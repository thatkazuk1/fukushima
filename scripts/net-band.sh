#!/usr/bin/env bash
# Show or pin the Wi-Fi band for the active connection.
#
#   net-band.sh              -> band<TAB>5 / available<TAB>2.4 5 / selected<TAB>auto
#   net-band.sh auto|2.4|5|6 -> modifies the profile and reconnects; on failure
#                               reverts to the previous band and re-associates,
#                               so a band the AP does not serve never strands
#                               the machine offline.
#
# `nmcli connection modify/up` may raise a polkit prompt depending on the
# session's NetworkManager policy — that is expected.
set -euo pipefail

nm() { LC_ALL=C nmcli -e no -g "$@" 2>/dev/null; }

wifi_device() {
    nm DEVICE,TYPE,STATE device status | awk -F: '$2=="wifi" && $3=="connected"{print $1; exit}'
}

# NetworkManager band tokens: "" auto, bg = 2.4, a = 5, 6GHz = 6 (NM 1.44+).
nm_band_for() { case "$1" in 2.4) echo bg;; 5) echo a;; 6) echo 6GHz;; *) return 1;; esac; }
band_from_nm() { case "$1" in bg) echo 2.4;; a) echo 5;; 6GHz) echo 6;; *) echo auto;; esac; }

band_for_freq() {
    local m=${1%%[!0-9]*}
    [ -n "$m" ] || return 1
    if   [ "$m" -ge 2400 ] && [ "$m" -lt 2500 ]; then echo 2.4
    elif [ "$m" -ge 4900 ] && [ "$m" -lt 5925 ]; then echo 5
    elif [ "$m" -ge 5925 ] && [ "$m" -lt 7125 ]; then echo 6
    else return 1; fi
}

current_freq() {
    LC_ALL=C nmcli -t -e no -f IN-USE,FREQ dev wifi list ifname "$1" --rescan no 2>/dev/null \
        | awk -F: '$1=="*"{print $2; exit}'
}

# Bands the current SSID answers on, low to high, always including the one in
# use. Reads NetworkManager's scan cache (the surface keeps it warm); forcing a
# scan here would stall every poll.
available_bands() {
    local dev=$1 ssid=$2 cur=$3
    {
        [ -n "$cur" ] && echo "$cur"
        LC_ALL=C nmcli -t -e no -f SSID,FREQ dev wifi list ifname "$dev" --rescan no 2>/dev/null \
            | awk -F: -v want="$ssid" '{
                name=$1; for (i=2; i<NF; i++) name=name ":" $i;
                if (name==want) print $NF
              }' \
            | while read -r f; do band_for_freq "$f" || true; done
    } | sort -u -g | tr '\n' ' ' | sed 's/ $//'
}

profile_for() { nm GENERAL.CONNECTION device show "$1"; }

status() {
    local dev ssid freq band prof
    dev=$(wifi_device); [ -n "$dev" ] || return 0
    ssid=$(nm GENERAL.CONNECTION device show "$dev"); [ -n "$ssid" ] || return 0
    freq=$(current_freq "$dev")
    band=$(band_for_freq "$freq" || true)
    prof=$(profile_for "$dev")
    printf 'band\t%s\n' "$band"
    printf 'available\t%s\n' "$(available_bands "$dev" "$ssid" "$band")"
    [ -n "$prof" ] && printf 'selected\t%s\n' "$(band_from_nm "$(nm 802-11-wireless.band connection show "$prof")")"
}

set_band() {
    local target=$1 dev prof prev desired ssid freq
    dev=$(wifi_device);   [ -n "$dev" ]  || { echo "no connected Wi-Fi device" >&2; exit 1; }
    prof=$(profile_for "$dev"); [ -n "$prof" ] || { echo "no active Wi-Fi profile" >&2; exit 1; }

    if [ "$target" = auto ]; then
        desired=""
    else
        ssid=$(nm GENERAL.CONNECTION device show "$dev")
        freq=$(current_freq "$dev")
        case " $(available_bands "$dev" "$ssid" "$(band_for_freq "$freq" || true)") " in
            *" $target "*) ;;
            *) echo "${target}GHz not available on this network" >&2; exit 1;;
        esac
        desired=$(nm_band_for "$target")
    fi

    prev=$(nm 802-11-wireless.band connection show "$prof")
    [ "$prev" = "$desired" ] && exit 0

    nmcli connection modify "$prof" 802-11-wireless.band "$desired" >/dev/null
    if ! nmcli connection up "$prof" >/dev/null 2>&1; then
        nmcli connection modify "$prof" 802-11-wireless.band "$prev" >/dev/null
        nmcli connection up "$prof" >/dev/null 2>&1 || true
        echo "could not connect on ${target}; reverted" >&2
        exit 1
    fi
}

case "${1:-}" in
    "")            status ;;
    auto|2.4|5|6)  set_band "$1" ;;
    *)             echo "usage: net-band.sh [auto|2.4|5|6]" >&2; exit 2 ;;
esac
