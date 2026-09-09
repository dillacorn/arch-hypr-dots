#!/usr/bin/env bash
# Compute a high-contrast black/white lockscreen accent while the desktop is unlocked.

set -euo pipefail

CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_DIR="${CACHE_HOME}/awtarchy"
CACHE_FILE="${CACHE_DIR}/lockscreen-contrast.txt"
AWTWALL_STATE="${CONFIG_HOME}/awtwall/backend_state.tsv"
TMP_FILE=""

cleanup() {
    [[ -z "$TMP_FILE" ]] || rm -f -- "$TMP_FILE"
}
trap cleanup EXIT

write_color() {
    local color="$1"
    mkdir -p "$CACHE_DIR"
    TMP_FILE="$(mktemp "${CACHE_FILE}.tmp.XXXXXX")"
    printf '%s\n' "$color" >"$TMP_FILE"
    mv -f -- "$TMP_FILE" "$CACHE_FILE"
    TMP_FILE=""
}

wallpaper_path() {
    local line first second rest
    [[ -r "$AWTWALL_STATE" ]] || return 1

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS=$'\t' read -r first second rest <<<"$line"
        [[ "$first" == "backend" ]] && continue
        if [[ -n "${rest:-}" ]]; then
            printf '%s\n' "$rest"
            return 0
        fi
        if [[ -n "${second:-}" ]]; then
            printf '%s\n' "$second"
            return 0
        fi
    done <"$AWTWALL_STATE"
    return 1
}

main() {
    local background="${1:-black}" image="" mean=""

    case "$background" in
        black)
            write_color '#ffffff'
            return 0
            ;;
        wallpaper) ;;
        *)
            printf 'invalid lockscreen background: %s\n' "$background" >&2
            return 2
            ;;
    esac

    image="$(wallpaper_path 2>/dev/null || true)"
    if [[ -z "$image" || ! -f "$image" || ! -r "$image" ]] || ! command -v magick >/dev/null 2>&1; then
        write_color '#ffffff'
        return 0
    fi

    mean="$(magick "$image" -colorspace Gray -resize '1x1!' -format '%[fx:mean]' info: 2>/dev/null || true)"
    if [[ ! "$mean" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        write_color '#ffffff'
        return 0
    fi

    if awk -v mean="$mean" 'BEGIN { exit !(mean >= 0.58) }'; then
        write_color '#000000'
    else
        write_color '#ffffff'
    fi
}

main "$@"
