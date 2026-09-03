#!/usr/bin/env bash
# Streamed internet speed test for the wifi panel. Prints one tab-separated
# line per phase as it finishes:
#
#   ping<TAB><ms>
#   down<TAB><mbps>
#   up<TAB><mbps>
#   fail<TAB><phase>
#
# Each phase is time-boxed with `curl --max-time`. A time-box cutoff (curl exit
# 28) is the normal end of a phase, not a failure — the bytes moved up to that
# point are the measurement. Only a real connection error fails the phase.
set -u

base=https://speed.cloudflare.com
dur=8

emit() { printf '%s\t%s\n' "$1" "$2"; }
mbps() { awk -v b="$1" -v s="$dur" 'BEGIN { printf "%.1f", b * 8 / s / 1000000 }'; }

# ---- ping ----
# time_connect is one TCP round trip to the edge; time_total would fold in the
# TLS handshake and inflate the figure two- to threefold.
pt=$(curl -s --max-time 5 -o /dev/null -w '%{time_connect}' "$base/meta" 2>/dev/null) || { emit fail ping; exit 0; }
emit ping "$(awk -v t="$pt" 'BEGIN { printf "%d", t * 1000 }')"

# ---- download: sum 50 MB chunks until the time box is spent ----
end=$(( $(date +%s) + dur ))
bytes=0
while [ "$(date +%s)" -lt "$end" ]; do
    left=$(( end - $(date +%s) ))
    [ "$left" -lt 1 ] && break
    o=$(curl -s --max-time "$left" -o /dev/null -w '%{size_download} %{exitcode}' \
        "$base/__down?bytes=50000000" 2>/dev/null)
    sz=${o%% *}
    ec=${o##* }
    case "$ec" in
        0)  bytes=$(( bytes + ${sz:-0} )) ;;
        28) bytes=$(( bytes + ${sz:-0} )); break ;;
        *)  emit fail download; exit 0 ;;
    esac
done
[ "$bytes" -ge 200000 ] && emit down "$(mbps "$bytes")" || { emit fail download; exit 0; }

# ---- upload: stream from /dev/zero for one time box ----
o=$(head -c 500000000 /dev/zero \
    | curl -s --max-time "$dur" -o /dev/null -w '%{size_upload} %{exitcode}' \
        -T - -H 'Content-Type: application/octet-stream' "$base/__up" 2>/dev/null)
sz=${o%% *}
ec=${o##* }
case "$ec" in
    0 | 28) ;;
    *) emit fail upload; exit 0 ;;
esac
[ "${sz:-0}" -ge 200000 ] && emit up "$(mbps "$sz")" || emit fail upload
