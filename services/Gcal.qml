pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "../lib/gcal.js" as GcalLib

/**
 * Read-only Google Calendar, merged into the calendar surface beside the local
 * Events store. All the OAuth, token refresh and API paging lives in
 * scripts/gcal.py; this singleton just drives it — `list` for the connected
 * accounts, `sync` on open and every 15 minutes for their events, `auth` /
 * `disconnect` from the Calendars sub-surface — and parses the one JSON doc it
 * prints. Structure mirrors services/Weather.qml: async `Process` + guarded
 * JSON.parse, so startup never blocks and a network blip leaves the last good
 * `events` in place while `lastError` carries the reason.
 *
 * Events arrive already normalised to Events.qml's one-off shape
 * ({ id, date, endDate, time, endTime, text } plus { account, calendar }), so
 * `forDate` / `hasEvents` here match that singleton's signatures and the
 * surface can concatenate the two lists and sort once. Recurring events are
 * expanded to concrete instances by the API before we see them.
 *
 * Nothing here calls Date.now() or Math.random() (this engine throws on both —
 * see the Events.qml header); every timestamp is computed on the Python side.
 */
Singleton {
    id: root

    readonly property string script: Config.hyprPath("scripts", "gcal.py")

    /** [{ email }] for every connected account, from `gcal.py list`. */
    property var accounts: []
    /** Normalised, merged events across all accounts, from `gcal.py sync`. */
    property var events: []
    /** Per-account sync outcome: [{ email, ok, error }]. */
    property var accountStatus: []

    property bool ready: false
    property bool hasClient: false
    /** Stored OAuth client id/secret, so a retry can pre-fill the fields. */
    property string clientId: ""
    property string clientSecret: ""
    property string lastError: ""

    /** Live log for the connect flow in the Calendars sub-surface. */
    property string authLog: ""
    readonly property bool connecting: authProc.running
    readonly property bool syncing: syncProc.running

    readonly property bool enabled: Flags.gcalEnabled

    function refreshAll() {
        listProc.running = true;
        root.sync();
    }

    function sync() {
        if (!root.enabled || syncProc.running)
            return;
        syncProc.running = true;
    }

    /** Connect a new account. id/secret go via the environment, never argv. */
    function connect(clientId, clientSecret) {
        if (authProc.running)
            return;
        root.authLog = "opening browser…";
        authProc.environment = ({
            GCAL_CLIENT_ID: (clientId || "").trim(),
            GCAL_CLIENT_SECRET: (clientSecret || "").trim()
        });
        authProc.running = true;
    }

    function disconnect(email) {
        if (dcProc.running || !email)
            return;
        dcProc.command = ["python3", root.script, "disconnect", email];
        dcProc.running = true;
    }

    // --- date lookups, matching Events.qml -------------------------------

    function forDate(dateStr) {
        return root.enabled ? GcalLib.forDate(root.events, dateStr) : [];
    }

    function hasEvents(dateStr) {
        return root.enabled && GcalLib.hasEvents(root.events, dateStr);
    }

    Component.onCompleted: {
        clientProbe.reload();
        listProc.running = true;
        root.sync();
    }

    Connections {
        target: Flags
        function onGcalEnabledChanged() {
            if (Flags.gcalEnabled)
                root.sync();
        }
    }

    /** Cheap check for whether client.json exists yet, so the surface can show
        or hide the credential fields without shelling out. */
    FileView {
        id: clientProbe
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
            + "/fukushima/gcal/client.json"
        blockLoading: true
        printErrors: false
        onLoaded: {
            var t = clientProbe.text().trim();
            root.hasClient = t.length > 0;
            try {
                var c = JSON.parse(t);
                root.clientId = (c && c.client_id) || "";
                root.clientSecret = (c && c.client_secret) || "";
            } catch (e) {
                root.clientId = "";
                root.clientSecret = "";
            }
        }
        onLoadFailed: {
            root.hasClient = false;
            root.clientId = "";
            root.clientSecret = "";
        }
    }

    Process {
        id: listProc
        command: ["python3", root.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    if (d && Array.isArray(d.accounts))
                        root.accounts = d.accounts;
                } catch (e) {}
            }
        }
    }

    Process {
        id: syncProc
        // Window (past/future days) is gcal.py's default — kept there, not duplicated here.
        command: ["python3", root.script, "sync"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    if (!d || !Array.isArray(d.events)) {
                        root.lastError = (d && d.error) || "bad sync response";
                        return;
                    }
                    root.accountStatus = Array.isArray(d.accounts) ? d.accounts : [];
                    var bad = root.accountStatus.filter(function (a) { return !a.ok; });
                    root.lastError = bad.length > 0
                        ? bad[0].email + ": " + bad[0].error : "";
                    // Every account failed and nothing came back — almost always
                    // an offline blip. Keep the last good list rather than
                    // blanking the grid; the next tick recovers.
                    if (d.ok === false && d.events.length === 0
                        && root.accountStatus.length > 0 && bad.length === root.accountStatus.length)
                        return;
                    root.events = d.events;
                    root.ready = true;
                } catch (e) {
                    root.lastError = "sync parse failed";
                }
            }
        }
    }

    Process {
        id: authProc
        command: ["python3", root.script, "auth"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    if (d && d.email)
                        root.authLog = "connected " + d.email;
                } catch (e) {}
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (this.text.trim().length > 0)
                root.authLog = this.text.trim().split("\n").pop()
        }
        onExited: function (exitCode) {
            authProc.environment = ({});
            if (exitCode !== 0 && root.authLog.indexOf("connected ") !== 0)
                root.authLog = root.authLog || "connect failed";
            clientProbe.reload();
            root.refreshAll();
        }
    }

    Process {
        id: dcProc
        stdout: StdioCollector {}
        onExited: root.refreshAll()
    }

    Timer {
        interval: 900000
        running: root.enabled
        repeat: true
        onTriggered: root.sync()
    }
}
