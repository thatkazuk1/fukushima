#!/usr/bin/env python3
"""Google Calendar bridge for the Fukushima calendar surface.

Read-only. Owns the OAuth 2.0 dance (loopback + PKCE, Desktop-app client),
token refresh, and normalising Google's events into the exact shape
services/Events.qml already stores, so the QML side only ever sees:

    { id, account, calendar, date, endDate, time, endTime, text, allDay }

with date / endDate as zero-padded "YYYY-MM-DD" and time / endTime as "HH:MM"
or "" for an all-day entry — a plain string compare then spans and orders
dates the same way local events do.

Everything lives under ~/.local/state/fukushima/gcal/ with 0600 perms:

    client.json      { client_id, client_secret }        written on first connect
    <email>.json     { email, refresh_token, access_token, expiry }   per account

No third-party packages — stdlib only (mirrors scripts/wallcolors.py).

Subcommands
    auth       --client-id ID --client-secret SECRET   (or $GCAL_CLIENT_ID /
               $GCAL_CLIENT_SECRET, or a pre-existing client.json)
    list       -> { "accounts": [ { "email": "..." } ] }
    disconnect <email>
    sync       [--days-back N] [--days-fwd M]
               -> { ok, accounts: [ { email, ok, error } ], events: [ ... ] }
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import hashlib
import http.server
import json
import os
import secrets
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from datetime import datetime, timedelta, timezone

AUTH_URI = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URI = "https://oauth2.googleapis.com/token"
REVOKE_URI = "https://oauth2.googleapis.com/revoke"
CAL_LIST_URI = "https://www.googleapis.com/calendar/v3/users/me/calendarList"
EVENTS_URI = "https://www.googleapis.com/calendar/v3/calendars/{cal}/events"
SCOPES = "openid email https://www.googleapis.com/auth/calendar.readonly"

STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
    "fukushima",
    "gcal",
)
CLIENT_FILE = os.path.join(STATE_DIR, "client.json")

HTTP_TIMEOUT = 20
AUTH_WAIT = 600  # seconds to wait for the browser redirect


# --------------------------------------------------------------------------- io


def _ensure_dir() -> None:
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    with contextlib.suppress(OSError):
        os.chmod(STATE_DIR, 0o700)


def _read_json(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
            return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _write_json(path: str, data: dict) -> None:
    _ensure_dir()
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def _account_path(email: str) -> str:
    safe = email.replace("/", "_").replace("\\", "_")
    return os.path.join(STATE_DIR, safe + ".json")


def _account_files() -> list[str]:
    try:
        names = sorted(os.listdir(STATE_DIR))
    except OSError:
        return []
    out = []
    for name in names:
        if not name.endswith(".json") or name in ("client.json", "client.json.tmp"):
            continue
        out.append(os.path.join(STATE_DIR, name))
    return out


# ----------------------------------------------------------------------- client


def _load_client(args: argparse.Namespace | None = None) -> dict:
    cid = getattr(args, "client_id", None) or os.environ.get("GCAL_CLIENT_ID")
    csecret = getattr(args, "client_secret", None) or os.environ.get(
        "GCAL_CLIENT_SECRET"
    )
    if cid and csecret:
        client = {"client_id": cid.strip(), "client_secret": csecret.strip()}
        _write_json(CLIENT_FILE, client)
        return client
    client = _read_json(CLIENT_FILE)
    if client.get("client_id") and client.get("client_secret"):
        return client
    raise SystemExit(
        "no OAuth client configured — pass --client-id/--client-secret once "
        "(see docs/GCAL-SETUP.md)"
    )


# ------------------------------------------------------------------------- http


def _post_form(url: str, fields: dict) -> dict:
    body = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/x-www-form-urlencoded"}
    )
    with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
        return json.load(resp)


def _get_json(url: str, token: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
        return json.load(resp)


# -------------------------------------------------------------------------- auth


class _CatchHandler(http.server.BaseHTTPRequestHandler):
    """Catches the OAuth redirect. Only a request that actually carries `code`
    or `error` finishes the wait — a favicon fetch, a browser speculative
    connection or a bare `/` hit is answered 204 and ignored, so the parent
    doesn't bail thinking the redirect "arrived" empty."""

    result: dict = {}
    done: "threading.Event" = threading.Event()

    def do_GET(self) -> None:  # noqa: N802 (stdlib naming)
        params = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        code = (params.get("code") or [None])[0]
        error = (params.get("error") or [None])[0]
        if not code and not error:
            self.send_response(204)
            self.end_headers()
            return

        _CatchHandler.result = {
            "code": code,
            "error": error,
            "state": (params.get("state") or [None])[0],
        }
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        msg = (
            "Calendar connected — you can close this tab."
            if code
            else "Authorisation failed — you can close this tab."
        )
        self.wfile.write(
            b"<!doctype html><meta charset=utf-8>"
            b"<body style='font:16px system-ui;padding:3rem;text-align:center'>"
            + msg.encode()
            + b"</body>"
        )
        _CatchHandler.done.set()

    def log_message(self, *_args) -> None:  # silence the default stderr spam
        pass


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def cmd_auth(args: argparse.Namespace) -> int:
    client = _load_client(args)

    verifier = (
        base64.urlsafe_b64encode(secrets.token_bytes(48)).rstrip(b"=").decode()
    )
    challenge = (
        base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest())
        .rstrip(b"=")
        .decode()
    )
    state = secrets.token_urlsafe(24)
    port = _free_port()
    redirect = f"http://127.0.0.1:{port}"

    query = urllib.parse.urlencode(
        {
            "client_id": client["client_id"],
            "redirect_uri": redirect,
            "response_type": "code",
            "scope": SCOPES,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
            "state": state,
            "access_type": "offline",
            "prompt": "consent",
        }
    )
    url = AUTH_URI + "?" + query

    _CatchHandler.result = {}
    _CatchHandler.done = threading.Event()
    server = http.server.HTTPServer(("127.0.0.1", port), _CatchHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    sys.stderr.write("opening browser for Google sign-in…\n")
    sys.stderr.flush()
    if not webbrowser.open(url):
        sys.stderr.write("could not open a browser automatically. Visit:\n" + url + "\n")

    got = _CatchHandler.done.wait(timeout=AUTH_WAIT)
    server.shutdown()
    server.server_close()

    holder = _CatchHandler.result
    if not got and not holder:
        raise SystemExit("timed out waiting for the browser redirect")
    if holder.get("error"):
        raise SystemExit("authorisation denied: " + holder["error"])
    if holder.get("state") != state:
        raise SystemExit("state mismatch — try connecting again")
    code = holder.get("code")
    if not code:
        raise SystemExit("no authorisation code in the redirect")

    try:
        tok = _post_form(
            TOKEN_URI,
            {
                "client_id": client["client_id"],
                "client_secret": client["client_secret"],
                "code": code,
                "code_verifier": verifier,
                "grant_type": "authorization_code",
                "redirect_uri": redirect,
            },
        )
    except urllib.error.HTTPError as exc:
        raise SystemExit("token exchange failed: " + exc.read().decode(errors="replace"))
    except (urllib.error.URLError, OSError) as exc:
        raise SystemExit("token exchange failed (offline?): %s" % exc)

    if not tok.get("refresh_token"):
        raise SystemExit(
            "Google returned no refresh token — revoke the app's access at "
            "myaccount.google.com and connect again"
        )

    email = _email_from_id_token(tok.get("id_token", "")) or _email_from_userinfo(
        tok["access_token"]
    )
    if not email:
        raise SystemExit("could not determine the account email")

    _write_json(
        _account_path(email),
        {
            "email": email,
            "refresh_token": tok["refresh_token"],
            "access_token": tok.get("access_token", ""),
            "expiry": _expiry(tok.get("expires_in", 0)),
        },
    )
    print(json.dumps({"ok": True, "email": email}))
    return 0


def _email_from_id_token(id_token: str) -> str:
    try:
        payload = id_token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload))
        return claims.get("email", "") if claims.get("email_verified", True) else ""
    except (ValueError, IndexError):
        return ""


