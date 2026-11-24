#!/usr/bin/env bash
# One poll of the radio state for the pill icons. Quickshell's Bluetooth and
# Networking backends keep a copy of the state that goes stale when bluetoothd
# or NetworkManager restarts, so the services/Radios singleton reads the real
# state here instead. Emits tab-separated key/value lines on stdout.
#
#   bt        none | on | off      no adapter, adapter powered, adapter unpowered
#   wifi      none | on | off      no wifi device, radio enabled, radio disabled
#   wifi_signal 74                 signal of the connected network, 0-100 (absent when none)
#   eth       on | off             the route to the internet uses a wired device
set -u

bt=none
if out=$(timeout 3 bluetoothctl show 2>/dev/null) && [ -n "$out" ]; then
    case "$out" in
        *"Powered: yes"*) bt=on ;;
        *"Powered: no"*) bt=off ;;
    esac
fi
printf 'bt\t%s\n' "$bt"

wifi=none
if timeout 3 nmcli -t -f TYPE device 2>/dev/null | grep -qx wifi; then
    case "$(timeout 3 nmcli radio wifi 2>/dev/null)" in
        enabled) wifi=on ;;
        *) wifi=off ;;
    esac
fi
printf 'wifi\t%s\n' "$wifi"

if [ "$wifi" = on ]; then
    sig=$(timeout 3 nmcli -t -f IN-USE,SIGNAL device wifi list --rescan no 2>/dev/null \
        | awk -F: '$1 == "*" { print $2; exit }')
    [ -n "$sig" ] && printf 'wifi_signal\t%s\n' "$sig"
fi

# Active link. The kernel picks the route to the internet by metric, so a
# cable that is plugged in but loses to wifi does not count. NetworkManager
# names the type of that device; a VPN or bridge device is not "ethernet".
eth=off
dev=$(ip -j route get 1.1.1.1 2>/dev/null | jq -r '.[0].dev // empty' 2>/dev/null)
if [ -n "$dev" ] && [ "$(timeout 3 nmcli -g GENERAL.TYPE device show "$dev" 2>/dev/null)" = ethernet ]; then
    eth=on
fi
printf 'eth\t%s\n' "$eth"
exit 0
