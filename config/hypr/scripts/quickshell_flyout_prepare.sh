#!/usr/bin/env bash
# Prepare an Awtarchy Quickshell floating flyout before QML maps it.
#
# The regular post-map positioning helpers remain as fallbacks. This helper
# installs a later static Hyprland rule first so the initial mapped frame already
# has the target monitor, size, position, and visible opacity.

set -euo pipefail

surface="${1:-}"
monitor="${2:-}"
placement="${3:-}"
width="${4:-}"
height="${5:-}"
bar_size="${6:-0}"
anchor="${7:--1}"
screen_width="${8:-}"
screen_height="${9:-}"

usage() {
    printf 'usage: %s <surface> <monitor> <placement> <width> <height> <bar-size> <anchor> <screen-width> <screen-height>\n' "$0" >&2
    exit 2
}

[[ -n "$surface" && -n "$monitor" && -n "$placement" ]] || usage
[[ "$monitor" =~ ^[A-Za-z0-9._:-]+$ ]] || {
    printf 'quickshell_flyout_prepare.sh: unsupported monitor name: %s\n' "$monitor" >&2
    exit 2
}
for value in "$width" "$height" "$bar_size" "$screen_width" "$screen_height"; do
    [[ "$value" =~ ^[0-9]+$ ]] || usage
done
[[ "$anchor" =~ ^-?[0-9]+$ ]] || usage
(( width > 0 && height > 0 && screen_width > 0 && screen_height > 0 )) || usage

case "$placement" in
    center|top|bottom|left|right|top-center|bottom-center|left-center|right-center) ;;
    *) usage ;;
esac

case "$surface" in
    launcher)
        title='Awtarchy Application Search'
        layout='launcher'
        ;;
    clipboard)
        title='Awtarchy Clipboard History'
        layout='centered'
        ;;
    notifications)
        title='Awtarchy Notification Center'
        layout='notification'
        ;;
    quick-settings)
        title='Awtarchy Quick Settings'
        layout='centered'
        ;;
    network)
        title='Awtarchy Network'
        layout='corner'
        ;;
    bluetooth)
        title='Awtarchy Bluetooth'
        layout='corner'
        ;;
    *) usage ;;
esac

center_x=$(( (screen_width - width) / 2 ))
center_y=$(( (screen_height - height) / 2 ))
(( center_x < 0 )) && center_x=0
(( center_y < 0 )) && center_y=0

x="$center_x"
y="$center_y"

if [[ "$placement" != "center" ]]; then
    case "$layout:$placement" in
        launcher:top)
            x=0
            y="$bar_size"
            ;;
        launcher:bottom)
            x=0
            y=$(( screen_height - height - bar_size ))
            ;;
        launcher:left)
            x="$bar_size"
            y=0
            ;;
        launcher:right)
            x=$(( screen_width - width - bar_size ))
            y=0
            ;;
        launcher:top-center)
            x="$center_x"
            y="$bar_size"
            ;;
        launcher:bottom-center)
            x="$center_x"
            y=$(( screen_height - height - bar_size ))
            ;;
        launcher:left-center)
            x="$bar_size"
            y="$center_y"
            ;;
        launcher:right-center)
            x=$(( screen_width - width - bar_size ))
            y="$center_y"
            ;;
        centered:top)
            x="$center_x"
            y="$bar_size"
            ;;
        centered:bottom)
            x="$center_x"
            y=$(( screen_height - height - bar_size ))
            ;;
        centered:left)
            x="$bar_size"
            y="$center_y"
            ;;
        centered:right)
            x=$(( screen_width - width - bar_size ))
            y="$center_y"
            ;;
        corner:top)
            x=$(( screen_width - width - 8 ))
            y="$bar_size"
            ;;
        corner:bottom)
            x=$(( screen_width - width - 8 ))
            y=$(( screen_height - height - bar_size ))
            ;;
        corner:left)
            x="$bar_size"
            y=$(( screen_height - height - 8 ))
            ;;
        corner:right)
            x=$(( screen_width - width - bar_size ))
            y=$(( screen_height - height - 8 ))
            ;;
        notification:top|notification:bottom)
            (( anchor >= 0 )) || anchor=$(( screen_width - 40 ))
            x=$(( anchor - width ))
            min_x=6
            max_x=$(( screen_width - width - 6 ))
            (( max_x < min_x )) && max_x="$min_x"
            (( x < min_x )) && x="$min_x"
            (( x > max_x )) && x="$max_x"
            if [[ "$placement" == "top" ]]; then
                y="$bar_size"
            else
                y=$(( screen_height - height - bar_size ))
            fi
            ;;
        notification:left|notification:right)
            (( anchor >= 0 )) || anchor=$(( screen_height - 40 ))
            y=$(( anchor - height ))
            min_y=6
            max_y=$(( screen_height - height - 6 ))
            (( max_y < min_y )) && max_y="$min_y"
            (( y < min_y )) && y="$min_y"
            (( y > max_y )) && y="$max_y"
            if [[ "$placement" == "left" ]]; then
                x="$bar_size"
            else
                x=$(( screen_width - width - bar_size ))
            fi
            ;;
    esac
fi

(( x < 0 )) && x=0
(( y < 0 )) && y=0

rule_name="awtarchy-flyout-prepared-${surface//[^A-Za-z0-9_-]/-}-$$"

# All interpolated values above are either fixed strings or strictly validated
# ASCII/numeric values. The newly created rule is intentionally left enabled;
# the next open replaces it before mapping. This also keeps privacy-remap
# hide/show cycles at the same geometry without introducing another first frame.
lua="awtarchy_prepared_flyout_rules_v1 = awtarchy_prepared_flyout_rules_v1 or {}; local old = awtarchy_prepared_flyout_rules_v1['$surface']; if old ~= nil then pcall(function() old:set_enabled(false) end) end; awtarchy_prepared_flyout_rules_v1['$surface'] = hl.window_rule({ name = '$rule_name', match = { title = '$title' }, float = true, monitor = '$monitor', size = { '$width', '$height' }, move = { '$x', '$y' }, no_anim = true, opacity = '1 override 1 override 1 override' }); hl.exec_scheduled_prop_refresh_immediately()"

hyprctl eval "$lua" >/dev/null
