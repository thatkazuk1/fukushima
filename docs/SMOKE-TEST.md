# Ukishima smoke test

A manual click-through of everything the shell does, to run **after each
refactor commit** in Phase 2. The refactor is behaviour-preserving, so anything
that changes here is a regression to investigate before moving on.

## How to run it

The repo is the live shell, so a QML change is already on screen. Drive surfaces
with `just ipc <handler>` or the real keybinds. Work top to bottom; tick what
still holds. A full pass is ~10 minutes.

To test against first-run defaults instead of your saved settings, use a
throwaway instance: `qs kill` (stop the live shell), then `just dev` +
`just dev-clean`.

Legend: **T** = how to trigger · **E** = expected

---

## 1. Resting pill (collapsed face)

Set the face in Appearance → Display, or edit `~/.local/state/ukishima/flags.json`
`mainDisplay`.

- [ ] **minimal** — T: default · E: Japanese glyph + time only, centred capsule
- [ ] **classic** — E: date + time
- [ ] **system** — E: weekday, time, active-workspace dots, keyboard layout, battery
- [ ] **strip** — E: pill becomes a full-width top bar flush to the screen edge; workspace tracker on the left
- [ ] Clock ticks; `time12h` / `clockSeconds` in flags take effect live
- [ ] `showGlyphs: false` removes the kanji without reflowing badly
- [ ] Reserved zone: tiled windows sit **below** the pill, and the gap tracks `topGap` / `appGap`

## 2. Expand / collapse / pin

- [ ] Hover the pill → morphs open **in place** (no popup), hover row of module icons appears
- [ ] Move pointer away → collapses back after its grace period
- [ ] Click the pill body → pins open (stays after pointer leaves)
- [ ] Click the backdrop (anywhere off the pill) → unpins / dismisses
- [ ] `Esc` with nothing open → closes/unpins
- [ ] **Auto-hide** (`autoHide: true`): pill retracts off the top edge; a thin
      top-centre strip reveals it on pointer touch; passing lower down does nothing
- [ ] **Fullscreen**: focus a fullscreen window on a monitor → that monitor's
      pill retracts and the layer goes click-through; unfullscreen → it returns
- [ ] Multi-monitor: hover row and surfaces open on the **focused** monitor only;
      `peek` shows a non-focused monitor's pill

## 3. Soul bead

- [ ] Hovering a module icon in the expanded row → the bead cursor glides to it
- [ ] Opening a surface → the bead docks at that surface's seam (e.g. media
      playback head, battery charge head, Link focused row)

---

## 4. Quick surfaces (`just ipc <name>`)

| Surface | `just ipc` | Trigger notes |
| --- | --- | --- |
| Launcher | `launcher` | SUPER+/ |
| Wallpaper | `wallpaper` | SUPER+SHIFT+W |
| Clipboard | `clipboard` | SUPER+SHIFT+V |
| Calendar | `calendar` | clock target |
| Media | `media` | only opens if a player is active |
| Mixer | `mixer` | |
| Link (inbox) | `link` | notification glyph |

- [ ] **Launcher** — search filters the app list; ranking favours fuzzy match +
      past launch frequency; `Enter` launches and closes; icons render
- [ ] **Wallpaper** — filmstrip, newest first; focused thumb large/lit,
      neighbours shrink+dim; wheel/arrows move focus; click a neighbour glides;
      `Enter`/tap on focused applies (strip stays open); hold focused thumb =
      heat fill → trashes file, early release drains
  - [ ] Type a printable char → local filter field appears, narrows by name
  - [ ] Wallhaven chip → remote feed; sort (Hot/Latest/Top/Random/Top Liked);
        paging; bare keys seed the search field; `Enter` runs a tag search;
        `Backspace` returns focus to the field after a search
  - [ ] Fit control (Cover/Contain/Stretch/Center) rescales in place
- [ ] **Clipboard** — populated as the morph finishes; substring filter; `Enter`
      copies + closes; hover row → dismiss glyph deletes; `Ctrl+X` deletes
      selection; image entries show cached thumbnail + size; hold 掃 = wipe all
