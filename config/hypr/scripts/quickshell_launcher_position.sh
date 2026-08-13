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
#   clamp
#       keep the current placement but move every edge back inside the monitor

set -euo pipefail
export LC_ALL=C.UTF-8

monitor="${1:-}"
placement="${2:-center}"
title="Awtarchy Application Search"
state_file="${XDG_CACHE_HOME:-$HOME/.cache}/awtarchy/quickshell-state.json"
prepared_file="${XDG_RUNTIME_DIR:-/tmp}/awtarchy-quickshell/flyout-targets/launcher"
reference_screen_w=1920
reference_screen_h=1080
reference_w=420
reference_h=582

[[ -n "$monitor" ]] || {
    printf 'quickshell_launcher_position.sh: monitor is required\n' >&2
    exit 2
}

case "$placement" in
    center|top|bottom|left|right|top-center|bottom-center|left-center|right-center|clamp) ;;
    *)
        printf 'quickshell_launcher_position.sh: invalid placement: %s\n' "$placement" >&2
        exit 2
        ;;
esac

command -v hyprctl >/dev/null 2>&1 || exit 127
command -v jq >/dev/null 2>&1 || exit 127

# A prepared launcher spawn has already selected its authoritative monitor and
# edge before mapping. QML may briefly retain the previous screen while Qt is
# remapping the singleton window, so do not let this legacy post-map correction
# move a correctly prepared launcher back to that stale monitor. Live clamp
# operations intentionally keep their caller-provided target.
resolve_prepared_target() {
    [[ "$placement" != "clamp" ]] || return 0
    [[ -r "$prepared_file" ]] || return 0

    local prepared_monitor prepared_placement prepared_json
    IFS=$'\t' read -r prepared_monitor prepared_placement < "$prepared_file" || return 0

    [[ "$prepared_monitor" =~ ^[A-Za-z0-9._:-]+$ ]] || return 0
    case "$prepared_placement" in
        center|top|bottom|left|right|top-center|bottom-center|left-center|right-center) ;;
        *) return 0 ;;
    esac

    prepared_json="$(
        hyprctl monitors -j 2>/dev/null \
            | jq -c --arg monitor "$prepared_monitor" '.[] | select(.name == $monitor)' \
            | head -n1
    )"
    [[ -n "$prepared_json" ]] || return 0

    monitor="$prepared_monitor"
    placement="$prepared_placement"
}

resolve_prepared_target

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
win_x="$(jq -r '.at[0] // 0' <<<"$client")"
win_y="$(jq -r '.at[1] // 0' <<<"$client")"
win_w="$(jq -r '.size[0] // 0' <<<"$client")"
win_h="$(jq -r '.size[1] // 0' <<<"$client")"

[[ -n "$address" && "$win_x" =~ ^-?[0-9]+$ && "$win_y" =~ ^-?[0-9]+$ \
    && "$win_w" =~ ^[0-9]+$ && "$win_h" =~ ^[0-9]+$ ]] || exit 1
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

# Scale the unsaved launcher default from the 1920x1080 @ 1.0 reference
# canvas. mon_w/mon_h are logical dimensions, so monitor scale is not applied
# twice. Explicit per-monitor saves remain exact logical-pixel dimensions.
read -r adaptive_default_w adaptive_default_h < <(
    awk \
        -v monitor_w="$mon_w" \
        -v monitor_h="$mon_h" \
        -v reference_screen_w="$reference_screen_w" \
        -v reference_screen_h="$reference_screen_h" \
        -v reference_w="$reference_w" \
        -v reference_h="$reference_h" '
        BEGIN {
            width_scale = monitor_w / reference_screen_w
            height_scale = monitor_h / reference_screen_h
            factor = width_scale < height_scale ? width_scale : height_scale
            printf "%d\t%d\n", int(reference_w * factor + 0.5), int(reference_h * factor + 0.5)
        }
    '
)