def _email_from_userinfo(access_token: str) -> str:
    try:
        info = _get_json("https://openidconnect.googleapis.com/v1/userinfo", access_token)
        return info.get("email", "")
    except (urllib.error.URLError, ValueError, OSError):
        return ""


# ------------------------------------------------------------------------ tokens


def _expiry(expires_in) -> str:
    try:
        secs = int(expires_in)
    except (TypeError, ValueError):
        secs = 0
    return (datetime.now(timezone.utc) + timedelta(seconds=max(0, secs - 60))).isoformat()


def _valid_access_token(acct_path: str, client: dict) -> tuple[str, str]:
    """Return (token, error). Refreshes and persists when the cached one is stale."""
    acct = _read_json(acct_path)
    if not acct.get("refresh_token"):
        return "", "not connected"

    exp = acct.get("expiry", "")
    fresh = False
    try:
        fresh = bool(acct.get("access_token")) and datetime.fromisoformat(
            exp
        ) > datetime.now(timezone.utc)
    except ValueError:
        fresh = False
    if fresh:
        return acct["access_token"], ""

    try:
        tok = _post_form(
            TOKEN_URI,
            {
                "client_id": client["client_id"],
                "client_secret": client["client_secret"],
                "refresh_token": acct["refresh_token"],
                "grant_type": "refresh_token",
            },
        )
    except urllib.error.HTTPError as exc:
        return "", "token refresh failed (%d)" % exc.code
    except (urllib.error.URLError, OSError) as exc:
        return "", "offline: %s" % exc

    if not tok.get("access_token"):
        return "", "token refresh returned nothing"
    acct["access_token"] = tok["access_token"]
    acct["expiry"] = _expiry(tok.get("expires_in", 0))
    if tok.get("refresh_token"):
        acct["refresh_token"] = tok["refresh_token"]
    _write_json(acct_path, acct)
    return acct["access_token"], ""