- [ ] **Calendar** — month grid sized to the month's rows; today framed with the
      Ame ring; day with a stored event marked warm + ember dot; pick a day →
      editor slides open right (list, delete tap, add form: start/end/title);
      prev/next nav; view resets to today on each open
- [ ] **Media** — album art bleeds left + blurred glow; title/artist/source-time;
      奏/休 play-pause, 前/次 skips; progress stroke along the bottom; 2+ players →
      source token becomes a picker bubble
- [ ] **Mixer** — DND + Keep-Awake chips in the header; four vertical faders:
      brightness (ddcutil), vibrance (nvibrant), volume + mic (Pipewire) — each
      moves real hardware; arrow keys adjust the focused fader
- [ ] **Link / inbox** — grouped per app; critical entries pinned above the fold;
      clear-all; "silence" empty state; opening marks all seen after a beat

---

## 5. System surfaces

Reachable via `just ipc page "" <name>` and from the expanded hover row.

- [ ] **wifi** (`page "" wifi`) — network panel (NetInfo service):
  - [ ] vitals grid updates live: Ping / Packet Loss, Receiving / Sending,
        Downloaded / Uploaded (cumulative), IP Address / Gateway
  - [ ] **WI-FI BAND** row: header reads the live band when auto; AUTOMATIC
        toggle; pinning a band shows 2.4/5/6 pills and reconnects (auto-reverts
        with an error line if the AP doesn't serve it)
  - [ ] **QR glyph** → share card: scannable matrix, SSID, close chevron
  - [ ] **gauge glyph** → speed test: Start → ping/down/up fill in, Run again
  - [ ] list split into **KNOWN NETWORKS** / **OTHER NETWORKS**; secured unknown
        network → inline password row → `nmcli dev wifi connect`; disconnect /
        forget / show-password on a saved row; `Esc` / backdrop dismiss
- [ ] **bt** (`page "" bt`) — adapter toggle; scan with 25s auto-stop; known
      devices use Quickshell connect/disconnect; unpaired → pair-trust-connect
      with inline ember + transient failure line
- [ ] **battery** (`ipc battery`) — percentage hero + time-to-empty/full subline;
      charge meter; Rate/Health/Capacity stats (Health drops if UPower can't
      report; time line drops with no estimate); charging warms the tones;
      AC-full → "Plugged in". Absent on a desktop
- [ ] **sysmon** (`ipc sysmon`) — CPU/GPU/memory flame dials (270° arcs, eased);
      centre value + unit + sub (temp / mem total); hairline strip: net
      throughput, disk fill, swap, VRAM; no dGPU → GPU dial + VRAM cell drop and
      the rest recentre; polling only runs while open. (No speed test here any
      more — it moved to the wifi panel.)
- [ ] **weather** (`page "" weather`) — hero glyph + temp + humidity; hourly grid;
      5-day forecast under a hairline; pre-fetch → header + dim waiting hint only;
      editable location, falls back to IP auto-detect
- [ ] **recorder** (`ipc recorder`) — needs `gpu-screen-recorder`; header status
      (Idle / dot + m:ss / Get ready); config stage + options drawer (fps,
      quality, capture-cursor); action bar start→countdown→stop; press while
      idle → source chooser (Screen → monitor sub-chooser if >1; Window/Region →
      slurp); zero countdown starts immediately; filmstrip of recent clips
  - [ ] **quickRecord** (`ipc quickRecord`, SUPER+D) — one key cycles
        record→stop / countdown→cancel / chooser→dismiss / else open chooser
- [ ] **power** (`ipc power`) — safe group (lock/logout/sleep, fire on tap) |
      hairline | destructive group (restart/shutdown, press-and-hold heat fill,
      early release drains); arrow keys move focus; `Enter` fires safe at once,
      held `Enter` drives the heat fill on destructive
- [ ] **link editor** (`ipc link`) — keybind list from the lua config; rebind,
      add, remove, rename all write valid lua back (see `lib/binds.js`)
- [ ] **minimized tray** — `minimizeWindow`/`restoreWindow` (SUPER+M) move a
      window to/from `special:minimized`; tray row shows parked windows; click
      restores to the focused workspace

---

## 6. Settings hub

`just ipc page "" appearance` → four tiles. Each sub-surface: back chevron
returns to the index, empty click / cog closes.

- [ ] **appearance** index — four tiles (Display / Theme / Font / Interface)
- [ ] **display** (`page "" display`) — resting face mode, 12/24h, seconds,
      header glyphs, music visualizer — all live
- [ ] **theme** (`page "" theme`) — light / dark / dynamic-per-wallpaper /
      manual hue; manual mode reveals the rainbow hue strip + dark/light;
      dragging rebuilds the palette via `wallcolors.py --hue`, debounced,
      reloads Hyprland + terminal
- [ ] **fontpicker** (`page "" fontpicker`) — every installed family, each row
      self-previewing; click writes `Flags.uiFont`, whole shell re-renders;
      reset row → bundled Inter; current pick tinted
- [ ] **interface** (`page "" interface`) — UI scale, reduced motion, auto-hide
- [ ] **update** (`page "" update`) — pulls latest from GitHub, reloads in place;
      post-update toast names what landed

---

## 7. Transient / decoupled

- [ ] **OSD** — volume / brightness / workspace change → capsule grows from the
      top like a notch, holds, shrinks; the pill does **not** morph for these;
      level bars stay fixed size through the transition
- [ ] **Workspace flash** — on switch / alt-tab: the capsule shows the bare
      tracker line briefly, then morphs to the numbered row (active in a
      vermillion disc), holds ~2.2 s, fades. Per-monitor: only the switched
      monitor's capsule flashes
- [ ] **Toast** — an incoming notification renders in the pill body (icon,
      app eyebrow, summary + critical ember, body, action pills); click
      dismisses (stays in inbox); actions consume their own click; auto-expires
      unless critical
- [ ] **Game mode** (`ipc gameMode`) — self-contained Hyprland strip; exit chip;
      full-bar input mask; restores previous DND / viz / keep-awake / profile on
      exit

---

## 8. Services / live reactivity

- [ ] **Battery notifications** (`BatteryAlerts` singleton) — discharging past
      25 % / 20 % fire once each; 15 % opens a critical announce that repeats
      every 10 min until plugged in; re-arms on charge or rising back above
      25 %; "full" fires once at the actual full point (respects an 80 % limit)
- [ ] **NetInfo** — the wifi panel's grid, ping and band poll only while the
      surface is open, and stop when it closes
- [ ] **Dyn / palette** — changing the wallpaper retints the whole UI + terminal
      live (watches `colors.json`)
- [ ] **Flags** — a change written to `flags.json` by one instance shows up in
      the other on the next file event (DND, keep-awake, …)
- [ ] **Workspaces / monitors** — workspace switch, window open/close/move,
      monitor hotplug all update the pill; window drags / title spam do **not**
      trigger the triple model refresh
- [ ] **Players / Cava / Sysmon / Weather / Devices** — surfaces reflect live
      state, not a stale snapshot

## 9. Helper scripts

- [ ] `scripts/wallpaper.sh` — applies, animates the transition, handles
      live (`mpvpaper`) wallpapers, per-monitor assignment, the shuffle bag
- [ ] `scripts/wallpaper-thumbs.sh` / `cliphist-thumbs.sh` — thumbs generated on
      open, stale previews pruned
- [ ] `scripts/wallcolors.py` — palette + `--hue` manual build
- [ ] `scripts/gamemode.sh` — enter/exit game mode

---

## Known pre-existing quirks (not regressions)

- `Tooltip.qml` sets three horizontal anchors bound to `undefined`/one value —
  intentional, `qmllint`-suppressed with a comment.
- The README preview video is upstream Ukishima's, not this fork's.
