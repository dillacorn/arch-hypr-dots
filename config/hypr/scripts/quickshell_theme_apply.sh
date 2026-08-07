#!/usr/bin/env bash
# Apply an existing Awtarchy theme and export its shell colors to Quickshell.

set -euo pipefail

name="${1:-}"
[[ -n "$name" && "$name" != */* && "$name" != .* ]] || exit 2

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
THEME_DIR="$CONFIG_HOME/hypr/themes"
THEME="$THEME_DIR/$name"
QS_THEME="$CONFIG_HOME/quickshell/awtarchy/theme.json"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy"

[[ -f "$THEME" && -x "$THEME" ]] || exit 1

# Extract the existing Awtarchy shell color variables without sourcing the
# theme script. This keeps the Quickshell theme native and avoids tying its
# runtime to Waybar/Fuzzel/Mako/wlogout config formats.
theme_value() {
    local key="$1" fallback="$2" value
    value="$(awk -F= -v key="$key" '$1 == key { value=$0; sub(/^[^=]*=/, "", value); gsub(/^[[:space:]]*["\047]|["\047][[:space:]]*$/, "", value); print value; exit }' "$THEME")"
    printf '%s\n' "${value:-$fallback}"
}

background="$(theme_value W_BG '#353535')"
hover="$(theme_value W_CUSTOM_HOVER_BG '#404040')"
focus="$(theme_value W_FOCUS_BG '#4a4a4a')"
active="$(theme_value W_ACTIVE_BG '#2b2b2b')"
urgent="$(theme_value W_URGENT_BG '#ff5555')"
charging="$(theme_value W_BATT_CHARGING_BG '#6a9955')"
critical="$(theme_value W_BATT_CRITICAL_BG '#ff5555')"
foreground="$(theme_value W_COLOR '#d0d0d0')"
dark="$(theme_value W_URGENT_COLOR '#1a1a1a')"
muted="$(theme_value W_MUTED "$hover")"

# Keep the rest of each existing Awtarchy theme behavior intact during the
# conversion period: Hyprland, Wofi, terminal, editor, calculator, etc.
"$THEME"

mkdir -p "$(dirname "$QS_THEME")" "$STATE_DIR"
python - "$QS_THEME" \
    "$background" "$hover" "$focus" "$active" "$urgent" \
    "$charging" "$critical" "$foreground" "$dark" "$muted" <<'PY'
import json
import os
import sys
import tempfile

path = sys.argv[1]
keys = (
    "background", "hover", "focus", "active", "urgent",
    "charging", "critical", "foreground", "dark", "muted",
)
data = dict(zip(keys, sys.argv[2:]))

fd, tmp = tempfile.mkstemp(prefix="theme.", suffix=".json", dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY

printf '%s\n' "$name" >"$STATE_DIR/active-theme"
