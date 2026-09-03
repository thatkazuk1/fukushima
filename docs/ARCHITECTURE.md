# Architecture

## It is not a compiled Qt project

A compiled Qt/QML application is a **CMake project**: `CMakeLists.txt`, C++ in
`src/`, `qt_add_qml_module()` declaring a module URI, a `.qrc` bundling
resources, a build directory producing a binary. None of that applies here.

Ukishima is a **Quickshell configuration** — a directory the `quickshell` binary
reads at startup and interprets. The reference point is not "a Qt app," it is
"a well-organised Quickshell config," and that ecosystem has a settled layout.

## Layout

```
shell.qml            entry point — MUST sit at the repo root
config/              settings singletons + design tokens
services/            live system-state providers
components/          reusable UI primitives
modules/
  pill/              the morphing pill
  surfaces/          the panels that grow from the pill
  osd/               the volume / brightness / workspace flash
lib/                 pure JavaScript (+ its Node tests)
scripts/             shell helpers run via Process
hypr/                Hyprland-side config fragments
assets/              bundled media
docs/
```

The organising principle: **settings, system logic, and UI stay separate.**

| Dir | Rule of thumb |
| --- | --- |
| `config/` | A singleton belongs here if it holds user settings (`Config`, `Flags`) or design tokens read everywhere (`Theme`, `Motion`). |
| `services/` | A singleton belongs here if it models something about the running system — a device, a daemon, a feed (`Battery`, `Weather`, `Players`, `Cava`, `Notifs`, …). |
| `components/` | A QML type with no domain knowledge — a fader, a glyph, a tooltip. Reusable by anything. |
| `modules/` | A shell *feature*. Knows about surfaces, the pill, the compositor. Not reused outside the shell. |
| `lib/` | Logic with zero QML imports, so it can be unit-tested under plain Node. Parsing, ranking, arithmetic. |

## Imports

There is no build step and no module URI, so QML types resolve by **directory
import relative to the importing file**:

```qml
// a file in modules/surfaces/
import "../../config"      // Theme, Motion, Flags, Config
import "../../services"    // Battery, Weather, …
import "../../components"  // HFader, GlyphIcon, …
```

Each importable directory carries a `qmldir` listing its types (`Foo Foo.qml`,
or `singleton Foo Foo.qml`). `shell.qml`, at the root, imports by path from the
root (`import "modules/pill"`).

Rules:

- Import `config/` and `services/` **only where used** — `qmllint`'s
  `unused-imports` catches a dead directory import.
- A singleton that reads another singleton across the `config` / `services` line
  needs an explicit import (e.g. `config/Theme.qml` imports `../services` for
  `Dyn`; the services that read `Config`/`Flags` import `../config`).
- Same-directory types resolve with no import.

## Hard constraints

- **`shell.qml` stays at the repo root.** Quickshell's config discovery looks
  for `<config dir>/shell.qml`; Hyprland runs bare `quickshell` (the "default"
  config = `~/.config/quickshell/shell.qml`, a symlink to this repo).
- **`scripts/` stays at the repo root.** Hyprland keybinds and `exec-once` lines
  call `~/.config/quickshell/scripts/…` by absolute path. `Config.hyprPath()`
  resolves everything else against the repo root, so the shell never depends on
  its launch directory.
- Paths under `$XDG_STATE_HOME/ukishima` and `$XDG_CACHE_HOME/ukishima` are the
  runtime state contract — see the README's State & Cache section.

## Known debt

- **`modules/pill/Pill.qml`** is one ~3000-line `Item` holding the state for
  every surface. The next refactor splits it into per-concern controllers in
  place.
- **`config/Flags.qml`** is a single flat `JsonAdapter` with ~60 properties;
  it wants grouping (`record.*`, `night.*`, `wallpaper.*`, `ui.*`).
- **`hypr/decoration.lua`**, `services/Spaces.qml`'s lua writer, and
  `lib/monitors.js` assume a Lua-configured Hyprland. On a hyprlang setup the
  first two are inert and `lib/monitors.js` is orphaned (only its test uses it).
