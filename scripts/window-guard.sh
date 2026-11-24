#!/usr/bin/env bash
# Move floating windows with a position outside the 16-bit range back onto
# their monitor.
#
# Hyprshell stores each window position as a 16-bit number (-32768 to 32767).
# A floating window can end up far off screen, for example after a monitor
# change. One such window makes `hyprctl clients` unreadable to Hyprshell, and
# ALT+TAB then does nothing. The services/WindowGuard singleton runs this
# script when windows or monitors change.
#
# Prints one tab-separated line for each window that it handles:
#   moved   <class>  <from x,y>  <to x,y>
#   skipped <class>  <from x,y>  tiled
# A tiled window follows the layout, so this script cannot move it.
set -u

# 16-bit limit is 32767. Keep a margin so a window near the limit is also fixed.
limit=32000

clients=$(hyprctl clients -j 2>/dev/null) || exit 0
monitors=$(hyprctl monitors -j 2>/dev/null) || exit 0
[ -n "$clients" ] && [ -n "$monitors" ] || exit 0

# Fields: address, floating, class, from x, from y, target x, target y.
# The target is the centre of the window's monitor. A window without a monitor
# (id -1) goes to the first monitor.
jq -rn --argjson c "$clients" --argjson m "$monitors" --argjson lim "$limit" '
    $c[]
    | select(.mapped
        and (.at[0] < -$lim or .at[0] > $lim or .at[1] < -$lim or .at[1] > $lim))
    | . as $w
    | ($m | map(select(.id == $w.monitor)) | first // ($m | first)) as $mon
    | select($mon != null)
    | [ $w.address, $w.floating, $w.class, $w.at[0], $w.at[1],
        ($mon.x + (($mon.width / $mon.scale) - $w.size[0]) / 2 | floor),
        ($mon.y + (($mon.height / $mon.scale) - $w.size[1]) / 2 | floor) ]
    | @tsv
' | while IFS=$'\t' read -r addr floating class fx fy tx ty; do
    if [ "$floating" = true ]; then
        hyprctl dispatch movewindowpixel "exact $tx $ty,address:$addr" >/dev/null 2>&1
        printf 'moved\t%s\t%s,%s\t%s,%s\n' "$class" "$fx" "$fy" "$tx" "$ty"
    else
        printf 'skipped\t%s\t%s,%s\ttiled\n' "$class" "$fx" "$fy"
    fi
done
exit 0
