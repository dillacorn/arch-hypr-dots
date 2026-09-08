#!/usr/bin/env bash
# Apply Awtarchy's persisted Bibata XCursor selection.

set -Eeuo pipefail
IFS=$'\n\t'

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
STATE_SCRIPT="${AWTARCHY_APPLICATION_STATE_SCRIPT:-${CONFIG_HOME}/hypr/scripts/quickshell_application_state.sh}"
ICON_ROOT="${AWTARCHY_CURSOR_ICON_ROOT:-/usr/share/icons}"
HYPR_CONFIG="${AWTARCHY_HYPR_CONFIG:-${CONFIG_HOME}/hypr/hyprland.lua}"
GTK3_SETTINGS="${AWTARCHY_GTK3_SETTINGS:-${CONFIG_HOME}/gtk-3.0/settings.ini}"
NWG_SETTINGS="${AWTARCHY_NWG_SETTINGS:-${DATA_HOME}/nwg-look/gsettings}"
XRESOURCES="${AWTARCHY_XRESOURCES_FILE:-${HOME}/.Xresources}"
CURSOR_SIZE=24

variant_theme() {
    case "$1" in
        ice) printf '%s\n' 'Bibata-Modern-Ice' ;;
        classic) printf '%s\n' 'Bibata-Modern-Classic' ;;
        *) return 2 ;;
    esac
}

saved_variant() {
    local value="ice"
    if [[ -s "$STATE_FILE" ]] && command -v jq >/dev/null 2>&1; then
        value="$(jq -r '.cursor_variant // "ice"' "$STATE_FILE" 2>/dev/null || printf '%s' ice)"
    fi
    case "$value" in
        ice|classic) printf '%s\n' "$value" ;;
        *) printf '%s\n' ice ;;
    esac
}

sync_theme_to_user_icons() {
    local theme="$1" source="${ICON_ROOT}/${theme}" destination="${DATA_HOME}/icons/${theme}"
    [[ -d "$source" ]] || return 1
    mkdir -p -- "$destination"
    cp -a -- "$source/." "$destination/"
}

require_bibata_themes() {
    local theme
    for theme in Bibata-Modern-Ice Bibata-Modern-Classic; do
        if [[ ! -d "${ICON_ROOT}/${theme}" && ! -d "${DATA_HOME}/icons/${theme}" ]]; then
            printf 'quickshell_cursor_theme.sh: Bibata theme is unavailable: %s\n' "$theme" >&2
            return 1
        fi
    done
}

sync_bibata_themes() {
    local theme
    for theme in Bibata-Modern-Ice Bibata-Modern-Classic; do
        if [[ -d "${ICON_ROOT}/${theme}" ]]; then
            sync_theme_to_user_icons "$theme"
        fi
    done
}

