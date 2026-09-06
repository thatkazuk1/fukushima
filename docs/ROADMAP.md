# Ukishima roadmap

Where the fork is and where it's going. This is a working document — update it as
phases close.

Ukishima is a hard-fork of [amanhex/Ukishima](https://github.com/amanhex/Ukishima)
(itself forked from Gakuseei/Ricelin), re-engineered as a properly structured
Quickshell project. Companion docs:
[`ARCHITECTURE.md`](ARCHITECTURE.md) (layout + import rules),
[`DEVELOPMENT.md`](DEVELOPMENT.md) (dev loop, tooling),
[`SMOKE-TEST.md`](SMOKE-TEST.md) (manual regression pass).

## Phases

| Phase | Theme | State |
| --- | --- | --- |
| 0 | Dev environment | ✅ done |
| 1 | Baseline correctness | ✅ done |
| 2 | Behaviour-preserving refactor | 🟡 in progress (interleaved) |
| 3 | Features | 🟡 ongoing |
| 4 | Distribution | ⬜ not started |

Sequencing decision (2026-09-03): the structural refactor comes *before* net-new
features — but Phase 2's remaining items don't compound fast enough to justify a
feature freeze. Do the leftover splits **when a feature forces the code open**;
otherwise interleave.

---

## Phase 0 — Dev environment ✅

- `Justfile` task runner (`doctor`, `dev`, `ipc`, `lint`, `test`, `check`, `fmt`);
  auto-locates the Qt tools.
- `scripts/dev.sh` — run the repo as an isolated instance (state/cache redirected
  into `./.dev/`).
- `.qmllint.ini` tuned for a no-C++-types project; `.editorconfig`; CI workflow
  running `just check`.
- `.vscode/` checked in; `qmlls` enabled. A Qt 6.10 qmldom `SIGABRT` (a
  `function` declaration inside a binding block) was tracked down to two files
  and fixed. Quickshell's own singletons/components resolve via its tooling VFS
  (one-time `touch .qmlls.ini` + reload); the compiled-in framework types don't,
  and `.qmllint.ini` mutes that family. `just lint` / the `qmllint` build task
  are the terminal/CI diagnostics. See [`DEVELOPMENT.md`](DEVELOPMENT.md#editor-setup).
- `lib/*.js` + `*.test.mjs` wired to Node; `docs/DEVELOPMENT.md`,
  `docs/ARCHITECTURE.md`.

## Phase 1 — Baseline correctness ✅

- `qmllint` advisories cleared; `just lint` is clean.
- **Dispatcher fix:** the upstream code assumed a Lua-configured Hyprland and
  called `hl.dsp.*` — every one failed with "Invalid dispatcher" on a hyprlang
  setup. Rewritten to standard `hyprctl` dispatchers (workspace-click,
  minimize/restore, logout, notification-focus).
- Fork identity settled: keep the name `ukishima`; retarget `LICENSE` and the
  install script; credit the chain Ricelin → Ukishima → this fork in the README.
- This repo became the live shell (`~/.config/quickshell` → repo symlink).

## Phase 2 — Behaviour-preserving refactor 🟡

**Done:**

- **Standard layout.** `Singletons/` → `config/` (settings + design tokens) +
  `services/` (system-state providers); pill / surfaces / OSD → `modules/`;
  Hyprland fragments → `hypr/`; preview gallery → `assets/`. Import graph
  rewritten and trimmed. Documented in [`ARCHITECTURE.md`](ARCHITECTURE.md).
- **`shell.qml` declutter** — battery-alert escalation + update toast extracted
  to `services/BatteryAlerts.qml` / `services/UpdateToast.qml` (lazy singletons).
  644 → ~535 lines.
- **`Pill.qml` split, round 1** — `GameBar`, `DragInstall`, `QuickRecordChooser`
  extracted to `modules/pill/`. 3020 → ~2350 lines. Pattern: self-contained
  view/controller, host feeds explicit props, one signal back.
- Orphaned `lib/monitors.js` deleted.

**Remaining (interleave / when a feature forces it):**

- **Finish the `Pill.qml` split** — the coupled parts that round 1 left:
  - the `rest` collapsed faces (~355 lines, threaded through strip geometry)
  - the `hover` module row (~600 lines, most coupled — soul-bead targeting,
    per-icon tooltips, `requestSurface`)
  - a `SurfaceStack` for the ~20 surface `Loader`s
- **`config/Flags.qml` regroup** — one flat ~60-property `JsonAdapter` → grouped
  (`record.*`, `night.*`, `wallpaper.*`, `ui.*`). Needs a `flags.json` migration
  shim so existing state isn't lost.
- **`shell.qml` input layer** — split the per-monitor window trees and the
  keyboard-routing `FocusScope` (~340 lines) into their own components.
- **`lib/` test coverage** — `lib/calc.js` and `lib/fuzzy.js` (both used by the
  launcher) have no tests.

## Phase 3 — Features 🟡

**Done:**

- **Workspace-number flash** — the switch indicator now morphs line → numbered
  row (active workspace in a vermillion disc) → fade, on keyboard switch,
  alt-tab, and dot-click. Per-monitor. (`modules/osd/`, `components/Workspaces.qml`)
- **Network panel rebuild** — the Wi-Fi surface mirrors omarchy Quattro's panel:
  - new `services/NetInfo.qml` + `lib/net.js` (throughput, ping window,
    formatting; 38 assertions) + `scripts/net-status.sh` / `net-band.sh` /
    `net-qr.sh` / `net-speedtest.sh`
  - live vitals grid (ping / loss, receiving / sending, downloaded / uploaded,
    IP / gateway); polls only while open
  - band selector — 2.4 / 5 / 6 GHz pills + AUTOMATIC; `nmcli` reconnect with
    auto-revert if the AP doesn't serve the pinned band
  - QR share card; inline speed test (time-boxed `curl`, robust on slow/asymmetric
    links); Known / Other network sections
  - ping takes the min of two resolvers (the user's ISP anycasts 1.1.1.1 to a
    distant colo)
- **Battery health / degradation block** — `services/Battery.qml` reads
  `/sys/class/power_supply/BAT*/` for design capacity and cycle count (UPower via
  Quickshell exposes neither). Health = full ÷ design; the battery surface shows
  a capacity bar, the Wh figures, and cycle count, turning vermillion under 80%.
- **Tooltips** on the network panel controls, plus a fix to the shared `Tooltip`
  component (it was rendering translucent — the layer effect was the culprit).
- Speed test removed from the system-resources surface (it moved to the panel).
- Wallpaper selector now includes `.jpeg` files.

**Backlog (user to prioritise):**

- Reactivity pass over the pill's hover row / system face — device state should
  be shown, not guessed (e.g. Bluetooth-on reflected in the icon without a click).
- Further feature ideas — TBD.

## Phase 4 — Distribution ⬜

- **Recreate the GitHub repo.** It was deleted; `remote-install.sh` still clones
  `github.com/thatkazuk1/ukishima`, `origin` points at nothing, nothing is pushed.
- Rework `remote-install.sh` / `uninstall.sh` — they still print Lua keybind
  examples that don't apply to a hyprlang setup.
- Versioned releases + tags; a changelog.
- Fresh screenshots / preview — `assets/preview/` is upstream Ukishima's.
- Optional: AUR / Nix packaging.

---

## Open decisions

- **Lua-only "Spaces" editor.** `services/Spaces.qml` writes
  `hypr/spaces.lua` / `binds.lua` for a special-workspace editor — inert on a
  hyprlang Hyprland. Either build a hyprlang port (a real custom
  special-workspaces feature) or remove the editor. This is a *feature* call, not
  refactor debt.
- **`hypr/decoration.lua`** (pill blur layer rule) isn't sourced — moot while
  `pillBlur` is off, revisit if blur comes back.

## Known quirks (not regressions)

- `Tooltip.qml` sets three horizontal anchors, two resolving to `undefined` —
  intentional, `qmllint`-suppressed with a comment.
- The network panel's speed-test "Ping" reads higher than the vitals grid's — it
  measures RTT to a specific CDN endpoint, by design.
- The README preview media is upstream's, not this fork's (see Phase 4).
