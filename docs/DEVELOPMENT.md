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
| **Hyprland** | The Wayland compositor Ukishima decorates and talks to over `hyprctl` IPC. | `services/Spaces.qml`, `components/Workspaces.qml` |

Practical consequence: the dev loop is **edit a file → reload the shell → look at
it**. You will never run `qmake` or `cmake`.

### The shape of the code

The layout follows the standard Quickshell config convention — see
[`ARCHITECTURE.md`](ARCHITECTURE.md) for the full picture.

- **`shell.qml`** — the root (must be at the repo root). Creates, per monitor, a
  zero-height "reserve" window (claims an exclusive zone so tiled windows sit
  below the pill) and a full-screen transparent "overlay" window hosting the
  pill. Also holds the IPC handlers and the per-monitor input routing.
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
plugin for your editor). `.vscode/` is checked in — `settings.json`, `tasks.json`
and `extensions.json` — so a fresh clone is configured on open. It runs `qmlls`,
the QML language server, pointed at the system Qt 6 build in `/usr/lib/qt6/bin`
(adjust `qt-qml.qmlls.customExePath` for your machine).

**One-time step to resolve our own types.** Quickshell only turns on editor
tooling when a `.qmlls.ini` already exists at the repo root. Seed it and reload
the shell once:

```bash
just qmlls-init          # touches .qmlls.ini
qs kill && hyprctl dispatch exec quickshell
```

Quickshell then mirrors the config tree into a VFS under
`/run/user/$UID/quickshell/vfs/<id>/` and rewrites `.qmlls.ini` (now a symlink)
to point `qmlls` at it, so our singletons and components resolve under the `qs`
module. The file is git-ignored — it holds absolute machine paths — and `/run`
is a tmpfs, so redo the `touch` + reload after a reboot if resolution drops.
The launch log prints `QML tooling support enabled` when it takes.

**What still won't resolve.** The Quickshell *framework* types — `PanelWindow`,
`Process`, `Variants`, `IpcHandler`, `Quickshell.Hyprland.*` — are compiled into
the `quickshell` binary (this distro build ships no on-disk type info), so
`qmlls` can't see them. `.qmllint.ini` mutes that family for both `qmlls` and
`qmllint`, so they don't show as errors, but you get no completion or hover for
them — keep the
[Quickshell type reference](https://quickshell.outfoxxed.me/docs/) open.

**A qmldom crash to know about.** A `function` *declaration* placed among the
statements of a QML binding block —

```qml
readonly property string x: {
    var c = foo;
    function helper() { ... }   // <-- crashes qmlls (Qt 6.10 qmldom bug)
    return helper(c);
}
```

— `SIGABRT`s `qmlls` outright (*"Could not construct the JS DOM"*). Hoist the
helper to a component method instead. Nested functions inside a *function
expression* (a `.sort(function () { ... })` callback, a signal handler body) are
fine — only the bare binding block bites.

Diagnostics also run from the terminal / CI:

- `just lint` — `qmllint` over every tracked `.qml` (`.qmllint.ini` config)
- `just check` — that plus the `lib/` JS tests; this is the CI gate
- the **`qmllint`** build task (<kbd>Ctrl+Shift+B</kbd>) routes findings into the
  Problems panel

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
matching, arithmetic — belongs in `lib/` as a plain `.js` module (loaded into
QML with `import "../../lib/x.js" as X` plus a trailing `module.exports` shim for
Node) with a sibling `*.test.mjs` using a tiny hand-rolled `eq`/`ok` harness, no
dependencies. This keeps the logic exercisable in CI without a compositor.
`lib/calc.js` and `lib/fuzzy.js` (both used by the launcher) have no tests yet
and are the obvious first candidates.

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