# -------------------------------------------------------------------- normalise


def _pad(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%d")


def _parse_rfc3339(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _normalise(ev: dict, email: str, cal_name: str) -> dict | None:
    start = ev.get("start") or {}
    end = ev.get("end") or {}
    title = ev.get("summary") or "(no title)"
    uid = "%s#%s" % (email, ev.get("id", secrets.token_hex(6)))

    if start.get("date"):
        # All-day. Google's end.date is exclusive → step back a day.
        try:
            s = datetime.fromisoformat(start["date"])
        except ValueError:
            return None
        e = s
        if end.get("date"):
            with contextlib.suppress(ValueError):
                e = datetime.fromisoformat(end["date"]) - timedelta(days=1)
        if e < s:
            e = s
        return {
            "id": uid,
            "account": email,
            "calendar": cal_name,
            "date": _pad(s),
            "endDate": "" if _pad(e) == _pad(s) else _pad(e),
            "time": "",
            "endTime": "",
            "text": title,
            "allDay": True,
        }

    if not start.get("dateTime"):
        return None
    try:
        s = _parse_rfc3339(start["dateTime"]).astimezone()
        e = _parse_rfc3339(end["dateTime"]).astimezone() if end.get("dateTime") else s
    except ValueError:
        return None
    return {
        "id": uid,
        "account": email,
        "calendar": cal_name,
        "date": _pad(s),
        "endDate": "" if _pad(e) == _pad(s) else _pad(e),
        "time": s.strftime("%H:%M"),
        "endTime": e.strftime("%H:%M"),
        "text": title,
        "allDay": False,
    }


# -------------------------------------------------------------------------- sync


def _fetch_account(acct_path: str, client: dict, time_min: str, time_max: str) -> tuple:
    email = _read_json(acct_path).get("email", os.path.basename(acct_path)[:-5])
    token, err = _valid_access_token(acct_path, client)
    if err:
        return email, [], err

    try:
        cal_list = _get_json(CAL_LIST_URI, token)
    except urllib.error.HTTPError as exc:
        return email, [], "calendar list failed (%d)" % exc.code
    except (urllib.error.URLError, ValueError, OSError) as exc:
        return email, [], "offline: %s" % exc

    events: list[dict] = []
    for cal in cal_list.get("items", []):
        cal_id = cal.get("id")
        if not cal_id or cal.get("selected") is False:
            continue
        cal_name = cal.get("summaryOverride") or cal.get("summary") or cal_id
        page_token = None
        for _ in range(20):  # page guard
            query = {
                "singleEvents": "true",
                "orderBy": "startTime",
                "timeMin": time_min,
                "timeMax": time_max,
                "maxResults": "2500",
                "fields": "items(id,summary,start,end,status),nextPageToken",
            }
            if page_token:
                query["pageToken"] = page_token
            url = EVENTS_URI.format(
                cal=urllib.parse.quote(cal_id, safe="")
            ) + "?" + urllib.parse.urlencode(query)
            try:
                page = _get_json(url, token)
            except (urllib.error.HTTPError, urllib.error.URLError, ValueError, OSError):
                break
            for ev in page.get("items", []):
                if ev.get("status") == "cancelled":
                    continue
                norm = _normalise(ev, email, cal_name)
                if norm:
                    events.append(norm)
            page_token = page.get("nextPageToken")
            if not page_token:
                break
    return email, events, ""


def cmd_sync(args: argparse.Namespace) -> int:
    files = _account_files()
    result = {"ok": True, "accounts": [], "events": []}
    if not files:
        print(json.dumps(result))
        return 0

    try:
        client = _load_client(args)
    except SystemExit as exc:
        print(json.dumps({"ok": False, "accounts": [], "events": [], "error": str(exc)}))
        return 0

    now = datetime.now(timezone.utc)
    time_min = (now - timedelta(days=args.days_back)).isoformat()
    time_max = (now + timedelta(days=args.days_fwd)).isoformat()

    for path in files:
        email, events, err = _fetch_account(path, client, time_min, time_max)
        result["accounts"].append({"email": email, "ok": not err, "error": err})
        result["events"].extend(events)
        if err:
            result["ok"] = False

    result["events"].sort(key=lambda e: (e["date"], e["time"] or "", e["text"]))
    print(json.dumps(result))
    return 0


# ------------------------------------------------------------------ list/remove


def cmd_list(_args: argparse.Namespace) -> int:
    accounts = []
    for path in _account_files():
        email = _read_json(path).get("email")
        if email:
            accounts.append({"email": email})
    print(json.dumps({"accounts": accounts}))
    return 0


def cmd_disconnect(args: argparse.Namespace) -> int:
    path = _account_path(args.email)
    acct = _read_json(path)
    token = acct.get("refresh_token") or acct.get("access_token")
    if token:
        with contextlib.suppress(Exception):
            _post_form(REVOKE_URI, {"token": token})
    with contextlib.suppress(OSError):
        os.remove(path)
    print(json.dumps({"ok": True, "email": args.email}))
    return 0


# -------------------------------------------------------------------------- main


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="gcal.py", description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_auth = sub.add_parser("auth", help="connect a Google account")
    p_auth.add_argument("--client-id")
    p_auth.add_argument("--client-secret")
    p_auth.set_defaults(func=cmd_auth)

    sub.add_parser("list", help="list connected accounts").set_defaults(func=cmd_list)

    p_sync = sub.add_parser("sync", help="fetch events from every connected account")
    p_sync.add_argument("--days-back", type=int, default=35)
    p_sync.add_argument("--days-fwd", type=int, default=180)
    p_sync.add_argument("--client-id")
    p_sync.add_argument("--client-secret")
    p_sync.set_defaults(func=cmd_sync)

    p_dc = sub.add_parser("disconnect", help="revoke and forget an account")
    p_dc.add_argument("email")
    p_dc.set_defaults(func=cmd_disconnect)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except SystemExit:
        raise
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit as exc:
        if exc.code not in (0, None) and isinstance(exc.code, str):
            sys.stderr.write(exc.code + "\n")
            sys.exit(1)
        raise
