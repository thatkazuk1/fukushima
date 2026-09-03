# Developing Ukishima

A ground-up orientation for working on this codebase, aimed at someone new to
Qt/QML.

## 1. What this project actually is

Ukishima is **not a compiled application**. There is no C++, no CMake, no build
step, no binary to produce. It is a **[Quickshell](https://quickshell.outfoxxed.me)
configuration**: a tree of `.qml` files (plus a little JavaScript and some shell
scripts) that the `quickshell` binary loads and interprets at runtime.

The stack, from the bottom up:

| Layer | What it gives you | Where you see it |
| --- | --- | --- |
| **QML** — the language | Declarative object tree with JavaScript expressions and functions. Familiar if you've seen JSON + JS. | every `.qml` file |
| **Qt Quick** — the toolkit | The visual primitives: `Item`, `Rectangle`, `Text`, `MouseArea`, `Image`, plus animations, `Behavior`, `states`, `Loader`. | `components/`, `modules/` |
| **Quickshell** — the shell runtime | Desktop-shell types Qt doesn't have: `PanelWindow` (a Wayland layer-shell surface), `Variants` (one delegate per screen), `IpcHandler`, `FileView` + `JsonAdapter` (config files), `Process` (subprocesses), and the `Quickshell.Hyprland` / `.Wayland` / `.Io` modules. | `shell.qml`, `services/` |
| **Hyprland** | The Wayland compositor Ukishima decorates and talks to over `hyprctl` IPC. | `services/Spaces.qml`, `lib/monitors.js` |

Practical consequence: the dev loop is **edit a file → reload the shell → look at
it**. You will never run `qmake` or `cmake`.

### The shape of the code

The layout follows the standard Quickshell config convention — see
[`ARCHITECTURE.md`](ARCHITECTURE.md) for the full picture.

- **`shell.qml`** — the root (must be at the repo root). Creates, per monitor, a
  zero-height "reserve" window (claims an exclusive zone so tiled windows sit
  below the pill) and a full-screen transparent "overlay" window hosting the
  pill. Also holds the IPC handlers and the battery-notification logic.
- **`config/`** — settings singletons (`Config`, `Flags`) and design tokens
  (`Theme`, `Motion`). Declared `singleton` in `config/qmldir`.
- **`services/`** — the 17 system-state providers (`Battery`, `Weather`,
  `Players`, `Cava`, `Sysmon`, `Notifs`, …). `services/qmldir`.
- **`components/`** — small reusable primitives (faders, dropdown, tray, tooltip).
- **`modules/`** — the shell features:
  - `modules/pill/Pill.qml` — the morphing pill. Still one enormous `Item`
    holding the state for every surface (the next refactor target).
  - `modules/surfaces/` — the panels that grow out of the pill. Loaded on demand.
  - `modules/osd/` — the volume/brightness/workspace flash.
- **`lib/`** — pure JavaScript, no QML deps, unit-tested with plain Node.
- **`scripts/`** — shell helpers invoked via `Process`. Stays at the repo root
  because Hyprland keybinds reference `~/.config/quickshell/scripts/…` by path.
- **`hypr/`** — Hyprland-side fragments (`decoration.lua`, `hyprsunset.conf`).
- **`assets/`** — bundled media (the preview gallery).

## 2. Prerequisites

You are developing on the machine that runs the shell, so most of this is
already present. Check with `just doctor` once `just` is installed, or by hand:

```bash
quickshell --version      # 0.3.x+
hyprctl version           # any recent 0.4x/0.5x
node --version             # 18+  (for the lib/ tests)
```

### Install the task runner and QML tools

```bash
sudo apt install just
```

The QML tooling (`qmllint`, `qmlformat`, `qmlls`) ships with Qt but is usually
not on `PATH`. On this machine it lives in `/usr/lib/qt6/bin`. The `Justfile`
finds it automatically; for interactive use, add it to your shell:

```bash
export PATH="/usr/lib/qt6/bin:$PATH"
```

### Editor setup

Install the **Qt Qml** extension (VS Code: `theqtcompany.qt-qml`, or the Qt
plugin for your editor). It drives `qmlls`, the QML language server.
`.vscode/settings.json` points it at the system `qmlls` in `/usr/lib/qt6/bin`.

**How Quickshell types reach the editor.** Quickshell compiles its QML modules
into the `quickshell` binary, but when it runs it also mirrors them (and your
config tree) into a per-config VFS under
`/run/user/$UID/quickshell/vfs/<shell-id>/` and writes a `.qmlls.ini` into the
repo pointing `qmlls` at it ("QML tooling support enabled" in the launch log).

Consequences:

- The live shell (loaded from this repo) populates that VFS mirror and
  writes/refreshes `.qmlls.ini` while it runs and an editor is connected, so
  Quickshell types resolve for `qmlls` in a normal session. `/run/user` is a
  tmpfs; a reboot rebuilds it on next login. (A `just dev` session does the same
  for its own config id.)
- `.qmlls.ini` is **git-ignored** — it holds absolute machine-specific paths and
  is disposable. Don't commit it. If your editor isn't picking up Quickshell
  types, confirm the file exists and points into a `vfs/<id>/` that still exists.
- `qmllint` does **not** use the VFS, so it still can't type-check Quickshell
  types. `.qmllint.ini` silences that family and keeps the checks that work
  without types. That's why `just lint` is real but limited.

Keep the [Quickshell type reference](https://quickshell.outfoxxed.me/docs/) open
regardless.

## 3. Running your changes

This repo **is** the live shell. `~/.config/quickshell` is a symlink to it, so
Hyprland's `exec-once = ... exec quickshell` loads this tree and the shell uses
your real `~/.local/state/ukishima` state. Quickshell hot-reloads QML on save,
so editing a file *is* the dev loop — nothing to run.

After changing a **singleton** (or anything not hot-reloadable), restart:

```bash
qs kill
hyprctl dispatch exec quickshell
```

**Large structural edits: stop the shell first.** Quickshell 0.3.1 can crash
during engine teardown on rapid consecutive hot-reloads (saving several files in
a row). For a multi-file refactor, `qs kill`, make all the changes, `just
check`, then start it once.

To try something risky **without touching live state**, run a throwaway
instance with its own `./.dev/` state/cache (git-ignored):

```bash
just dev           # Ctrl-C to stop
just dev-kill      # if it wedges
just dev-clean     # wipe ./.dev/ for a clean-slate settings test
```

Two shells can't both own the `ukishima` IPC id and layer namespace cleanly, so
stop the live one (`qs kill`) before a `just dev` session you need to *see*.

Drive surfaces over IPC just like the real keybinds do:

```bash
just ipc launcher ""      # open the launcher on the focused monitor
just ipc page "" wifi     # open an arbitrary surface by name
```

## 4. Checks

```bash
just lint     # qmllint over every .qml  (config: .qmllint.ini)
just test     # run every lib/*.test.mjs under Node
just check    # both — this is what CI runs
```

`just lint` is currently clean.

There is no automated UI test (it needs a compositor). After a
behaviour-preserving change, walk [`SMOKE-TEST.md`](SMOKE-TEST.md) — a manual
click-through of every surface and pill state.

### Formatting

`qmlformat` has no maximum-line-width setting, so it collapses the intentional
manual wrapping throughout this codebase into unreadable long lines. It is
therefore **not enforced** and **not part of `just check`**. `.editorconfig`
(4-space indent for QML/JS) plus code review are the style baseline. If you want
to mechanically tidy a single new file: `just fmt path/to/File.qml`, then read
the diff before committing.

## 5. Writing testable logic

Anything that is pure data transformation — parsing `hyprctl` output, fuzzy
matching, arithmetic — belongs in `lib/` as a plain `.mjs`/`.js` module with a
sibling `*.test.mjs`, not inline in a `.qml` file. See `lib/monitors.js` and
`lib/monitors.test.mjs` for the pattern (a tiny hand-rolled `eq`/`ok` harness,
no dependencies). This keeps the logic exercisable in CI without a compositor.

## 6. Conventions

- 4-space indent, `lf`, final newline (`.editorconfig` enforces).
- One QML component per file; register it in the directory's `qmldir`.
- A singleton is `config/` if it holds settings or design tokens, `services/`
  if it models live system state.
- Persisted settings go through `config/Flags.qml` (a `JsonAdapter` over
  `$XDG_STATE_HOME/ukishima/flags.json`).
- Import `config/` and `services/` only where actually used — `qmllint` flags a
  dead directory import.
- Keep block comments explaining *why* — the existing ones are load-bearing
  documentation of hard-won Wayland/Hyprland behaviour.
