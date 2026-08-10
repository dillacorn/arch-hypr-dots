#!/usr/bin/env bash
# Position and size Awtarchy Quickshell floating flyouts on a specific monitor.

set -euo pipefail
export LC_ALL=C.UTF-8

surface="${1:-}"
monitor="${2:-}"
placement="${3:-center}"
action="${4:-spawn}"
requested_w="${5:-}"
requested_h="${6:-}"
anchor="${7:--1}"
state_file="${XDG_CACHE_HOME:-$HOME/.cache}/awtarchy/quickshell-state.json"

[[ -n "$surface" && -n "$monitor" ]] || {
    printf 'quickshell_flyout_position.sh: surface and monitor are required\n' >&2
    exit 2
}

case "$placement" in
    center|top|bottom|left|right) ;;
    *)
        printf 'quickshell_flyout_position.sh: invalid placement: %s\n' "$placement" >&2
        exit 2
        ;;
esac

case "$action" in
    spawn|resize|clamp) ;;
    *)
        printf 'quickshell_flyout_position.sh: invalid action: %s\n' "$action" >&2
        exit 2
        ;;
esac

case "$surface" in
    clipboard)
        title='Awtarchy Clipboard History'
        state_key='clipboard_views'
        default_w=880
        default_h=760
        min_w=480
        min_h=360
        layout='centered'
        ;;
    notifications)
        title='Awtarchy Notification Center'
        state_key='notification_views'
        default_w=520
        default_h=760
        min_w=360
        min_h=360
        layout='notification'
        ;;
    quick-settings)
        title='Awtarchy Quick Settings'
        state_key='quick_settings_views'
        default_w=860
        default_h=850
        min_w=520
        min_h=460
        layout='centered'
        ;;
    network)
        title='Awtarchy Network'
        state_key='network_views'
        default_w=520
        default_h=600
        min_w=360
        min_h=360
        layout='corner'
        ;;
    bluetooth)
        title='Awtarchy Bluetooth'
        state_key='bluetooth_views'
        default_w=500
        default_h=600
        min_w=360
        min_h=360
        layout='corner'
        ;;
    *)
        printf 'quickshell_flyout_position.sh: invalid surface: %s\n' "$surface" >&2
        exit 2
        ;;
esac

command -v hyprctl >/dev/null 2>&1 || exit 127
command -v jq >/dev/null 2>&1 || exit 127

client=""
for _ in {1..60}; do
    client="$(
        hyprctl clients -j 2>/dev/null |
            jq -c --arg title "$title" '[.[] | select(.title == $title)] | last // empty' 2>/dev/null || true
    )"
    [[ -n "$client" ]] && break
    sleep 0.02
done

