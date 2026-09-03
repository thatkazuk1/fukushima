#!/usr/bin/env bash
# Emit the active Wi-Fi network as a QR matrix for the surface to draw with
# native rectangles: one line per row, each character 0 (light) or 1 (dark),
# with the spec's 4-module quiet zone already included.
#
# First line is metadata:  meta<TAB>SSID<TAB>security   (security: WPA|WEP|nopass)
#
# The password is read with `nmcli --show-secrets` (a user may read their own
# saved secret unprivileged) and never appears on a command line.
set -euo pipefail

iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
[ -n "${iface:-}" ] && [ -d "/sys/class/net/$iface/wireless" ] || {
    echo "no active Wi-Fi connection" >&2; exit 1; }

uuid=$(nmcli --get-values GENERAL.CON-UUID device show "$iface" 2>/dev/null | head -n1)
[ -n "$uuid" ] && [ "$uuid" != "--" ] || { echo "no active Wi-Fi connection" >&2; exit 1; }

mapfile -t f < <(nmcli --show-secrets --escape no --get-values \
    802-11-wireless.ssid,802-11-wireless-security.key-mgmt,802-11-wireless-security.psk,802-11-wireless.hidden \
    connection show uuid "$uuid" 2>/dev/null)

ssid=${f[0]:-}
keymgmt=${f[1]:-}
psk=${f[2]:-}
hidden=${f[3]:-no}
[ -n "$ssid" ] || { echo "could not read the Wi-Fi name" >&2; exit 1; }
case "$keymgmt" in *eap*|*ieee8021x*) echo "enterprise Wi-Fi cannot be shared as a QR" >&2; exit 1;; esac

esc() { local v=$1; v=${v//\\/\\\\}; v=${v//;/\\;}; v=${v//,/\\,}; v=${v//:/\\:}; printf '%s' "$v"; }

if [ -n "$keymgmt" ] && [ "$keymgmt" != none ]; then
    [ -n "$psk" ] || { echo "could not read the Wi-Fi password" >&2; exit 1; }
    sec=WPA
else
    sec=nopass
fi

payload="WIFI:T:$sec;S:$(esc "$ssid");"
[ "$sec" != nopass ] && payload+="P:$(esc "$psk");"
[ "$hidden" = yes ] && payload+="H:true;"
payload+=";"

printf 'meta\t%s\t%s\n' "$ssid" "$sec"

# qrencode ASCII uses two chars per module; collapse each pair to one bit.
printf '%s' "$payload" | qrencode --type ASCII --margin 4 --output - | while IFS= read -r line; do
    row=""
    for ((c = 0; c < ${#line}; c += 2)); do
        case "${line:c:2}" in *"#"*) row+=1;; *) row+=0;; esac
    done
    printf '%s\n' "$row"
done
