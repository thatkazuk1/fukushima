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
  - [Polkit Agent](#polkit-agent)
  - [Themes for Other Apps](#themes-for-other-apps)
  - [Usage Notch](#usage-notch)
  - [Google Calendar](#google-calendar)
  - [Development](#development)
  - [Testing](#testing)
  - [State & Cache](#state--cache)
  - [Uninstalling](#uninstalling)
- [How to Get Help](#how-to-get-help)
- [Contributing](#contributing)
- [Acknowledgements](#acknowledgements)
- [Authors](#authors)

## About the Project

Fukushima (福島) is a widget layer for Hyprland. A single morphing pill sits at the top of every monitor. Hover the pill and it expands into a control centre with the clock, media and system readouts. Each module grows its own surface out of the pill. The password prompt is the one separate window.

The installer does not change your Hyprland config. You add the auto-launch line and the keybinds yourself. The optional [themes for other apps](#themes-for-other-apps) do change files in `~/.config`.

This is a fork of amanhex's **Ukishima** (浮島, *"floating island"*) — the name keeps the *-shima*. See [Acknowledgements](#acknowledgements) for the full lineage.

## Features

### The pill

- **Dynamic island:** one morphing pill for each monitor, with a bead cursor and smooth morph animations.
- **Four collapsed faces:** minimal, classic, system and strip.
- **Surfaces:** launcher, calendar, weather, media, sound, screen, wallpaper picker, screen recorder, clipboard history, wifi, bluetooth, battery, power menu, system monitor, usage limits, notification inbox, minimized-window stash, OSD and toasts.
- **Settings hub:** Appearance holds the display, theme, font, interface and update pages.

### Modules

- **LLM usage notch:** ring gauges for the Codex, Claude and Antigravity limits, with the time until each reset. It warns at 80, 95 and 100 percent. It needs [a separate collector](#usage-notch).
- **Polkit agent:** the password prompt uses the pill palette and font. See [Polkit Agent](#polkit-agent).
- **Network panel:** live vitals (ping, packet loss, transfer rates, session totals, IP and gateway), a Wi-Fi band selector, QR sharing, a speed test, and the Known and Other network lists.
- **Wallpaper system:** the `awww` backend with a shuffled bag, per-monitor assignment, transitions, video wallpapers (`mpvpaper`) and a fit control. It includes [Wallhaven](https://wallhaven.cc) search with sorting and pagination. Online thumbnails stay in memory.
- **Palettes:** fixed light and dark palettes, a palette from the wallpaper, or a manual hue. A wallpaper change or a manual hue also updates the `ghostty` and `fastfetch` colours.
- **Screen recorder:** `gpu-screen-recorder` with a window or region picker, countdown, quality presets, audio and a strip of recent clips.
- **Weather:** Open-Meteo current, hourly and five-day forecast. You can set the location, or the shell finds it from your IP address.
- **Google Calendar:** read-only events from one or more accounts, beside your local events. See [Google Calendar](#google-calendar).
- **Extras:** night light, music visualiser, game mode, quick-record keybind, keep-awake and an in-app updater.

### Matching themes

Optional dark themes for GTK3, GTK4, Qt5, Qt6, kitty and wofi. See [Themes for Other Apps](#themes-for-other-apps).

## Preview

See the [preview gallery](assets/preview/README.md) for screenshots. These predate this
fork and will be refreshed once it diverges visually.

## Project Status

![status](https://img.shields.io/badge/status-active-brightgreen)
![quickshell](https://img.shields.io/badge/quickshell-0.3.0%2B-blue)
![hyprland](https://img.shields.io/badge/hyprland-0.4x%20%E2%80%93%200.5x-blue)
![license](https://img.shields.io/badge/license-MIT-lightgrey)
[![CI](https://github.com/thatkazuk1/fukushima/actions/workflows/ci.yml/badge.svg)](https://github.com/thatkazuk1/fukushima/actions/workflows/ci.yml)

Actively developed. CI runs the pure-JS logic tests and `qmllint` on each push to `master` and on each pull request. The lint job is advisory.

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
| `notify-send` (libnotify) | battery and usage warnings |
| `curl` | wallpaper search, speed test |
| `python3` | palette generation, Google Calendar |
| `xdg-open` | open recordings and folders |
| `qrencode` | Wi-Fi share QR in the network panel |
| `ip` / `ping` (iproute2, iputils) | network panel vitals |
| `brightnessctl` | backlight control |
| `cava` | music visualiser |
| `cliphist` + `wl-clipboard` | clipboard history |
| `slurp` | window/region picker for screen recording |
| `hyprsunset` | night light |

#### Optional, for full functionality

| Package | Adds |
| --- | --- |
| `gpu-screen-recorder` | the screen-recording backend (recording is disabled without it) |
| `mpvpaper` | animated / video wallpapers |
| `matugen` | base16 colours for the `ghostty` theme |
| `ddcutil` | monitor brightness via DDC (external display faders) |
| `kdialog` / `zenity` | native folder picker for the record output directory |
| `ghostty` | live terminal palette reload over D-Bus |
| `nvibrant` | screen vibrance control |
| `qt5ct`, `qt6ct` | the Qt theme |
| `kitty`, `wofi` | the terminal and launcher themes |
| `fastfetch` | recoloured system readout (needs `~/.config/fastfetch/config.jsonc.in`) |
| `hypridle` | idle / DPMS lock integration alongside the built-in keep-awake |

### Technology Stack

- **[Quickshell](https://quickshell.outfoxxed.me) 0.3.0+** — the shell runtime, on Qt 6. It needs the Hyprland, Wayland, Io and Polkit service modules. Development uses 0.3.2.
- **[Hyprland](https://hypr.land)** — the Wayland compositor (developed on 0.56.1, works across recent 0.4x/0.5x). Talked to over `hyprctl` IPC.
- **QML** — the entire shell; no compiled component and no build step.
- **Bash** — the helper scripts under `scripts/`, started by Quickshell's `Process`.
- **Python 3** — `scripts/wallcolors.py` (palettes) and `scripts/gcal.py` (Google Calendar).
- **Node** — runs the pure-JS logic tests under `lib/` (not needed at runtime).

### Third-party Services

- **[Open-Meteo](https://open-meteo.com)** — weather forecast (no API key; IP geolocation fallback via their companion service).
- **[Wallhaven](https://wallhaven.cc)** — the online wallpaper browse/search. Thumbnails are streamed from Wallhaven's CDN straight to QML and never touch disk.
- **GitHub** — the in-app updater pulls the latest commit of this repo.
- **[Google Calendar API](https://developers.google.com/calendar)** — optional and read-only. You supply your own OAuth client. `scripts/gcal.py` stores the events on your machine.
- **[LobeHub icons](https://github.com/lobehub/lobe-icons)** — the provider marks (MIT). See [`assets/marks/SOURCE.md`](assets/marks/SOURCE.md).

## Installation & Development

### Setting Up

```bash
curl -fsSL https://raw.githubusercontent.com/thatkazuk1/fukushima/master/remote-install.sh | bash
```

This clones the project to `~/.local/share/quickshell/fukushima`, checks dependencies, and prints the auto-launch line and keybinds to add to your Hyprland config. If already installed, it pulls the latest changes instead.

To auto-launch, add to your Hyprland config:

```conf
# hyprlang (.conf)
exec-once = quickshell --config ~/.local/share/quickshell/fukushima
```

```lua
-- Lua
hl.exec_cmd("quickshell --config ~/.local/share/quickshell/fukushima")
```

Or launch it manually:

```bash
quickshell --config "$HOME/.local/share/quickshell/fukushima"
```

**Already installed?** Pull updates from the **Update** sub-surface inside the pill's settings (Appearance → Update), rerun the install command, or `git pull` in the install directory.

### Keybinds

Every surface and action is exposed over Quickshell IPC (target `fukushima`). The `""` argument is the monitor — empty means "focused monitor". Bind whichever you want in your Hyprland config:

```conf
# hyprlang (.conf)
bind = SUPER SHIFT, W, exec, qs -p ~/.local/share/quickshell/fukushima ipc call fukushima wallpaper ""
bind = SUPER SHIFT, V, exec, qs -p ~/.local/share/quickshell/fukushima ipc call fukushima clipboard ""
bind = SUPER, slash,   exec, qs -p ~/.local/share/quickshell/fukushima ipc call fukushima launcher ""
```

```lua
-- Lua
hl.bind(var_mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("qs -p ~/.local/share/quickshell/fukushima ipc call fukushima wallpaper \"\""))
hl.bind(var_mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("qs -p ~/.local/share/quickshell/fukushima ipc call fukushima clipboard \"\""))
hl.bind(var_mainMod .. " + slash",     hl.dsp.exec_cmd("qs -p ~/.local/share/quickshell/fukushima ipc call fukushima launcher \"\""))
```

If you cloned to `~/.config/quickshell/fukushima` instead, replace `qs -p ~/.local/share/quickshell/fukushima` with `qs -c fukushima`.

Available IPC handlers: `launcher`, `wallpaper`, `clipboard`, `mixer` (sound), `display` (screen), `calendar`, `media`, `power`, `link`, `battery`, `usage`, `sysmon`/`system`, `recorder`/`screenrec`/`record`, `quickRecord`, `gameMode`, `peek`, `hide`, `page`, `minimizeWindow`, `restoreWindow`. The `page` handler takes the monitor first (empty = focused) and the surface name second — `qs -c fukushima ipc call fukushima page "" wifi`.

### Polkit Agent

The shell registers as the polkit agent for your session. Only one agent can register. Remove the start line of any other agent from your Hyprland config, for example:

```conf
exec-once = systemctl --user start hyprpolkitagent
```

Then stop the agent that runs now:

```bash
systemctl --user stop hyprpolkitagent
```

### Themes for Other Apps

These themes use the fixed dark palette. They do not follow the wallpaper.

> **Warning:** each build script writes into `~/.config`. Back up your own files first.

| Command | Changes |
| --- | --- |
| `gtk/build.sh` | replaces `gtk.css` in `~/.config/gtk-3.0` and `gtk-4.0` with links. The theme applies to all GTK apps. Use it with `adw-gtk3-dark`. |
| `qt/build.sh` | writes `qt5ct.conf` and `qt6ct.conf`, and links the palette. |
| `kitty/build.sh` | links the palette and adds an `include` line to `kitty.conf`. This palette overrides earlier colour files. |
| `wofi/build.sh` | replaces `style.css` with a link, and sets `term=kitty` in the wofi config. |

For Qt, install `qt5ct` and `qt6ct`. Add this line to your Hyprland config, then log in again:

```conf
env = QT_QPA_PLATFORMTHEME,qt6ct:qt5ct
```

The Qt theme changes Qt Widgets apps. Qt Quick apps keep their own colours.

### Usage Notch

The shell only reads `$XDG_STATE_HOME/llm-usage/usage.json` (default `~/.local/state/llm-usage/usage.json`). A separate collector writes the file. This repo does not include a collector, and the shell never reads provider credentials. The notch is hidden until the file has data.

```json
{
  "version": 1,
  "updated_at": 1795570000,
  "providers": {
    "codex": {
      "status": "ok",
      "plan": "plus",
      "updated_at": 1795570000,
      "windows": {
        "session": { "used_percent": 12, "resets_at": 1795588000 },
        "weekly": { "used_percent": 3, "resets_at": 1796039000 }
      }
    },
    "antigravity": { "status": "unavailable", "reason": "not installed", "windows": {} }
  }
}
```

- The provider keys are `codex`, `claude` and `antigravity`.
- `status` is `ok`, `stale`, `unavailable` or `error`. Use `reason` to explain the last two.
- Times are Unix epoch seconds. `used_percent` is 0 to 100.
- A window can set its own `label` and `short` names.
- Write the file atomically. If the file is older than 10 minutes, the shell shows the data as stale.

### Google Calendar

Do the client setup once in the [Google Cloud console](https://console.cloud.google.com/):

1. Create a project and enable the **Google Calendar API**.
2. Configure the consent screen as **External**. Keep it in **Testing** mode.
3. Add each Google address that you want to connect as a test user.
4. Create an **OAuth client ID** of the type **Desktop app**.

Then link your accounts:

1. Click the clock on the pill.
2. Click the stacked-layers icon to open the Calendars page.
3. Paste the client ID and client secret, then click **Connect with Google**.
4. Approve the access in the browser.

Google shows an "unverified app" screen for a client in Testing mode.

### Development

The shell is interpreted QML. Edit a file, and Quickshell reloads it.

```bash
sudo apt install just
```

```bash
just doctor
```

```bash
just dev
```

`just doctor` checks the toolchain. `just dev` runs this checkout as an isolated instance, beside an installed instance.

### Testing

```bash
just check
```

`just check` runs `qmllint` and the logic tests in `lib/`. There is no automated UI test, because it needs a live compositor.

### State & Cache

- **state:** `$XDG_STATE_HOME/fukushima` (default `~/.local/state/fukushima`) — flags, events, gamemode snapshot, and Google Calendar OAuth tokens under `gcal/` (0600). The wallpaper selection is in the sibling `~/.local/state/fukushima-wallpaper*` files.
- **cache:** `$XDG_CACHE_HOME/fukushima` (default `~/.cache/fukushima`) — palette JSON and record thumbnails; wallpaper previews under `fukushima-wp-thumbs/`, clipboard previews under `cliphist-thumbs/`, weather location under `pill/`.

### Uninstalling

```bash
curl -fsSL https://raw.githubusercontent.com/thatkazuk1/fukushima/master/uninstall.sh | bash
```

Removes the program files, all state (`~/.local/state/fukushima*`) and all caches (`~/.cache/fukushima*`, `~/.cache/cliphist-thumbs`, `~/.cache/pill`), and stops any running instance. It does not undo these items, so remove them yourself:

- the `exec-once` line, the keybinds and the Qt `env` line in your Hyprland config
- the theme links and config edits from the build scripts
- the packages that you added only for this shell

If you removed another polkit agent, add its start line again.

## How to Get Help

This is a personal project with no service level. The header comment of each QML file explains what it does and why. For a real bug, open an issue.

## Contributing

The project does not look for contributions at this time. Bug reports for real faults are welcome. Commits follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## Acknowledgements

Fukushima stands on two projects it borrows heavily from:

- **[Ricelin](https://github.com/Gakuseei/Ricelin)** by **[Gakuseei](https://github.com/Gakuseei)** — the origin of the pill concept, the morphing-surface architecture and most of the original shell code.
- **[Ukishima](https://github.com/amanhex/Ukishima)** by **[amanhex](https://github.com/amanhex)** — the fork of Ricelin that extended and rebranded it into the pill shell this repo is based on.

Lineage: Ricelin → Ukishima → Fukushima. This repo forks amanhex's Ukishima and continues that work. All credit for the base code goes to the original authors; the `MIT` licence and their copyright are retained in [`LICENSE`](LICENSE).

## Authors

**Desmond Edem** ([@thatkazuk1](https://github.com/thatkazuk1)) — this fork.

Base code by **Gakuseei** (Ricelin) and **amanhex** (Ukishima); see [Acknowledgements](#acknowledgements).

**[Back to top](#table-of-contents)**
