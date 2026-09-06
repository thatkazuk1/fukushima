#!/usr/bin/env bash
# Run this working copy as a throwaway "dev" instance, side by side with a
# normally-installed Fukushima.
#
# Isolation is done entirely through the XDG base dirs: every state/cache path
# in the shell and its helper scripts is derived from $XDG_STATE_HOME /
# $XDG_CACHE_HOME, so redirecting those two into ./.dev/ keeps the dev instance
# from touching your real ~/.local/state/ukishima* and ~/.cache/ukishima*.
#
# The dev instance shares the "fukushima" layer-shell namespace with a running
# live shell (compositors allow duplicates); a dedicated --dev namespace suffix
# lands with the Paths refactor.
#
# Usage:
#   scripts/dev.sh                 # run in the foreground, Ctrl-C to stop
#   scripts/dev.sh ipc call fukushima launcher ""  # talk to the running dev instance
set -eu

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dev="$repo/.dev"
mkdir -p "$dev/state" "$dev/cache"

export XDG_STATE_HOME="$dev/state"
export XDG_CACHE_HOME="$dev/cache"

# Subcommand passthrough: `scripts/dev.sh ipc ...`, `scripts/dev.sh log`, etc.
if [ "$#" -gt 0 ]; then
  exec qs -p "$repo" "$@"
fi

# -n / --no-duplicate: refuse to start a second copy of *this* config (matched by
# path), so a stale dev instance is caught instead of silently stacking.
exec qs -p "$repo" -n
