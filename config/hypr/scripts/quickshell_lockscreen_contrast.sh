#!/usr/bin/env bash
# Compute per-element black/white lockscreen contrast while the desktop is unlocked.

set -euo pipefail

CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE_DIR="${CACHE_HOME}/awtarchy"
STATE_FILE="${CACHE_DIR}/quickshell-state.json"
CACHE_FILE="${CACHE_DIR}/lockscreen-contrast.json"
ELEMENTS="logo time date username weather password"
DEFAULT_LAYOUT='{"logo":{"x":0.5,"y":0.34},"time":{"x":0.5,"y":0.51},"date":{"x":0.5,"y":0.555},"username":{"x":0.5,"y":0.595},"weather":{"x":0.5,"y":0.635},"password":{"x":0.5,"y":0.7}}'
TMP_FILE=""
OUTPUT_STDOUT=0
OVERRIDE_BACKGROUND=""
OVERRIDE_BACKGROUND_COLOR=""
OVERRIDE_WALLPAPER=""
OVERRIDE_LAYOUT=""

cleanup() {
    [[ -z "$TMP_FILE" ]] || rm -f -- "$TMP_FILE"
}
trap cleanup EXIT

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'quickshell_lockscreen_contrast.sh: missing: %s\n' "$1" >&2
        exit 127
    }
}

need jq

