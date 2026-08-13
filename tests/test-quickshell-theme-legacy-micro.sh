#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_APPLY="${ROOT}/config/hypr/scripts/quickshell_theme_apply.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

home="${TMP}/home"
config="${home}/.config"
fakebin="${TMP}/fakebin"
mkdir -p "${config}/hypr/themes" "${config}/hypr" "${config}/micro" \
  "${config}/quickshell/awtarchy" "$fakebin"

cp -- "${ROOT}/config/hypr/themes/gruvbox" "${config}/hypr/themes/gruvbox"
cat >"${config}/hypr/hyprland.lua" <<'LUA'
local config = {
    general = {
        col = {
            active_border = "rgba(a0a0a0ff)",
            inactive_border = "rgba(4b4b4bff)",
        },
    },
}
return config
LUA

cat >"${config}/micro/settings.json" <<'JSON'
{
    "colorscheme": "gruvbox",
}
JSON

cat >"${fakebin}/hyprctl" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod 0755 "${fakebin}/hyprctl"

HOME="$home" XDG_CONFIG_HOME="$config" XDG_STATE_HOME="${home}/.local/state" \
  PATH="${fakebin}:$PATH" bash "$THEME_APPLY" gruvbox

python3 - "${config}/micro/settings.json" "${config}/quickshell/awtarchy/theme.json" <<'PY'
from pathlib import Path
import json
import sys

micro = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
theme = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if micro.get("colorscheme") != "gruvbox":
    raise SystemExit("legacy Micro settings were not repaired")
if theme.get("background") != "#282828":
    raise SystemExit("Gruvbox Quickshell palette was not generated")
PY

python3 - "${ROOT}/config/hypr/themes" <<'PY'
from pathlib import Path
import re
import sys


def relative_luminance(value):
    channels = [int(value[index:index + 2], 16) / 255 for index in (1, 3, 5)]
    linear = [
        channel / 12.92 if channel <= 0.04045
        else ((channel + 0.055) / 1.055) ** 2.4
        for channel in channels
    ]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast(left, right):
    high, low = sorted(
        (relative_luminance(left), relative_luminance(right)), reverse=True
    )
    return (high + 0.05) / (low + 0.05)


theme_dir = Path(sys.argv[1])
for name in ("gruvbox", "catppuccin-frappé", "crimson_red", "electric_blue"):
    text = (theme_dir / name).read_text(encoding="utf-8")
    palette = dict(re.findall(r'^(QS_[A-Z]+)="(#[0-9a-fA-F]{6})"$', text, re.MULTILINE))
    checks = {
        "foreground/background": (palette["QS_FOREGROUND"], palette["QS_BACKGROUND"]),
        "foreground/focus": (palette["QS_FOREGROUND"], palette["QS_FOCUS"]),
        "foreground/hover": (palette["QS_FOREGROUND"], palette["QS_HOVER"]),
        "foreground/active": (palette["QS_FOREGROUND"], palette["QS_ACTIVE"]),
        "muted/background": (palette["QS_MUTED"], palette["QS_BACKGROUND"]),
    }
    for label, colors in checks.items():
        ratio = contrast(*colors)
        if ratio < 4.5:
            raise SystemExit(f"{name} {label} contrast is only {ratio:.2f}:1")
PY

printf '%s\n' 'Quickshell legacy Micro theme migration test passed.'
