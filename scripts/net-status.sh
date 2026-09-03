#!/usr/bin/env bash
# One network-status poll for the wifi surface. Emits tab-separated key/value
# lines on stdout; the Network service diffs the byte counters and ping samples
# between polls (see lib/net.js). Nothing here needs privilege.
#
#   iface   wlo1
#   type    wifi | ethernet
#   ip      192.168.30.107
#   prefix  24
#   gateway 192.168.30.1
#   rx_bytes 12143148388
#   tx_bytes 5088788424
#   ssid    Cinque
#   signal  74
#   rate    195 Mbit/s
#   freq    5220
#   router_ping_ms   3.35        (absent line = timed out this poll)
#   internet_ping_ms 12.1
set -u

# Two well-connected anycast resolvers; internet latency is the lower of the
# two so one badly-routed anycast path (e.g. an ISP that hauls 1.1.1.1 to
# another continent) doesn't skew the figure.
probes="1.1.1.1 8.8.8.8"
route_probe=1.1.1.1

route=$(ip -j route get "$route_probe" 2>/dev/null)
[ -n "$route" ] || exit 0

iface=$(printf '%s' "$route" | jq -r '.[0].dev // empty' 2>/dev/null)
gateway=$(printf '%s' "$route" | jq -r '.[0].gateway // empty' 2>/dev/null)
ip4=$(printf '%s' "$route" | jq -r '.[0].prefsrc // empty' 2>/dev/null)
[ -n "$iface" ] || exit 0

prefix=$(ip -j addr show "$iface" 2>/dev/null \
    | jq -r 'first(.[0].addr_info[]? | select(.family=="inet") | .prefixlen) // empty' 2>/dev/null)

printf 'iface\t%s\n' "$iface"
printf 'ip\t%s\n' "$ip4"
printf 'prefix\t%s\n' "$prefix"
printf 'gateway\t%s\n' "$gateway"

if [ -r "/sys/class/net/$iface/statistics/rx_bytes" ]; then
    printf 'rx_bytes\t%s\n' "$(cat "/sys/class/net/$iface/statistics/rx_bytes")"
    printf 'tx_bytes\t%s\n' "$(cat "/sys/class/net/$iface/statistics/tx_bytes")"
fi

if [ -d "/sys/class/net/$iface/wireless" ]; then
    printf 'type\twifi\n'
    # SIGNAL / RATE / FREQ of the associated AP. None of these three fields can
    # contain a colon, so -F: is safe; the SSID (which can) is read separately
    # from GENERAL.CONNECTION below.
    LC_ALL=C nmcli -t -e no -f IN-USE,SIGNAL,RATE,FREQ dev wifi list ifname "$iface" --rescan no 2>/dev/null \
        | awk -F: '$1=="*"{
            sig=$2; rate=$3; freq=$4;
            gsub(/[^0-9]/,"",sig); gsub(/[^0-9]/,"",freq);
            print "signal\t" sig;
            print "rate\t"   rate;
            print "freq\t"   freq;
            exit;
          }'
    ssid=$(LC_ALL=C nmcli -t -e no -g GENERAL.CONNECTION device show "$iface" 2>/dev/null)
    [ -n "$ssid" ] && printf 'ssid\t%s\n' "$ssid"
else
    printf 'type\tethernet\n'
fi

# Router + internet latency, in parallel, one packet each, 1s ceiling. A line
# is only printed when a probe answered; a missing internet line is a timeout
# the service records as packet loss. Internet latency is the lower of the two
# resolver probes.
ping_ms() {
    LC_ALL=C ping -n -c1 -W1 "$1" 2>/dev/null \
        | awk -F'time[=<]' '/time[=<]/{split($2,a," "); print a[1]; exit}'
}

tmp=$(mktemp -d) || exit 0
[ -n "$gateway" ] && { ping_ms "$gateway" >"$tmp/r" & }
for h in $probes; do ping_ms "$h" >"$tmp/i.$h" & done
wait

[ -s "$tmp/r" ] && printf 'router_ping_ms\t%s\n' "$(cat "$tmp/r")"
best=$(cat "$tmp"/i.* 2>/dev/null | awk 'NF{print}' | sort -g | head -n1)
[ -n "$best" ] && printf 'internet_ping_ms\t%s\n' "$best"
rm -rf "$tmp"
