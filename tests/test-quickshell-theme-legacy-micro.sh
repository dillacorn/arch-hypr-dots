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

printf '%s\n' 'Quickshell legacy Micro theme migration test passed.'
