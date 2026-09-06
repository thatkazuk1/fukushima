#!/usr/bin/env bash
set -eu

SHARE="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"

echo "Removing Fukushima..."

# Stop a running instance (qs / quickshell started with the fukushima config).
pkill -f "[q]s .*[Ff]ukushima" 2>/dev/null || true
pkill -f "[q]uickshell .*[Ff]ukushima" 2>/dev/null || true

# Program files (wherever you cloned it).
rm -rf "$SHARE/quickshell/fukushima"
rm -rf "$CONF/quickshell/fukushima"

# State: flags, events, gamemode snapshot, wallpaper selection.
rm -rf "$STATE/fukushima"
rm -f  "$STATE/fukushima-wallpaper-dir"
rm -f  "$STATE/fukushima-wallpaper"
rm -f  "$STATE/fukushima-wallpaper-map"
rm -f  "$STATE/fukushima-wallpaper-bag" "$STATE/fukushima-wallpaper-bag.lock"
rm -f  "$STATE/fukushima-wallpaper-fit"
rm -f  "$STATE/fukushima-wallpaper-still.png"

# Cache: rec thumbs, wallpaper + clipboard previews, weather location.
rm -rf "$CACHE/fukushima"
rm -rf "$CACHE/fukushima-wp-thumbs"
rm -rf "$CACHE/cliphist-thumbs"
rm -rf "$CACHE/pill"

# Note: this script never edits your Hyprland config. The auto-launch line and
# the SUPER keybinds were added by you, so remove them yourself:
echo "Fukushima removed."
echo "Remove the exec-once auto-launch line and the SUPER keybinds from your Hyprland config."