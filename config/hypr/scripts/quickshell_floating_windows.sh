#!/usr/bin/env bash
set -Eeuo pipefail

HYPR_LUA="${HYPRLAND_LUA:-${XDG_CONFIG_HOME:-${HOME}/.config}/hypr/hyprland.lua}"
HYPRCTL="${HYPRCTL:-hyprctl}"
MARKER_RE='^[[:space:]]*local awtarchy_floating_windows = (true|false) -- AWTARCHY_FLOATING_WINDOWS[[:space:]]*$'

die() {
    printf 'Floating Windows: %s\n' "$*" >&2
    exit 1
}

current_state() {
    [[ -r "$HYPR_LUA" ]] || die "cannot read $HYPR_LUA"

    local count line
    count="$(grep -Ec "$MARKER_RE" "$HYPR_LUA" || true)"
    [[ "$count" == "1" ]] || die "expected exactly one AWTARCHY_FLOATING_WINDOWS setting in $HYPR_LUA"

    line="$(grep -E "$MARKER_RE" "$HYPR_LUA")"
    case "$line" in
        *'= true -- AWTARCHY_FLOATING_WINDOWS') printf '%s\n' 'enabled' ;;
        *'= false -- AWTARCHY_FLOATING_WINDOWS') printf '%s\n' 'disabled' ;;
        *) die 'could not parse Floating Windows state' ;;
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
pattern = re.compile(
    rb'(?m)^([ \t]*local awtarchy_floating_windows = )(true|false)( -- AWTARCHY_FLOATING_WINDOWS[ \t]*)$'
)
replacement = rb'\g<1>' + target + rb'\g<3>'
updated, count = pattern.subn(replacement, data)
if count != 1:
    raise SystemExit('expected exactly one AWTARCHY_FLOATING_WINDOWS setting')

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
