#!/usr/bin/env bash
# Write the qt5ct and qt6ct config files for the Fukushima palette.
# The qt5ct and qt6ct packages must be installed for Qt to read them.
set -euo pipefail
cd "$(dirname "$0")"
for ct in qt5ct qt6ct; do
  dir="$HOME/.config/$ct"
  mkdir -p "$dir/colors"
  ln -sfn "$PWD/fukushima-colors.conf" "$dir/colors/fukushima.conf"
  sed "s|@COLORS@|$dir/colors/fukushima.conf|" qt.conf.in > "$dir/$ct.conf"
done
echo "wrote qt5ct and qt6ct config"