ensure_hyprcursor_theme() {
    local theme="$1"
    local theme_dir="${DATA_HOME}/icons/${theme}"
    local work_root extract_parent create_parent extracted="" compiled="" candidate

    if [[ -f "${theme_dir}/manifest.hl" && -d "${theme_dir}/hyprcursors" ]]; then
        return 0
    fi

    command -v hyprcursor-util >/dev/null 2>&1 || {
        printf 'quickshell_cursor_theme.sh: hyprcursor-util is unavailable; current-session compositor cursor cannot be switched.\n' >&2
        return 1
    }
    command -v xcur2png >/dev/null 2>&1 || {
        printf 'quickshell_cursor_theme.sh: xcur2png is unavailable; current-session compositor cursor cannot be switched.\n' >&2
        return 1
    }
    [[ -d "$theme_dir" ]] || return 1

    mkdir -p -- "${CACHE_HOME}/awtarchy"
    work_root="$(mktemp -d "${CACHE_HOME}/awtarchy/hyprcursor.XXXXXX")" || return 1
    extract_parent="${work_root}/extract"
    create_parent="${work_root}/create"
    mkdir -p -- "$extract_parent" "$create_parent"

    if ! hyprcursor-util --extract "$theme_dir" --output "$extract_parent" >/dev/null 2>&1; then
        rm -rf -- "$work_root"
        printf 'quickshell_cursor_theme.sh: failed to extract %s for hyprcursor conversion.\n' "$theme" >&2
        return 1
    fi

    for candidate in "$extract_parent"/*; do
        if [[ -d "$candidate" && -f "$candidate/manifest.hl" ]]; then
            extracted="$candidate"
            break
        fi
    done
    if [[ -z "$extracted" ]]; then
        rm -rf -- "$work_root"
        printf 'quickshell_cursor_theme.sh: hyprcursor extraction output is missing for %s.\n' "$theme" >&2
        return 1
    fi

    if ! hyprcursor-util --create "$extracted" --output "$create_parent" >/dev/null 2>&1; then
        rm -rf -- "$work_root"
        printf 'quickshell_cursor_theme.sh: failed to compile %s as hyprcursor.\n' "$theme" >&2
        return 1
    fi

    for candidate in "$create_parent"/*; do
        if [[ -d "$candidate" && -f "$candidate/manifest.hl" && -d "$candidate/hyprcursors" ]]; then
            compiled="$candidate"
            break
        fi
    done
    if [[ -z "$compiled" ]]; then
        rm -rf -- "$work_root"
        printf 'quickshell_cursor_theme.sh: compiled hyprcursor output is missing for %s.\n' "$theme" >&2
        return 1
    fi

    cp -a -- "${compiled}/manifest.hl" "${theme_dir}/manifest.hl"
    rm -rf -- "${theme_dir}/hyprcursors"
    cp -a -- "${compiled}/hyprcursors" "${theme_dir}/hyprcursors"
    rm -rf -- "$work_root"
}

write_managed_files() {
    local theme="$1"
    python3 - "$HYPR_CONFIG" "$GTK3_SETTINGS" "$NWG_SETTINGS" "$XRESOURCES" "$theme" <<'PY'
from pathlib import Path
import re
import sys

hypr = Path(sys.argv[1])
gtk3 = Path(sys.argv[2])
nwg = Path(sys.argv[3])
xresources = Path(sys.argv[4])
theme = sys.argv[5]


def replace_required(path: Path, pattern: str, replacement: str, label: str) -> None:
    text = path.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one managed cursor setting in {path}")
    path.write_text(updated)


replace_required(
    hypr,
    r'^hl\.env\("XCURSOR_THEME",\s*"[^"]+"\)$',
    f'hl.env("XCURSOR_THEME", "{theme}")',
    "Hyprland",
)
replace_required(
    gtk3,
    r'^gtk-cursor-theme-name=.*$',
    f'gtk-cursor-theme-name={theme}',
    "GTK3",
)
replace_required(
    nwg,
    r'^cursor-theme=.*$',
    f'cursor-theme={theme}',
    "nwg-look",
)
replace_required(
    xresources,
    r'^Xcursor\.theme:.*$',
    f'Xcursor.theme: {theme}',
    "Xresources",
)
PY
}

apply_live_settings() {
    local theme="$1" hyprcursor_ready=0

    if ensure_hyprcursor_theme "$theme"; then
        hyprcursor_ready=1
    fi

    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface cursor-theme "$theme" >/dev/null 2>&1 || true
        gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE" >/dev/null 2>&1 || true
    fi

    if command -v flatpak >/dev/null 2>&1; then
        flatpak override --user --env="GTK_CURSOR_THEME=${theme}" >/dev/null 2>&1 || true
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user set-environment "XCURSOR_THEME=${theme}" "XCURSOR_SIZE=${CURSOR_SIZE}" >/dev/null 2>&1 || true
    fi

    if command -v dbus-update-activation-environment >/dev/null 2>&1; then
        XCURSOR_THEME="$theme" XCURSOR_SIZE="$CURSOR_SIZE" \
            dbus-update-activation-environment --systemd XCURSOR_THEME XCURSOR_SIZE >/dev/null 2>&1 || true
    fi

    if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        hyprctl reload >/dev/null 2>&1 || true
        if (( hyprcursor_ready == 0 )); then
            return 1
        fi
        if ! hyprctl setcursor "$theme" "$CURSOR_SIZE" >/dev/null 2>&1; then
            printf 'quickshell_cursor_theme.sh: Hyprland could not switch the compositor cursor to %s.\n' "$theme" >&2
            return 1
        fi
    fi
}

apply_variant() {
    local variant="$1" theme
    theme="$(variant_theme "$variant")" || {
        printf 'quickshell_cursor_theme.sh: invalid cursor variant: %s\n' "$variant" >&2
        return 2
    }

    require_bibata_themes || return 1
    sync_bibata_themes
    mkdir -p -- "${DATA_HOME}/icons/default"
    printf "[Icon Theme]\nInherits=%s\n" "$theme" >"${DATA_HOME}/icons/default/index.theme"
    write_managed_files "$theme"
    apply_live_settings "$theme"
}

set_variant() {
    local variant="$1"
    variant_theme "$variant" >/dev/null || {
        printf 'quickshell_cursor_theme.sh: invalid cursor variant: %s\n' "$variant" >&2
        return 2
    }
    [[ -x "$STATE_SCRIPT" || -f "$STATE_SCRIPT" ]] || {
        printf 'quickshell_cursor_theme.sh: state writer is unavailable: %s\n' "$STATE_SCRIPT" >&2
        return 1
    }
    bash "$STATE_SCRIPT" set-cursor-theme "$variant"
    apply_variant "$variant"
}

case "${1:-status}" in
    status)
        saved_variant
        ;;
    set)
        [[ -n ${2:-} ]] || {
            printf 'usage: %s set <ice|classic>\n' "${0##*/}" >&2
            exit 2
        }
        set_variant "$2"
        ;;
    reapply)
        apply_variant "$(saved_variant)"
        ;;
    *)
        printf 'usage: %s {status|set <ice|classic>|reapply}\n' "${0##*/}" >&2
        exit 2
        ;;
esac
