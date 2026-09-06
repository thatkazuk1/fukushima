# 福島 Fukushima

A dynamic-island [Quickshell](https://quickshell.outfoxxed.me) shell for Hyprland — one morphing pill per monitor, every surface grown from the pill itself.

## Table of Contents

- [About the Project](#about-the-project)
- [Features](#features)
- [Preview](#preview)
- [Project Status](#project-status)
- [Getting Started](#getting-started)
  - [Dependencies](#dependencies)
  - [Technology Stack](#technology-stack)
  - [Third-party Services](#third-party-services)
- [Installation & Development](#installation--development)
  - [Setting Up](#setting-up)
  - [Keybinds](#keybinds)
  - [Development](#development)
  - [Testing](#testing)
  - [State & Cache](#state--cache)
  - [Uninstalling](#uninstalling)
- [How to Get Help](#how-to-get-help)
- [Contributing](#contributing)
- [Acknowledgements](#acknowledgements)
- [Authors](#authors)
  - [Repo Activity](#repo-activity)

## About the Project

Fukushima (福島) is a widget layer for Hyprland built around a single morphing pill at the top of every monitor. Collapsed, it is a thin warm-vermillion strip; hover it and it expands in place into a control centre — workspace dots, clock, media, system readouts — and every module grows its own surface out of the pill itself. Nothing ever pops up as a separate panel.

The project is fully self-contained. It makes no changes to existing Hyprland config files; the auto-launch line and the keybinds are the only things you add yourself.

This is a fork of amanhex's **Ukishima** (浮島, *"floating island"*) — the name keeps the *-shima*. See [Acknowledgements](#acknowledgements) for the full lineage. The IPC target, Wayland namespaces and state/cache paths are all `fukushima`; the **install directory** and the Quickshell **config name** below are still `ukishima` pending a rename.

## Features

- **Dynamic island** — one morphing pill per monitor, expanding in place with a bead cursor and smooth morph animations. Four collapsed faces (minimal / classic / system / strip).
- **Surfaces** grown from the pill: launcher, weather, calendar, media, mixer, wallpaper strip + online search, screen recorder, clipboard history, wifi, bluetooth, battery, power menu, system monitor, notification centre, minimized-window stash, OSD, toasts, and a settings hub (appearance → display, theme, font, interface, update).
- **Network panel** — the wifi surface carries a live vitals grid (ping / packet loss, receive + send rates, session totals, IP / gateway), a Wi-Fi band selector with an automatic mode, QR sharing, and an inline speed test, over the signal-sorted Known / Other network list with its connect / forget / show-password flow.
- **Wallpaper system** — `awww` backend with a shuffled bag, per-monitor assignment, animated transitions, live wallpapers (`mpvpaper`), a per-wallpaper fit control (Cover / Contain / Stretch / Center) that rescales the screen in place, and a live palette that retints the whole UI plus the terminal on every change; an online [Wallhaven](https://wallhaven.cc) browse/search with pagination, Hot / Latest / Top / Random / Top Liked sorting, and memory-only thumbnails (nothing cached to disk).
- **Screen recorder** — `gpu-screen-recorder` with slurp window/region picking, countdown, quality presets, audio, and a recent-clips filmstrip.
- **Weather** — Open-Meteo current conditions, hourly and five-day forecast in a dedicated surface, with an editable location (falls back to IP auto-detection).
- **Extras** — night light (hyprsunset), clipboard manager (cliphist), music visualiser (cava), game mode, quick-record keybind, keep-awake, and an in-app updater that pulls the latest release from GitHub.

## Preview

See the [preview gallery](assets/preview/README.md) for screenshots. These predate this
fork and will be refreshed once it diverges visually.

## Project Status

![status](https://img.shields.io/badge/status-active-brightgreen)
![quickshell](https://img.shields.io/badge/quickshell-0.3.0%2B-blue)
![hyprland](https://img.shields.io/badge/hyprland-0.4x%20%E2%80%93%200.5x-blue)
![license](https://img.shields.io/badge/license-MIT-lightgrey)
[![CI](https://github.com/thatkazuk1/ukishima/actions/workflows/ci.yml/badge.svg)](https://github.com/thatkazuk1/ukishima/actions/workflows/ci.yml)

Actively developed. The current focus is a structured engineering pass over the
forked codebase — a proper dev environment (done), a behaviour-preserving
refactor of the surface architecture, then new features. CI runs `qmllint` and
the pure-JS logic tests on every push.

## Getting Started

### Dependencies

#### Core

| Tool | Used for |
| --- | --- |
| `quickshell` | shell runtime |
| `hyprctl` | Hyprland IPC (workspaces, monitors, dispatch, reload) |
| `upower` | battery status and charge reporting (design capacity + cycle count read from `/sys/class/power_supply`) |
| `bluez` (`bluetoothctl`) | bluetooth surface |
| `jq` | JSON parsing in the helper scripts |
| `magick` (ImageMagick) | wallpaper thumbnails and palette |
| `awww` + `awww-daemon` | wallpaper backend |
| `ffmpeg` | video-wallpaper still extraction |
| `nmcli` (NetworkManager) | wifi surface, band selector |
| `qrencode` | Wi-Fi share QR in the network panel |
| `ip` / `ping` (iproute2, iputils) | network panel vitals |
| `brightnessctl` or `light` | backlight control |
| `cava` | music visualiser |
| `cliphist` + `wl-clipboard` | clipboard history |
| `slurp` | window/region picker for screen recording |
| `hyprsunset` | night light |

#### Optional, for full functionality

| Package | Adds |
| --- | --- |
| `gpu-screen-recorder` | the screen-recording backend (recording is disabled without it) |
| `mpvpaper` | animated / video wallpapers |
| `matugen` | Material base16 palettes (always-dark terminal theme) |
| `ddcutil` | monitor brightness via DDC (external display faders) |
| `kdialog` / `zenity` | native folder picker for the record output directory |
| `ghostty` | live terminal palette reload over D-Bus |
| `fastfetch` | recoloured system readout (needs `~/.config/fastfetch/config.jsonc.in`) |
| `hypridle` | idle / DPMS lock integration alongside the built-in keep-awake |

### Technology Stack

- **[Quickshell](https://quickshell.outfoxxed.me) 0.3.0+** — the shell runtime; must be built with the Hyprland, Wayland and Io QML modules. Ships Qt 6 / QtQuick.
- **[Hyprland](https://hypr.land)** — the Wayland compositor (developed on 0.56.1, works across recent 0.4x/0.5x). Talked to over `hyprctl` IPC.
- **QML** — the entire shell; no compiled component and no build step.
- **Bash** — the helper scripts under `scripts/` (wallpaper application, thumbnails, game mode), invoked via Quickshell's `Process`.
- **Python 3** — `scripts/wallcolors.py`, the palette / manual-hue generator.
- **Node** — runs the pure-JS logic tests under `lib/` (not needed at runtime).

### Third-party Services

- **[Open-Meteo](https://open-meteo.com)** — weather forecast (no API key; IP geolocation fallback via their companion service).
- **[Wallhaven](https://wallhaven.cc)** — the online wallpaper browse/search. Thumbnails are streamed from Wallhaven's CDN straight to QML and never touch disk.
- **GitHub** — the in-app updater pulls the latest commit of this repo.

## Installation & Development

### Setting Up

```bash
curl -fsSL https://raw.githubusercontent.com/thatkazuk1/ukishima/master/remote-install.sh | bash
```

This clones the project to `~/.local/share/quickshell/ukishima`, checks dependencies, and prints the auto-launch line and keybinds to add to your Hyprland config. If already installed, it pulls the latest changes instead.

To auto-launch, add to your Hyprland config:

```conf
# hyprlang (.conf)
exec-once = quickshell --config ~/.local/share/quickshell/ukishima
```

```lua
-- Lua
hl.exec_cmd("quickshell --config ~/.local/share/quickshell/ukishima")
```

Or launch it manually:

```bash
quickshell --config "$HOME/.local/share/quickshell/ukishima"
```

**Already installed?** Pull updates from the **Update** sub-surface inside the pill's settings (Appearance → Update), rerun the install command, or `git pull` in the install directory.

### Keybinds

Every surface and action is exposed over Quickshell IPC (target `fukushima`). The `""` argument is the monitor — empty means "focused monitor". Bind whichever you want in your Hyprland config:

```conf
# hyprlang (.conf)
bind = SUPER, SHIFT+W, exec, qs -p ~/.local/share/quickshell/ukishima ipc call fukushima wallpaper ""
bind = SUPER, SHIFT+V, exec, qs -p ~/.local/share/quickshell/ukishima ipc call fukushima clipboard ""
bind = SUPER, slash,   exec, qs -p ~/.local/share/quickshell/ukishima ipc call fukushima launcher ""
```

```lua
-- Lua
hl.bind(var_mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("qs -p ~/.local/share/quickshell/ukishima ipc call fukushima wallpaper \"\""))
hl.bind(var_mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("qs -p ~/.local/share/quickshell/ukishima ipc call fukushima clipboard \"\""))
hl.bind(var_mainMod .. " + slash",     hl.dsp.exec_cmd("qs -p ~/.local/share/quickshell/ukishima ipc call fukushima launcher \"\""))
```

If you cloned to `~/.config/quickshell/ukishima` instead, replace `qs -p ~/.local/share/quickshell/ukishima` with `qs -c ukishima`.

Available IPC handlers: `launcher`, `wallpaper`, `clipboard`, `mixer`, `calendar`, `media`, `power`, `link`, `battery`, `sysmon`/`system`, `recorder`/`screenrec`/`record`, `quickRecord`, `gameMode`, `peek`, `hide`, `page`, `minimizeWindow`, `restoreWindow`. The `page` handler takes the monitor first (empty = focused) and the surface name second — `qs -c ukishima ipc call fukushima page "" wifi`.

### Development

The shell is interpreted QML — edit a file, and Quickshell hot-reloads it. Full setup (QML tooling, editor config, the isolated dev instance) is in [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md); [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) covers the layout and [`docs/ROADMAP.md`](docs/ROADMAP.md) where the fork is headed. In short:

```bash
sudo apt install just              # task runner
just doctor                        # confirm the toolchain
just dev                           # run this checkout as an isolated instance
```

`just dev` runs alongside a normally-installed instance without touching its state.

### Testing

```bash
just check     # qmllint + the lib/ logic tests (this is what CI runs)
```

There is no automated UI test (it would need a live compositor). After a behaviour-preserving change, walk [`docs/SMOKE-TEST.md`](docs/SMOKE-TEST.md) — a manual click-through of every surface and pill state.

### State & Cache

- **state:** `$XDG_STATE_HOME/fukushima` (default `~/.local/state/fukushima`) — flags, events, gamemode snapshot; the wallpaper selection lives in sibling `~/.local/state/fukushima-wallpaper*` files.
- **cache:** `$XDG_CACHE_HOME/fukushima` (default `~/.cache/fukushima`) — palette JSON and record thumbnails; wallpaper previews under `fukushima-wp-thumbs/`, clipboard previews under `cliphist-thumbs/`, weather location under `pill/`.

### Uninstalling

```bash
curl -fsSL https://raw.githubusercontent.com/thatkazuk1/ukishima/master/uninstall.sh | bash
```

Removes the program files, all state (`~/.local/state/fukushima*`) and all caches (`~/.cache/fukushima*`, `~/.cache/cliphist-thumbs`, `~/.cache/pill`), and stops any running instance. You still remove the `exec-once` line and the keybinds from your Hyprland config yourself, and uninstall any dependencies you added only for this.

## How to Get Help

This is a personal project with no SLA. [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) explains the codebase; the header comment on each surface explains what it does and why. For a genuine bug in the public material, the issue tracker is checked periodically.

## Contributing

Not actively seeking contributions while the refactor is in flight — the architecture is moving under your feet ([`docs/ROADMAP.md`](docs/ROADMAP.md) tracks it). Bug reports for real breakage are welcome. Commits follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## Acknowledgements

Fukushima stands on two projects it borrows heavily from:

- **[Ricelin](https://github.com/Gakuseei/Ricelin)** by **[Gakuseei](https://github.com/Gakuseei)** — the origin of the pill concept, the morphing-surface architecture and most of the original shell code.
- **[Ukishima](https://github.com/amanhex/Ukishima)** by **[amanhex](https://github.com/amanhex)** — the fork of Ricelin that extended and rebranded it into the pill shell this repo is based on.

Lineage: Ricelin → Ukishima → Fukushima. This repo forks amanhex's Ukishima and continues that work. All credit for the base code goes to the original authors; the `MIT` licence and their copyright are retained in [`LICENSE`](LICENSE).

## Authors

**Desmond Edem** ([@thatkazuk1](https://github.com/thatkazuk1)) — this fork.

Base code by **Gakuseei** (Ricelin) and **amanhex** (Ukishima); see [Acknowledgements](#acknowledgements).

### Repo Activity

TBA.

**[Back to top](#table-of-contents)**