[[ -n "$client" ]] || {
    printf 'quickshell_flyout_position.sh: window not found: %s\n' "$title" >&2
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
    printf 'quickshell_flyout_position.sh: monitor not found: %s\n' "$monitor" >&2
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
        [(.x // 0), (.y // 0), (logical_width | floor), (logical_height | floor)] | @tsv
    ' <<<"$mon"
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

max_w=$((mon_w - 20))
max_h=$((mon_h - 20))
(( max_w < 1 )) && max_w=1
(( max_h < 1 )) && max_h=1
(( min_w > max_w )) && min_w="$max_w"
(( min_h > max_h )) && min_h="$max_h"

clamp_dimension() {
    local value="$1" minimum="$2" maximum="$3"
    (( value < minimum )) && value="$minimum"
    (( value > maximum )) && value="$maximum"
    printf '%s\n' "$value"
}

resize_on_apply=0
case "$action" in
    spawn)
        desired_w="$default_w"
        desired_h="$default_h"
        if [[ -s "$state_file" ]] && jq -e '.' "$state_file" >/dev/null 2>&1; then
            read -r desired_w desired_h < <(
                jq -r \
                    --arg key "$state_key" \
                    --arg monitor "$monitor" \
                    --argjson default_w "$default_w" \
                    --argjson default_h "$default_h" '
                    def number_or_zero: try tonumber catch 0;
                    ((.[$key] // {})[$monitor] // {}) as $view
                    | (($view.width // 0) | number_or_zero) as $width
                    | (($view.height // 0) | number_or_zero) as $height
                    | (($view.save_version // 0) | number_or_zero) as $save_version
                    | ($view.saved == true and $save_version >= 2) as $saved
                    | if $saved and $width >= 1 and $width <= 16384
                        and $height >= 1 and $height <= 16384
                      then [($width | round), ($height | round)]
                      else [$default_w, $default_h]
                      end
                    | @tsv
                ' "$state_file"
            )
        fi
        win_w="$(clamp_dimension "$desired_w" "$min_w" "$max_w")"
        win_h="$(clamp_dimension "$desired_h" "$min_h" "$max_h")"
        resize_on_apply=1
        ;;
    resize)
        [[ "$requested_w" =~ ^[0-9]+$ && "$requested_h" =~ ^[0-9]+$ ]] || {
            printf 'quickshell_flyout_position.sh: resize requires integer width and height\n' >&2
            exit 2
        }
        win_w="$(clamp_dimension "$requested_w" "$min_w" "$max_w")"
        win_h="$(clamp_dimension "$requested_h" "$min_h" "$max_h")"
        resize_on_apply=1
        ;;
    clamp)
        win_w="$(clamp_dimension "$win_w" "$min_w" "$max_w")"
        win_h="$(clamp_dimension "$win_h" "$min_h" "$max_h")"
        ;;
esac

center_x=$((mon_x + (mon_w - win_w) / 2))
center_y=$((mon_y + (mon_h - win_h) / 2))

case "$layout:$placement" in
    centered:top)
        x="$center_x"; y=$((mon_y + horizontal_bar)) ;;
    centered:bottom)
        x="$center_x"; y=$((mon_y + mon_h - horizontal_bar - win_h)) ;;
    centered:left)
        x=$((mon_x + vertical_bar)); y="$center_y" ;;
    centered:right)
        x=$((mon_x + mon_w - vertical_bar - win_w)); y="$center_y" ;;
    corner:top)
        x=$((mon_x + mon_w - win_w - 8)); y=$((mon_y + horizontal_bar)) ;;
    corner:bottom)
        x=$((mon_x + mon_w - win_w - 8)); y=$((mon_y + mon_h - horizontal_bar - win_h)) ;;
    corner:left)
        x=$((mon_x + vertical_bar)); y=$((mon_y + mon_h - win_h - 8)) ;;
    corner:right)
        x=$((mon_x + mon_w - vertical_bar - win_w)); y=$((mon_y + mon_h - win_h - 8)) ;;
    notification:top|notification:bottom)
        if [[ "$anchor" =~ ^-?[0-9]+([.][0-9]+)?$ ]] && awk "BEGIN {exit !($anchor >= 0)}"; then
            local_anchor="$(awk -v value="$anchor" 'BEGIN {printf "%d", value + 0.5}')"
        else
            local_anchor=$((mon_w - 40))
        fi
        x=$((mon_x + local_anchor - win_w))
        if [[ "$placement" == top ]]; then
            y=$((mon_y + horizontal_bar))
        else
            y=$((mon_y + mon_h - horizontal_bar - win_h))
        fi
        ;;
    notification:left|notification:right)
        if [[ "$anchor" =~ ^-?[0-9]+([.][0-9]+)?$ ]] && awk "BEGIN {exit !($anchor >= 0)}"; then
            local_anchor="$(awk -v value="$anchor" 'BEGIN {printf "%d", value + 0.5}')"
        else
            local_anchor=$((mon_h - 40))
        fi
        y=$((mon_y + local_anchor - win_h))
        if [[ "$placement" == left ]]; then
            x=$((mon_x + vertical_bar))
        else
            x=$((mon_x + mon_w - vertical_bar - win_w))
        fi
        ;;
    *:center)
        x="$center_x"; y="$center_y" ;;
    *)
        x="$center_x"; y="$center_y" ;;
esac

if [[ "$action" == clamp ]]; then
    x="$win_x"
    y="$win_y"
fi

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
if (( resize_on_apply )); then
    resize_lua="hl.dispatch(hl.dsp.window.resize({ x = ${win_w}, y = ${win_h}, relative = false, window = \"${selector_lua}\" }))"
fi

hyprctl eval "
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"1\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"border_size\", value = \"0\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"rounding\", value = \"0\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = \"decorate\", value = \"0\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.float({ action = \"enable\", window = \"${selector_lua}\" }))
    hl.dispatch(hl.dsp.window.move({ monitor = \"${monitor_lua}\", follow = false, window = \"${selector_lua}\" }))
    ${resize_lua}
    hl.dispatch(hl.dsp.window.move({ x = ${x}, y = ${y}, relative = false, window = \"${selector_lua}\" }))
" >/dev/null
