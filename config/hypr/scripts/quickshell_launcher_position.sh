#!/usr/bin/env bash
# Position the Awtarchy Quickshell application launcher on a specific monitor.
#
# placement:
#   center
#       true center of the requested monitor
#   top|bottom|left|right
#       place beside the Apps button on that bar edge
#   top-center|bottom-center|left-center|right-center
#       attach to that bar edge while centering along the bar

set -euo pipefail
export LC_ALL=C

monitor="${1:-}"
placement="${2:-center}"
title="Awtarchy Application Search"

[[ -n "$monitor" ]] || {
    printf 'quickshell_launcher_position.sh: monitor is required\n' >&2
    exit 2
}

case "$placement" in
    center|top|bottom|left|right|top-center|bottom-center|left-center|right-center) ;;
    *)
        printf 'quickshell_launcher_position.sh: invalid placement: %s\n' "$placement" >&2
        exit 2
        ;;
esac

command -v hyprctl >/dev/null 2>&1 || exit 127
command -v jq >/dev/null 2>&1 || exit 127

client=""
for _ in {1..60}; do
    client="$(
        hyprctl clients -j 2>/dev/null |
            jq -c --arg title "$title" '
                [ .[] | select(.title == $title) ] | last // empty
            ' 2>/dev/null || true
    )"
    [[ -n "$client" ]] && break
    sleep 0.02
done

[[ -n "$client" ]] || {
    printf 'quickshell_launcher_position.sh: launcher window was not found\n' >&2
    exit 1
}

address="$(jq -r '.address // empty' <<<"$client")"
win_w="$(jq -r '.size[0] // 0' <<<"$client")"
win_h="$(jq -r '.size[1] // 0' <<<"$client")"

[[ -n "$address" && "$win_w" =~ ^[0-9]+$ && "$win_h" =~ ^[0-9]+$ ]] || exit 1
(( win_w > 0 && win_h > 0 )) || exit 1

mon="$(
    hyprctl monitors -j 2>/dev/null |
        jq -c --arg monitor "$monitor" '.[] | select(.name == $monitor)' |
        head -n1
)"
[[ -n "$mon" ]] || {
    printf 'quickshell_launcher_position.sh: monitor not found: %s\n' "$monitor" >&2
    exit 1
}

read -r mon_x mon_y mon_w mon_h < <(
    jq -r '
        def rotated: (((.transform // 0) % 2) == 1);
        def logical_width:
            if rotated then (.height / (.scale // 1))
            else (.width / (.scale // 1)) end;
        def logical_height:
            if rotated then (.width / (.scale // 1))
            else (.height / (.scale // 1)) end;
        [
            (.x // 0),
            (.y // 0),
            (logical_width | floor),
            (logical_height | floor)
        ] | @tsv
    ' <<<"$mon"
)

horizontal_bar=28
vertical_bar=36

case "$placement" in
    top)
        x="$mon_x"
        y=$((mon_y + horizontal_bar))
        ;;
    bottom)
        x="$mon_x"
        y=$((mon_y + mon_h - horizontal_bar - win_h))
        ;;
    left)
        x=$((mon_x + vertical_bar))
        y="$mon_y"
        ;;
    right)
        x=$((mon_x + mon_w - vertical_bar - win_w))
        y="$mon_y"
        ;;
    top-center)
        x=$((mon_x + (mon_w - win_w) / 2))
        y=$((mon_y + horizontal_bar))
        ;;
    bottom-center)
        x=$((mon_x + (mon_w - win_w) / 2))
        y=$((mon_y + mon_h - horizontal_bar - win_h))
        ;;
    left-center)
        x=$((mon_x + vertical_bar))
        y=$((mon_y + (mon_h - win_h) / 2))
        ;;
    right-center)
        x=$((mon_x + mon_w - vertical_bar - win_w))
        y=$((mon_y + (mon_h - win_h) / 2))
        ;;
    center)
        x=$((mon_x + (mon_w - win_w) / 2))
        y=$((mon_y + (mon_h - win_h) / 2))
        ;;
esac

min_x="$mon_x"
min_y="$mon_y"
max_x=$((mon_x + mon_w - win_w))
max_y=$((mon_y + mon_h - win_h))
(( max_x < min_x )) && max_x="$min_x"
(( max_y < min_y )) && max_y="$min_y"
(( x < min_x )) && x="$min_x"
(( x > max_x )) && x="$max_x"
(( y < min_y )) && y="$min_y"
(( y > max_y )) && y="$max_y"

selector="address:${address}"
monitor_lua="${monitor//\\/\\\\}"
monitor_lua="${monitor_lua//\"/\\\"}"
selector_lua="${selector//\\/\\\\}"
selector_lua="${selector_lua//\"/\\\"}"

# Disable animation on this launcher window before moving it. The Quickshell
# surface stays transparent until this process exits, so the user sees only the
# final position instead of a center-to-edge compositor animation.
hyprctl eval "
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"1\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.float({ action = \"enable\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.move({ monitor = \"${monitor_lua}\", follow = false, window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.move({ x = ${x}, y = ${y}, relative = false, window = \"${selector_lua}\" }))
" >/dev/null
