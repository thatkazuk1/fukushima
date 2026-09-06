# Ukishima dev tasks. Run `just` for the list.
#
# The Qt QML tools (qmllint / qmlformat / qmlls) ship with Qt but are often not
# on PATH. `qtbin` finds them: PATH first, then the usual distro locations.

set shell := ["bash", "-uc"]

qtbin := `for d in "" /usr/lib/qt6/bin /usr/lib/x86_64-linux-gnu/qt6/bin /usr/lib64/qt6/bin; do
    if { [ -z "$d" ] && command -v qmllint >/dev/null; } || [ -x "$d/qmllint" ]; then echo "$d"; break; fi
  done`

qmllint   := if qtbin == "" { "qmllint" }   else { qtbin / "qmllint" }
qmlformat := if qtbin == "" { "qmlformat" } else { qtbin / "qmlformat" }

# All tracked QML (the dev-instance scratch dir is untracked, so it's excluded).
qml := "$(git ls-files '*.qml')"

_default:
    @just --list --unsorted

# Report whether the toolchain this repo needs is present.
doctor:
    @echo "qtbin:      {{ if qtbin == "" { "(using PATH)" } else { qtbin } }}"
    @command -v quickshell >/dev/null && echo "quickshell: $(quickshell --version 2>&1 | head -1)" || echo "quickshell: MISSING"
    @command -v hyprctl    >/dev/null && echo "hyprland:   $(hyprctl version 2>&1 | head -1)"     || echo "hyprland:   MISSING"
    @command -v node       >/dev/null && echo "node:       $(node --version)"                     || echo "node:       MISSING (lib/ tests)"
    @{{qmllint}}   --version >/dev/null 2>&1 && echo "qmllint:    $({{qmllint}} --version)"        || echo "qmllint:    MISSING"
    @{{qmlformat}} --version >/dev/null 2>&1 && echo "qmlformat:  ok"                              || echo "qmlformat:  MISSING"
    @echo "editor:     qmlls is disabled on purpose (.vscode/settings.json) — qmllint via 'just lint' / the qmllint task is the linter"

# Run this working copy as an isolated dev instance (Ctrl-C to stop).
dev *args:
    scripts/dev.sh {{args}}

# Talk to the running dev instance over IPC. `mon` defaults to the focused
# monitor: `just ipc launcher`, `just ipc page "" wifi`, `just ipc peek DP-1`.
ipc handler mon='""' *args:
    scripts/dev.sh ipc call ukishima {{handler}} {{mon}} {{args}}

# Static analysis on every QML file (config in .qmllint.ini).
lint:
    {{qmllint}} {{qml}}

# Run every *.test.mjs (pure-JS logic extracted from QML lives under lib/).
test:
    for f in $(git ls-files '*.test.mjs'); do echo "→ $f"; node "$f" || exit 1; done

# The CI gate: static analysis + logic tests.
check: lint test

# --- Formatting -------------------------------------------------------------
# qmlformat has no line-width setting and collapses the codebase's intentional
# manual wrapping, so it is NOT part of `check` and NOT enforced. These recipes
# are here for spot use on a single new file you want mechanically tidied.

# Show what qmlformat would change (no writes). Pass a path to scope it.
fmt-diff path=qml:
    for f in {{path}}; do diff -u "$f" <({{qmlformat}} "$f") || true; done

# Reformat the given path in place (default: everything — think first).
fmt path=qml:
    {{qmlformat}} --inplace {{path}}

# --- Dev instance lifecycle ------------------------------------------------

# Stop any running dev instance.
dev-kill:
    qs -p "$(pwd)" kill || true

# Wipe the dev instance's isolated state and cache.
dev-clean:
    rm -rf .dev
