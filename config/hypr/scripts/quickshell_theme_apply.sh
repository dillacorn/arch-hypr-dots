#!/usr/bin/env bash
# Apply an Awtarchy theme without executing obsolete shell-program mutations.
# Existing theme files remain the palette source while Quickshell conversion is tested.

set -euo pipefail

name="${1:-}"
[[ -n "$name" && "$name" != */* && "$name" != .* ]] || exit 2

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
THEME_DIR="$CONFIG_HOME/hypr/themes"
THEME="$THEME_DIR/$name"
QS_THEME="$CONFIG_HOME/quickshell/awtarchy/theme.json"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy"
HYPR_LUA="$CONFIG_HOME/hypr/hyprland.lua"
HYPR_CONF="$CONFIG_HOME/hypr/hyprland.conf"
WOFI_CSS="$CONFIG_HOME/wofi/style.css"
MICRO_SETTINGS="$CONFIG_HOME/micro/settings.json"
ALACRITTY_CONF="$CONFIG_HOME/alacritty/alacritty.toml"
SPEEDCRUNCH_INI="$CONFIG_HOME/SpeedCrunch/SpeedCrunch.ini"

[[ -f "$THEME" ]] || exit 1

theme_value() {
    local key="$1" fallback="$2" value
    value="$(awk -F= -v key="$key" '$1 == key { value=$0; sub(/^[^=]*=/, "", value); gsub(/^[[:space:]]*["\047]|["\047][[:space:]]*$/, "", value); print value; exit }' "$THEME")"
    printf '%s\n' "${value:-$fallback}"
}

extract_theme_metadata() {
    python3 - "$THEME" "$1" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
kind = sys.argv[2]
patterns = {
    "micro": r'"colorscheme"\s*:\s*"([^"]+)"',
    "alacritty": r'themes/themes/([^"\047|]+\.toml)',
    "speedcrunch": r'Display\\ColorSchemeName=([^|\047"\n]+)',
}
match = re.search(patterns[kind], text)
print(match.group(1).strip() if match else "")
PY
}

active_border="$(theme_value NEW_ACTIVE_BORDER 'a0a0a0ff')"
inactive_border="$(theme_value NEW_INACTIVE_BORDER '4b4b4bff')"

background="$(theme_value QS_BACKGROUND '#353535')"
hover="$(theme_value QS_HOVER '#404040')"
focus="$(theme_value QS_FOCUS '#4a4a4a')"
active="$(theme_value QS_ACTIVE '#2b2b2b')"
urgent="$(theme_value QS_URGENT '#ff5555')"
charging="$(theme_value QS_CHARGING '#6a9955')"
critical="$(theme_value QS_CRITICAL '#ff5555')"
foreground="$(theme_value QS_FOREGROUND '#d0d0d0')"
dark="$(theme_value QS_DARK '#1a1a1a')"
muted="$(theme_value QS_MUTED "$hover")"

wo_border="$(theme_value WO_BORDER '2px none #4a4a4a')"
wo_bg="$(theme_value WO_BG "$background")"
wo_input="$(theme_value WO_INPUT_COLOR "$foreground")"
wo_outer_border="$(theme_value WO_OUTER_BORDER '0px solid #4a4a4a')"
wo_outer_bg="$(theme_value WO_OUTER_BG "$background")"
wo_text="$(theme_value WO_TEXT_UNSEL '#ffffff')"

micro_scheme="$(theme_value MICRO_COLORSCHEME 'geany')"
alacritty_theme="$(theme_value ALACRITTY_THEME 'wombat.toml')"
speedcrunch_scheme="$(theme_value SPEEDCRUNCH_COLORSCHEME "$name")"

if [[ -f "$HYPR_LUA" ]]; then
    python3 - "$HYPR_LUA" "$active_border" "$inactive_border" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
values = {
    "active_border": f"rgba({sys.argv[2]})",
    "inactive_border": f"rgba({sys.argv[3]})",
}

for key, value in values.items():
    pattern = re.compile(
        r'(^[ \t]*(?!--)[^\n]*?\b' + re.escape(key) + r'\s*=\s*)"[^"\\]*(?:\\.[^"\\]*)*"',
        re.MULTILINE,
    )
    text, count = pattern.subn(lambda m, v=value: m.group(1) + repr(v).replace("'", '"'), text)
    if count == 0:
        raise SystemExit(f"ERROR: did not find Hyprland Lua key: {key}")

path.write_text(text, encoding="utf-8")
PY
elif [[ -f "$HYPR_CONF" ]]; then
    sed -i \
        -e "s/^ *col\.active_border *= *.*/col.active_border = rgba(${active_border})/" \
        -e "s/^ *col\.inactive_border *= *.*/col.inactive_border = rgba(${inactive_border})/" \
        "$HYPR_CONF"
fi

if [[ -f "$WOFI_CSS" ]]; then
    sed -i \
        -e "/^window[[:space:]]*{/,/^[[:space:]]*}/ s|^[[:space:]]*border:.*;|    border: ${wo_border};|" \
        -e "/^window[[:space:]]*{/,/^[[:space:]]*}/ s|^[[:space:]]*background-color:.*;|    background-color: ${wo_bg};|" \
        -e "/^#input[[:space:]]*{/,/^[[:space:]]*}/ s|^[[:space:]]*color:.*;|    color: ${wo_input};|" \
        -e "/^#outer-box[[:space:]]*{/,/^[[:space:]]*}/ s|^[[:space:]]*border:.*;|    border: ${wo_outer_border};|" \
        -e "/^#outer-box[[:space:]]*{/,/^[[:space:]]*}/ s|^[[:space:]]*background-color:.*;|    background-color: ${wo_outer_bg};|" \
        -e "/^#text/,/^[[:space:]]*}/ s|^[[:space:]]*color:.*;|    color: ${wo_text};|" \
        "$WOFI_CSS"
fi

if [[ -n "$micro_scheme" && -f "$MICRO_SETTINGS" ]]; then
    python3 - "$MICRO_SETTINGS" "$micro_scheme" <<'PY'
from pathlib import Path
import json
import sys

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["colorscheme"] = sys.argv[2]
path.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
PY
fi

if [[ -n "$alacritty_theme" && -f "$ALACRITTY_CONF" ]]; then
    python3 - "$ALACRITTY_CONF" "$alacritty_theme" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
target = f'~/.config/alacritty/themes/themes/{sys.argv[2]}'
text, count = re.subn(r'~/.config/alacritty/themes/themes/[^"\n]+\.toml', target, text)
if count:
    path.write_text(text, encoding="utf-8")
PY
fi

if [[ -n "$speedcrunch_scheme" && -f "$SPEEDCRUNCH_INI" ]]; then
    python3 - "$SPEEDCRUNCH_INI" "$speedcrunch_scheme" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text, count = re.subn(r'(?m)^Display\\ColorSchemeName=.*$', f'Display\\\\ColorSchemeName={sys.argv[2]}', text)
if count:
    path.write_text(text, encoding="utf-8")
PY
fi

mkdir -p "$(dirname "$QS_THEME")" "$STATE_DIR"
python3 - "$QS_THEME" \
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
command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