while (($#)); do
    case "$1" in
        --stdout)
            OUTPUT_STDOUT=1
            shift
            ;;
        --background)
            [[ $# -ge 2 ]] || exit 2
            OVERRIDE_BACKGROUND="$2"
            shift 2
            ;;
        --background-color)
            [[ $# -ge 2 ]] || exit 2
            OVERRIDE_BACKGROUND_COLOR="$2"
            shift 2
            ;;
        --wallpaper)
            [[ $# -ge 2 ]] || exit 2
            OVERRIDE_WALLPAPER="$2"
            shift 2
            ;;
        --layout-json)
            [[ $# -ge 2 ]] || exit 2
            OVERRIDE_LAYOUT="$2"
            shift 2
            ;;
        *)
            printf 'unknown contrast option: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

valid_hex() {
    [[ "$1" =~ ^#[0-9A-Fa-f]{6}$ ]]
}

contrast_for_hex() {
    local hex="$1" r g b luminance
    valid_hex "$hex" || {
        printf '#ffffff\n'
        return 0
    }
    r=$((16#${hex:1:2}))
    g=$((16#${hex:3:2}))
    b=$((16#${hex:5:2}))
    luminance="$(awk -v r="$r" -v g="$g" -v b="$b" \
        'BEGIN { printf "%.6f", (0.2126*r + 0.7152*g + 0.0722*b) / 255 }')"
    if awk -v value="$luminance" 'BEGIN { exit !(value >= 0.58) }'; then
        printf '#000000\n'
    else
        printf '#ffffff\n'
    fi
}

layout_value() {
    local layout="$1" element="$2" axis="$3" fallback="$4"
    jq -r --arg element "$element" --arg axis "$axis" --arg fallback "$fallback" '
        (.[$element][$axis] // ($fallback | tonumber)) as $value
        | if ($value | type) == "number" and $value >= 0 and $value <= 1
          then $value else ($fallback | tonumber) end
    ' <<<"$layout" 2>/dev/null || printf '%s\n' "$fallback"
}

sample_wallpaper_contrast() {
    local image="$1" layout="$2" element="$3"
    local dimensions width height x y ratio_w ratio_h crop_w crop_h center_x center_y origin_x origin_y mean

    if ! command -v magick >/dev/null 2>&1 || [[ ! -f "$image" || ! -r "$image" ]]; then
        printf '#ffffff\n'
        return 0
    fi

    dimensions="$(magick identify -format '%w %h' "$image" 2>/dev/null || true)"
    read -r width height <<<"$dimensions"
    if [[ ! "$width" =~ ^[1-9][0-9]*$ || ! "$height" =~ ^[1-9][0-9]*$ ]]; then
        printf '#ffffff\n'
        return 0
    fi

    case "$element" in
        logo) ratio_w=0.34; ratio_h=0.20 ;;
        password) ratio_w=0.26; ratio_h=0.10 ;;
        time) ratio_w=0.20; ratio_h=0.11 ;;
        *) ratio_w=0.18; ratio_h=0.09 ;;
    esac

    case "$element" in
        logo) x="$(layout_value "$layout" "$element" x 0.5)"; y="$(layout_value "$layout" "$element" y 0.34)" ;;
        time) x="$(layout_value "$layout" "$element" x 0.5)"; y="$(layout_value "$layout" "$element" y 0.51)" ;;
        date) x="$(layout_value "$layout" "$element" x 0.5)"; y="$(layout_value "$layout" "$element" y 0.555)" ;;
        username) x="$(layout_value "$layout" "$element" x 0.5)"; y="$(layout_value "$layout" "$element" y 0.595)" ;;
        weather) x="$(layout_value "$layout" "$element" x 0.5)"; y="$(layout_value "$layout" "$element" y 0.635)" ;;
        password) x="$(layout_value "$layout" "$element" x 0.5)"; y="$(layout_value "$layout" "$element" y 0.7)" ;;
    esac

    crop_w="$(awk -v total="$width" -v ratio="$ratio_w" 'BEGIN { value=int(total*ratio); print value < 1 ? 1 : value }')"
    crop_h="$(awk -v total="$height" -v ratio="$ratio_h" 'BEGIN { value=int(total*ratio); print value < 1 ? 1 : value }')"
    center_x="$(awk -v total="$width" -v ratio="$x" 'BEGIN { print int(total*ratio) }')"
    center_y="$(awk -v total="$height" -v ratio="$y" 'BEGIN { print int(total*ratio) }')"
    origin_x=$((center_x - crop_w / 2))
    origin_y=$((center_y - crop_h / 2))
    ((origin_x < 0)) && origin_x=0
    ((origin_y < 0)) && origin_y=0
    ((origin_x + crop_w > width)) && origin_x=$((width - crop_w))
    ((origin_y + crop_h > height)) && origin_y=$((height - crop_h))
    ((origin_x < 0)) && origin_x=0
    ((origin_y < 0)) && origin_y=0

    mean="$(magick "$image" \
        -crop "${crop_w}x${crop_h}+${origin_x}+${origin_y}" +repage \
        -colorspace Gray -resize '1x1!' -format '%[fx:mean]' info: 2>/dev/null || true)"
    if [[ ! "$mean" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf '#ffffff\n'
        return 0
    fi

    if awk -v value="$mean" 'BEGIN { exit !(value >= 0.58) }'; then
        printf '#000000\n'
    else
        printf '#ffffff\n'
    fi
}

background="black"
background_color="#000000"
wallpaper=""
layout="$DEFAULT_LAYOUT"

if [[ -s "$STATE_FILE" ]] && jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
    background="$(jq -r '.lockscreen_background // "black"' "$STATE_FILE")"
    background_color="$(jq -r '.lockscreen_background_color // "#000000"' "$STATE_FILE")"
    wallpaper="$(jq -r '.lockscreen_wallpaper_path // ""' "$STATE_FILE")"
    layout="$(jq -c '.lockscreen_layout // empty' "$STATE_FILE" 2>/dev/null || true)"
    [[ -n "$layout" && "$layout" != "null" ]] || layout="$DEFAULT_LAYOUT"
fi

[[ -z "$OVERRIDE_BACKGROUND" ]] || background="$OVERRIDE_BACKGROUND"
[[ -z "$OVERRIDE_BACKGROUND_COLOR" ]] || background_color="$OVERRIDE_BACKGROUND_COLOR"
[[ -z "$OVERRIDE_WALLPAPER" ]] || wallpaper="$OVERRIDE_WALLPAPER"
[[ -z "$OVERRIDE_LAYOUT" ]] || layout="$OVERRIDE_LAYOUT"

case "$background" in
    black|wallpaper|color) ;;
    *) background="black" ;;
esac
valid_hex "$background_color" || background_color="#000000"
if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$layout"; then
    layout="$DEFAULT_LAYOUT"
fi

colors='{}'
for element in $ELEMENTS; do
    case "$background" in
        black) color="#ffffff" ;;
        color) color="$(contrast_for_hex "$background_color")" ;;
        wallpaper) color="$(sample_wallpaper_contrast "$wallpaper" "$layout" "$element")" ;;
    esac
    colors="$(jq -c --arg element "$element" --arg color "$color" \
        '. + {($element): $color}' <<<"$colors")"
done

payload="$(jq -cn \
    --arg provider 'awtarchy-local-contrast' \
    --arg background "$background" \
    --arg background_color "$background_color" \
    --arg wallpaper "$wallpaper" \
    --argjson colors "$colors" \
    '{version:2, provider:$provider, background:$background,
      background_color:$background_color, wallpaper:$wallpaper, colors:$colors}')"

if ((OUTPUT_STDOUT == 1)); then
    printf '%s\n' "$payload"
    exit 0
fi

mkdir -p "$CACHE_DIR"
TMP_FILE="$(mktemp "${CACHE_FILE}.tmp.XXXXXX")"
printf '%s\n' "$payload" >"$TMP_FILE"
mv -f -- "$TMP_FILE" "$CACHE_FILE"
TMP_FILE=""