horizontal_bar=28
vertical_bar=36
if [[ -s "$state_file" ]] && jq -e '.' "$state_file" >/dev/null 2>&1; then
    custom_bar="$(jq -r --arg monitor "$monitor" '.monitors[$monitor].bar_size // 0' "$state_file" 2>/dev/null || printf '0')"
    if [[ "$custom_bar" =~ ^[0-9]+$ ]] && (( custom_bar >= 20 && custom_bar <= 80 )); then
        horizontal_bar="$custom_bar"
        vertical_bar="$custom_bar"
    fi
fi

# Quickshell intentionally does not apply FloatingWindow geometry changes while
# the backing window is visible. On a normal launcher spawn, enforce the saved
# size through Hyprland after mapping. The clamp path is used during a live drag
# and must preserve the current compositor-controlled size.
resize_on_spawn=0
if [[ "$placement" != "clamp" ]]; then
    desired_w="$adaptive_default_w"
    desired_h="$adaptive_default_h"

    if [[ -s "$state_file" ]] && jq -e '.' "$state_file" >/dev/null 2>&1; then
        read -r desired_w desired_h < <(
            jq -r \
                --arg monitor "$monitor" \
                --argjson default_w "$adaptive_default_w" \
                --argjson default_h "$adaptive_default_h" '
                def number_or_zero: try tonumber catch 0;
                (.launcher_sizes[$monitor] // {}) as $view
                | (($view.width // 0) | number_or_zero) as $width
                | (($view.height // 0) | number_or_zero) as $height
                | (($view.save_version // 0) | number_or_zero) as $save_version
                | (($view.locked == true)
                    or ($view.saved == true and $save_version >= 2)) as $saved
                | if $saved and $width >= 1 and $width <= 16384
                    and $height >= 1 and $height <= 16384
                  then [($width | round), ($height | round)]
                  else [$default_w, $default_h]
                  end
                | @tsv
            ' "$state_file"
        )
    fi

    min_w=420
    min_h=360
    max_w=$((mon_w - 32))
    max_h=$((mon_h - 32))
    (( max_w < 1 )) && max_w=1
    (( max_h < 1 )) && max_h=1
    (( min_w > max_w )) && min_w="$max_w"
    (( min_h > max_h )) && min_h="$max_h"
    (( desired_w < min_w )) && desired_w="$min_w"
    (( desired_w > max_w )) && desired_w="$max_w"
    (( desired_h < min_h )) && desired_h="$min_h"
    (( desired_h > max_h )) && desired_h="$max_h"

    win_w="$desired_w"
    win_h="$desired_h"
    resize_on_spawn=1
fi

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
    clamp)
        x="$win_x"
        y="$win_y"
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
resize_lua=""
focus_lua=""
if (( resize_on_spawn )); then
    resize_lua="hl.dispatch(hl.dsp.window.resize({ x = ${win_w}, y = ${win_h}, relative = false, window = \"${selector_lua}\" }))"
    # A keybind can open the launcher while the pointer is nowhere near it.
    # Focus this exact mapped toplevel so the prepared QML search field gets
    # keyboard input immediately instead of waiting for pointer focus.
    focus_lua="hl.dispatch(hl.dsp.focus({ window = \"${selector_lua}\" }))"
fi

# The v2 runtime rule maps the launcher fully transparent. Perform every move
# and resize first, then reveal only this exact window address.
hyprctl eval "
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"1\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"border_size\", value = \"0\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"rounding\", value = \"0\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"decorate\", value = \"0\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.float({ action = \"enable\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.move({ monitor = \"${monitor_lua}\", follow = false, window = \"${selector_lua}\" }))
    ${resize_lua}
    hl.dispatch(hl.dsp.window.move({ x = ${x}, y = ${y}, relative = false, window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"opacity\", value = \"1\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"opacity_override\", value = \"1\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"opacity_inactive\", value = \"1\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"opacity_inactive_override\", value = \"1\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"opacity_fullscreen\", value = \"1\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"opacity_fullscreen_override\", value = \"1\", window = \"${selector_lua}\" }))
    ${focus_lua}
" >/dev/null
