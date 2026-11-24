#!/usr/bin/env bash
# Link the washi palette into kitty and include it after the matugen colours.
set -euo pipefail
cd "$(dirname "$0")"
ln -sfn "$PWD/fukushima.conf" "$HOME/.config/kitty/fukushima.conf"
conf="$HOME/.config/kitty/kitty.conf"
line="include ~/.config/kitty/fukushima.conf"
grep -qxF "$line" "$conf" || printf '\n%s\n' "$line" >> "$conf"
echo "kitty linked"
