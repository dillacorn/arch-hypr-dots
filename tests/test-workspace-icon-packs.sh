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

for style in phases dots diamonds; do
    contains "$BAR_STATE" "key: \"${style}\"" \
        "workspace pack catalog is missing ${style}"
done
for removed_style in squares triangles minimal spark center-diamond; do
    not_contains "$BAR_STATE" "key: \"${removed_style}\"" \
        "workspace pack catalog still exposes ${removed_style}"
done

python3 - "$BAR_STATE" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index("readonly property var workspaceIconStylePresets:")
end = text.index("readonly property var workspaceStylePresets:", start)
catalog = text[start:end]
keys = re.findall(r'key:\s*"([^"]+)"', catalog)
expected = ["off", "awtarchy", "phases", "dots", "diamonds", "custom-symbol"]
if keys != expected:
    raise SystemExit(f"workspace icon catalog must be curated as {expected}, found {keys}")

packs = {}
for key in ("awtarchy", "phases", "dots", "diamonds"):
    match = re.search(
        r'\{\s*key:\s*"' + re.escape(key)
        + r'".*?symbols:\s*\[([^]]+)\].*?glyphSize:\s*(\d+)',
        catalog,
        re.S,
    )
    if not match:
        raise SystemExit(f"missing symbols/glyphSize for {key}")
    symbols = re.findall(r'"([^"]*)"', match.group(1))
    if len(symbols) != 10:
        raise SystemExit(f"{key} must expose exactly 10 symbols, found {len(symbols)}")
    packs[key] = (symbols, int(match.group(2)))

if packs["phases"][1] < 22:
    raise SystemExit("phases glyph size must be at least 22px")
if packs["dots"][0] != ["●"] * 10:
    raise SystemExit(f"dots must be a consistent solid-dot pack, found {packs['dots'][0]}")
if packs["diamonds"][0] != ["◆"] * 10:
    raise SystemExit(f"diamonds must be a consistent filled-diamond pack, found {packs['diamonds'][0]}")
PY

for alias in \
    '"filled-dot": "dots"' \
    '"squares": "diamonds"' \
    '"triangles": "diamonds"' \
    '"minimal": "dots"' \
    '"spark": "dots"'
do
    contains "$BAR_STATE" "$alias" \
        "legacy workspace style migration is missing ${alias}"
done

contains "$BAR_STATE" 'function workspaceIconPackFor(style)' \
    'BarState has no pack lookup helper'
contains "$BAR_STATE" 'function workspaceIconPixelSize()' \
    'BarState has no per-pack workspace glyph sizing helper'
contains "$BAR_STATE" 'pack.symbols[value - 1]' \
    'workspace icon resolver does not select the pack symbol for each workspace'

contains "$BAR_SETTINGS" 'function copyText(text)' \
    'workspace icon settings have no clipboard helper'
contains "$BAR_SETTINGS" '["wl-copy", text]' \
    'workspace icon settings do not use wl-copy for symbol copying'
contains "$BAR_SETTINGS" 'property string workspaceCopyFeedback: ""' \
    'workspace copy feedback state is missing'
contains "$BAR_SETTINGS" 'property string launcherCopyFeedback: ""' \
    'launcher copy feedback state is missing'
contains "$BAR_SETTINGS" 'id: workspaceCopyFeedbackTimer' \
    'workspace copy feedback has no timeout'
contains "$BAR_SETTINGS" 'id: launcherCopyFeedbackTimer' \
    'launcher copy feedback has no timeout'
contains "$BAR_SETTINGS" 'model: packRow.modelData.symbols' \
    'workspace icon preset does not preview its complete symbol pack'
contains "$BAR_SETTINGS" 'root.copyWorkspaceSymbol(' \
    'individual workspace symbols cannot be copied with scoped feedback'
contains "$BAR_SETTINGS" 'String(symbolCell.modelData), symbolCell.copyKey' \
    'workspace symbol copy does not use the bound delegate value and key'
contains "$BAR_SETTINGS" 'root.copyWorkspacePack(packRow.modelData)' \
    'workspace icon preset has no explicit whole-pack copy action'
contains "$BAR_SETTINGS" '"✓ Copied all" : " Copy all"' \
    'Copy all control does not visibly confirm success'
contains "$BAR_SETTINGS" 'text: root.workspaceCopyFeedback' \
    'workspace heading does not expose copy feedback'
contains "$BAR_SETTINGS" 'root.copyLauncherIcon(launcherPreset.modelData.value)' \
    'application launcher presets have no copy action'
contains "$BAR_SETTINGS" 'label: " Copy"' \
    'application launcher copy action is not explicit'
contains "$BAR_SETTINGS" 'text: root.launcherCopyFeedback' \
    'application launcher heading does not expose copy feedback'
contains "$BAR_SETTINGS" 'https://www.nerdfonts.com/cheat-sheet' \
    'workspace editor does not link to the Nerd Fonts cheat sheet'
contains "$BAR_SETTINGS" 'https://symbl.cc/en/unicode/' \
    'workspace editor does not link to a Unicode symbol browser'
contains "$BAR_SETTINGS" 'Qt.openUrlExternally' \
    'icon-resource controls do not open their URLs'

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

for style in phases dots diamonds; do
    run_state set-workspace-icon-style "$style"
    jq -e --arg style "$style" '
        .bar_appearance.workspace_icon_style == $style
        and .unrelated.preserve == true
    ' "$STATE_FILE" >/dev/null || fail "state writer did not persist ${style}"
done

for removed_style in squares triangles minimal spark; do
    cp "$STATE_FILE" "$TMP/before-${removed_style}.json"
    if run_state set-workspace-icon-style "$removed_style" >/dev/null 2>&1; then
        fail "state writer still accepts removed ${removed_style} preset"
    fi
    cmp -s "$STATE_FILE" "$TMP/before-${removed_style}.json" \
        || fail "rejected ${removed_style} preset modified persistent state"
done

printf '%s\n' 'PASS: curated workspace packs, copy feedback, launcher copying, and icon resources are validated.'
