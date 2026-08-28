#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
BAR_SETTINGS="${ROOT}/config/quickshell/awtarchy/BarIconSettings.qml"
BAR_BUTTON="${ROOT}/config/quickshell/awtarchy/BarButton.qml"
BAR_QML="${ROOT}/config/quickshell/awtarchy/Bar.qml"
STATE_SCRIPT="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

not_contains() {
    if grep -Fq -- "$2" "$1"; then
        fail "$3"
    fi
}

for style in phases dots diamonds squares triangles minimal; do
    contains "$BAR_STATE" "key: \"${style}\"" \
        "workspace pack catalog is missing ${style}"
done
not_contains "$BAR_STATE" 'key: "spark"' \
    'Spark is still exposed as a workspace icon preset'
not_contains "$BAR_STATE" 'key: "center-diamond"' \
    'Center Diamond is still exposed as a standalone workspace icon preset'

python3 - "$BAR_STATE" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
for key in ("awtarchy", "phases", "dots", "diamonds", "squares", "triangles", "minimal"):
    match = re.search(r'\{\s*key:\s*"' + re.escape(key) + r'".*?symbols:\s*\[([^]]+)\].*?glyphSize:\s*(\d+)', text, re.S)
    if not match:
        raise SystemExit(f"missing symbols/glyphSize for {key}")
    symbols = re.findall(r'"([^"]*)"', match.group(1))
    if len(symbols) != 10:
        raise SystemExit(f"{key} must expose exactly 10 symbols, found {len(symbols)}")
    if key in {"phases", "dots"} and int(match.group(2)) < 19:
        raise SystemExit(f"{key} glyph size was not increased")
PY

contains "$BAR_STATE" 'function workspaceIconPackFor(style)' \
    'BarState has no pack lookup helper'
contains "$BAR_STATE" 'function workspaceIconPixelSize()' \
    'BarState has no per-pack workspace glyph sizing helper'
contains "$BAR_STATE" 'pack.symbols[value - 1]' \
    'workspace icon resolver does not select a different pack symbol per workspace'

contains "$BAR_SETTINGS" 'function copyText(text)' \
    'workspace icon settings have no clipboard helper'
contains "$BAR_SETTINGS" '["wl-copy", text]' \
    'workspace icon settings do not use wl-copy for symbol copying'
contains "$BAR_SETTINGS" 'model: packRow.modelData.symbols' \
    'workspace icon preset does not preview its complete symbol pack'
contains "$BAR_SETTINGS" 'modelData.symbols.join(" ")' \
    'workspace icon preset has no whole-pack copy action'
contains "$BAR_SETTINGS" 'label: ""' \
    'workspace icon preset has no copy icon control'
contains "$BAR_SETTINGS" 'root.copyText(String(modelData))' \
    'individual workspace symbols cannot be copied from the preview'

contains "$BAR_BUTTON" 'property bool workspaceButton: false' \
    'BarButton cannot distinguish workspace controls for glyph sizing'
contains "$BAR_BUTTON" 'property int workspaceGlyphSize: 0' \
    'BarButton has no per-pack workspace glyph size input'
contains "$BAR_QML" 'workspaceButton: true' \
    'workspace bar buttons are not marked for dedicated glyph sizing'
contains "$BAR_QML" 'workspaceGlyphSize: BarState.workspaceIconPixelSize()' \
    'workspace bar buttons do not consume the selected pack glyph size'

CACHE_HOME="${TMP}/cache"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
mkdir -p "$(dirname -- "$STATE_FILE")" "$TMP/home"
printf '%s\n' '{"enabled":true,"bar_appearance":{},"unrelated":{"preserve":true}}' >"$STATE_FILE"

run_state() {
    env \
        HOME="$TMP/home" \
        XDG_CACHE_HOME="$CACHE_HOME" \
        HYPR_QUICKSHELL_SCRIPT="$TMP/missing-quickshell.sh" \
        bash "$STATE_SCRIPT" "$@"
}

for style in phases dots diamonds squares triangles minimal; do
    run_state set-workspace-icon-style "$style"
    jq -e --arg style "$style" '
        .bar_appearance.workspace_icon_style == $style
        and .unrelated.preserve == true
    ' "$STATE_FILE" >/dev/null || fail "state writer did not persist ${style}"
done

cp "$STATE_FILE" "$TMP/before-spark.json"
if run_state set-workspace-icon-style spark >/dev/null 2>&1; then
    fail 'state writer still accepts removed Spark preset'
fi
cmp -s "$STATE_FILE" "$TMP/before-spark.json" \
    || fail 'rejected Spark preset modified persistent state'

printf '%s\n' 'PASS: workspace icon packs, copy helpers, and per-pack sizing are validated.'
