#!/usr/bin/env bash
set -Eeuo pipefail

HYPR_LUA="${HYPRLAND_LUA:-${XDG_CONFIG_HOME:-${HOME}/.config}/hypr/hyprland.lua}"

fail() {
    printf 'error: %s\n' "$*" >&2
    return 1
}

valid_scale() {
    case "${1:-}" in
        1|1.25|1.5|2) return 0 ;;
        *) return 1 ;;
    esac
}

scale_ratio() {
    case "${1:-}" in
        1) printf '%s\n' '1 1' ;;
        1.25) printf '%s\n' '5 4' ;;
        1.5) printf '%s\n' '3 2' ;;
        2) printf '%s\n' '2 1' ;;
        *) return 1 ;;
    esac
}

monitor_status() {
    local monitor="$1"

    command -v hyprctl >/dev/null 2>&1 || fail 'hyprctl is unavailable'
    command -v jq >/dev/null 2>&1 || fail 'jq is unavailable'

    hyprctl -j monitors | jq -cer --arg monitor "$monitor" '
        .[]
        | select((.name // "") == $monitor and ((.disabled // false) | not))
        | {
            scale: ((.scale // 1) | tonumber),
            width: ((.width // 0) | tonumber),
            height: ((.height // 0) | tonumber)
          }
    '
}

scale_compatible() {
    local width="$1"
    local height="$2"
    local scale="$3"
    local numerator denominator

    read -r numerator denominator < <(scale_ratio "$scale") || return 1
    (( width > 0 && height > 0 )) || return 1
    (( (width * denominator) % numerator == 0 )) || return 1
    (( (height * denominator) % numerator == 0 ))
}

has_config_errors() {
    local output="$1"
    [[ -n ${output//[[:space:]]/} ]]
}

rewrite_monitor_scale() {
    local monitor="$1"
    local scale="$2"

    command -v python3 >/dev/null 2>&1 || fail 'python3 is unavailable'

    python3 - "$HYPR_LUA" "$monitor" "$scale" <<'PY'
from __future__ import annotations

import json
import os
import pathlib
import re
import sys
import tempfile

path = pathlib.Path(sys.argv[1])
monitor = sys.argv[2]
scale = sys.argv[3]
text = path.read_text(encoding="utf-8")

block_re = re.compile(r"hl\.monitor\s*\(\s*\{.*?\}\s*\)", re.DOTALL)
output_re = re.compile(r'\boutput\s*=\s*"((?:\\.|[^"\\])*)"')
scale_re = re.compile(r"(\bscale\s*=\s*)([^,}\n]+)")


def output_name(block: str) -> str | None:
    match = output_re.search(block)
    if not match:
        return None
    try:
        return json.loads('"' + match.group(1) + '"')
    except json.JSONDecodeError:
        return None


def replace_scale(block: str) -> str:
    if scale_re.search(block):
        return scale_re.sub(lambda match: match.group(1) + scale, block, count=1)

    close = block.rfind("}")
    if close < 0:
        raise RuntimeError("monitor rule has no closing table brace")
    before = block[:close]
    stripped = before.rstrip()
    separator = "" if stripped.endswith(("{", ",")) else ","
    spacing = before[len(stripped):]
    return stripped + separator + " scale = " + scale + spacing + block[close:]


matches = list(block_re.finditer(text))
explicit = None
fallback = None
for match in matches:
    name = output_name(match.group(0))
    if name == monitor:
        explicit = match
        break
    if name == "" and fallback is None:
        fallback = match

if explicit is not None:
    old_block = explicit.group(0)
    new_block = replace_scale(old_block)
    updated = text[:explicit.start()] + new_block + text[explicit.end():]
elif fallback is not None:
    old_block = fallback.group(0)
    escaped_monitor = json.dumps(monitor, ensure_ascii=False)
    new_block = output_re.sub(lambda match: "output = " + escaped_monitor, old_block, count=1)
    new_block = replace_scale(new_block)
    updated = text[:fallback.end()] + "\n" + new_block + text[fallback.end():]
else:
    raise RuntimeError("no explicit or fallback hl.monitor rule is available")

if updated == text:
    raise SystemExit(0)

stat = path.stat()
fd, temp_name = tempfile.mkstemp(prefix=".awtarchy-display-scale-", dir=str(path.parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
        handle.write(updated)
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temp_name, stat.st_mode & 0o7777)
    os.replace(temp_name, path)
finally:
    try:
        os.unlink(temp_name)
    except FileNotFoundError:
        pass
PY
}

rollback_config() {
    local backup="$1"

    cp --preserve=mode -- "$backup" "$HYPR_LUA" || return 1
    hyprctl reload >/dev/null 2>&1 || true
}

set_scale() {
    local monitor="$1"
    local scale="$2"
    local status width height existing_errors post_errors backup

    [[ -n $monitor ]] || fail 'monitor name is required'
    valid_scale "$scale" || fail "unsupported display scale: $scale"
    [[ -f $HYPR_LUA ]] || fail "Hyprland config is missing: $HYPR_LUA"
    [[ -r $HYPR_LUA && -w $HYPR_LUA ]] || fail "Hyprland config is not readable and writable: $HYPR_LUA"

    status="$(monitor_status "$monitor")" || fail "monitor is unavailable: $monitor"
    width="$(jq -r '.width' <<<"$status")"
    height="$(jq -r '.height' <<<"$status")"
    scale_compatible "$width" "$height" "$scale" \
        || fail "display scale $scale is incompatible with ${width}x${height} on $monitor"

    existing_errors="$(hyprctl configerrors 2>&1)" \
        || fail 'could not validate the current Hyprland configuration'
    has_config_errors "$existing_errors" \
        && fail 'Hyprland already reports configuration errors; refusing to rewrite hyprland.lua'

    backup="$(mktemp --tmpdir="$(dirname -- "$HYPR_LUA")" .awtarchy-display-scale-backup.XXXXXX)" \
        || fail 'could not create a Hyprland config backup'
    if ! cp --preserve=mode -- "$HYPR_LUA" "$backup"; then
        rm -f -- "$backup"
        fail 'could not back up hyprland.lua'
        return 1
    fi

    if ! rewrite_monitor_scale "$monitor" "$scale"; then
        rm -f -- "$backup"
        fail 'could not update the requested monitor scale'
        return 1
    fi

    if ! hyprctl reload >/dev/null 2>&1; then
        rollback_config "$backup" || true
        rm -f -- "$backup"
        fail 'Hyprland reload failed; restored the previous configuration'
        return 1
    fi

    if ! post_errors="$(hyprctl configerrors 2>&1)"; then
        rollback_config "$backup" || true
        rm -f -- "$backup"
        fail 'could not validate the reloaded Hyprland configuration; restored the previous configuration'
        return 1
    fi

    if has_config_errors "$post_errors"; then
        rollback_config "$backup" || true
        rm -f -- "$backup"
        fail 'Hyprland reported configuration errors after reload; restored the previous configuration'
        return 1
    fi

    rm -f -- "$backup"
    monitor_status "$monitor"
}

usage() {
    printf '%s\n' \
        'Usage:' \
        '  quickshell_display_scale.sh status MONITOR' \
        '  quickshell_display_scale.sh set MONITOR SCALE'
}

main() {
    local action="${1:-}"

    case "$action" in
        status)
            [[ $# -eq 2 ]] || { usage >&2; return 2; }
            monitor_status "$2"
            ;;
        set)
            [[ $# -eq 3 ]] || { usage >&2; return 2; }
            set_scale "$2" "$3"
            ;;
        *)
            usage >&2
            return 2
            ;;
    esac
}

main "$@"
