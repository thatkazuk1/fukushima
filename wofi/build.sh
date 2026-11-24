#!/usr/bin/env bash
# Link the washi stylesheet into wofi and make wofi launch kitty.
set -euo pipefail
cd "$(dirname "$0")"
ln -sfn "$PWD/style.css" "$HOME/.config/wofi/style.css"
sed -i 's/^term=.*/term=kitty/' "$HOME/.config/wofi/config"
echo "wofi linked"
