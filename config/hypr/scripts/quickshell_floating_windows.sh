#!/usr/bin/env bash
set -Eeuo pipefail

HYPR_LUA="${HYPRLAND_LUA:-${XDG_CONFIG_HOME:-${HOME}/.config}/hypr/hyprland.lua}"
HYPRCTL="${HYPRCTL:-hyprctl}"
MARKER_RE='^[[:space:]]*local awtarchy_floating_windows = (true|false) -- AWTARCHY_FLOATING_WINDOWS[[:space:]]*$'
GLOBAL_FLOAT='hl.window_rule({ match = { class = ".*" }, float = true })'
GAME_TILE='hl.window_rule({ match = { class = games }, tile = true })'
GAMES_ANCHOR_RE='^[[:space:]]*local games = '

die() {
    printf 'Floating Windows: %s\n' "$*" >&2
    exit 1
}

marker_count() {
    grep -Ec "$MARKER_RE" "$HYPR_LUA" || true
}

legacy_config_is_bootstrappable() {
    local marker global_float game_tile games_anchor
    marker="$(marker_count)"
    [[ "$marker" == "0" ]] || return 1

    global_float="$(grep -Fc "$GLOBAL_FLOAT" "$HYPR_LUA" || true)"
    game_tile="$(grep -Fc "$GAME_TILE" "$HYPR_LUA" || true)"
    games_anchor="$(grep -Ec "$GAMES_ANCHOR_RE" "$HYPR_LUA" || true)"

    [[ "$global_float" == "0" && "$game_tile" == "0" && "$games_anchor" == "1" ]]
}

current_state() {
    [[ -r "$HYPR_LUA" ]] || die "cannot read $HYPR_LUA"

    local count line
    count="$(marker_count)"
    case "$count" in
        0)
            if legacy_config_is_bootstrappable; then
                printf '%s\n' 'disabled'
                return 0
            fi
            die "Floating Windows is not initialized safely in $HYPR_LUA"
            ;;
        1)
            line="$(grep -E "$MARKER_RE" "$HYPR_LUA")"
            case "$line" in
                *'= true -- AWTARCHY_FLOATING_WINDOWS') printf '%s\n' 'enabled' ;;
                *'= false -- AWTARCHY_FLOATING_WINDOWS') printf '%s\n' 'disabled' ;;
                *) die 'could not parse Floating Windows state' ;;
            esac
            ;;
        *)
            die "expected at most one AWTARCHY_FLOATING_WINDOWS setting in $HYPR_LUA"
            ;;
    esac
}

rollback_config() {
    local backup="$1"
    cp -p -- "$backup" "$HYPR_LUA"
    "$HYPRCTL" reload >/dev/null 2>&1 || true
}

set_state() {
    local requested="$1"
    local target current pre_errors post_errors backup

    case "$requested" in
        on|enabled|true) target='true' ;;
        off|disabled|false) target='false' ;;
        *) die "invalid state '$requested' (expected on or off)" ;;
    esac

    current="$(current_state)"
    if [[ ( "$target" == 'true' && "$current" == 'enabled' ) \
        || ( "$target" == 'false' && "$current" == 'disabled' ) ]]; then
        printf '%s\n' "$current"
        return 0
    fi

    [[ -w "$HYPR_LUA" ]] || die "cannot write $HYPR_LUA"

    if ! pre_errors="$("$HYPRCTL" configerrors 2>&1)"; then
        die 'could not query current Hyprland config errors'
    fi
    if [[ -n "$pre_errors" ]]; then
        die "refusing to edit while Hyprland already reports config errors: $pre_errors"
    fi

    backup="$(mktemp --tmpdir="$(dirname -- "$HYPR_LUA")" '.awtarchy-floating-windows.backup.XXXXXX')"
    cp -p -- "$HYPR_LUA" "$backup"

    if ! python3 - "$HYPR_LUA" "$target" <<'PY'
import os
import re
import stat
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
target = sys.argv[2].encode()
data = path.read_bytes()
marker_pattern = re.compile(
    rb'(?m)^([ \t]*local awtarchy_floating_windows = )(true|false)( -- AWTARCHY_FLOATING_WINDOWS[ \t]*)$'
)
marker_matches = list(marker_pattern.finditer(data))

if len(marker_matches) == 1:
    replacement = rb'\g<1>' + target + rb'\g<3>'
    updated, count = marker_pattern.subn(replacement, data)
    if count != 1:
        raise SystemExit('expected exactly one AWTARCHY_FLOATING_WINDOWS setting')
elif len(marker_matches) == 0:
    if target != b'true':
        raise SystemExit('uninitialized Floating Windows config may only be bootstrapped while enabling')

    global_float = b'hl.window_rule({ match = { class = ".*" }, float = true })'
    game_tile = b'hl.window_rule({ match = { class = games }, tile = true })'
    if global_float in data or game_tile in data:
        raise SystemExit('refusing to bootstrap around partial Floating Windows rules')

    games_pattern = re.compile(rb'(?m)^([ \t]*local games = .*\n)')
    games_matches = list(games_pattern.finditer(data))
    if len(games_matches) != 1:
        raise SystemExit('expected exactly one games rule anchor for Floating Windows bootstrap')

    match = games_matches[0]
    games_line = match.group(1)
    block = (
        b'local awtarchy_floating_windows = true -- AWTARCHY_FLOATING_WINDOWS\n\n'
        + games_line
        + b'\n'
        + b'if awtarchy_floating_windows then\n'
        + b'    hl.window_rule({ match = { class = ".*" }, float = true })\n'
        + b'    hl.window_rule({ match = { class = games }, tile = true })\n'
        + b'end\n'
    )
    updated = data[:match.start()] + block + data[match.end():]
else:
    raise SystemExit('expected at most one AWTARCHY_FLOATING_WINDOWS setting')

mode = stat.S_IMODE(path.stat().st_mode)
with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.awtarchy-floating-windows.', delete=False) as handle:
    temp_path = Path(handle.name)
    handle.write(updated)
    handle.flush()
    os.fsync(handle.fileno())
os.chmod(temp_path, mode)
os.replace(temp_path, path)
PY
    then
        rm -f -- "$backup"
        die 'failed to update hyprland.lua'
    fi

    if ! "$HYPRCTL" reload >/dev/null 2>&1; then
        rollback_config "$backup"
        rm -f -- "$backup"
        die 'Hyprland reload failed; restored the previous configuration'
    fi

    if ! post_errors="$("$HYPRCTL" configerrors 2>&1)"; then
        rollback_config "$backup"
        rm -f -- "$backup"
        die 'could not validate Hyprland after reload; restored the previous configuration'
    fi
    if [[ -n "$post_errors" ]]; then
        rollback_config "$backup"
        rm -f -- "$backup"
        die "Hyprland reported config errors after reload; restored the previous configuration: $post_errors"
    fi

    rm -f -- "$backup"
    current_state
}

case "${1:-}" in
    status)
        [[ $# -eq 1 ]] || die 'usage: quickshell_floating_windows.sh status'
        current_state
        ;;
    set)
        [[ $# -eq 2 ]] || die 'usage: quickshell_floating_windows.sh set on|off'
        set_state "$2"
        ;;
    *)
        die 'usage: quickshell_floating_windows.sh status | set on|off'
        ;;
esac
