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

for style in workflow phases; do
    contains "$BAR_STATE" "key: \"${style}\"" \
        "workspace pack catalog is missing ${style}"
done
for removed_style in dots diamonds squares triangles minimal spark center-diamond; do
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
expected = ["off", "awtarchy", "workflow", "phases", "custom-symbol"]
if keys != expected:
    raise SystemExit(f"workspace icon catalog must be curated as {expected}, found {keys}")

packs = {}
for key in ("awtarchy", "workflow", "phases"):
    match = re.search(
        r'\{\s*key:\s*"' + re.escape(key)
        + r'".*?symbols:\s*\[([^]]+)\].*?glyphSize:\s*(\d+).*?glyphYOffset:\s*(-?\d+)',
        catalog,
        re.S,
    )
    if not match:
        raise SystemExit(f"missing symbols/glyphSize/glyphYOffset for {key}")
    symbols = re.findall(r'"([^"]*)"', match.group(1))
    if len(symbols) != 10:
        raise SystemExit(f"{key} must expose exactly 10 symbols, found {len(symbols)}")
    packs[key] = (symbols, int(match.group(2)), int(match.group(3)))

expected_workflow = ["", "", "", "", "", "", "", "", "", ""]
if packs["workflow"][0] != expected_workflow:
    raise SystemExit(f"workflow pack is not the curated role-based set: {packs['workflow'][0]}")
if len(set(packs["workflow"][0])) != 10:
    raise SystemExit("workflow pack must use ten distinct role icons")
if packs["phases"][1] < 22:
    raise SystemExit("phases glyph size must be at least 22px")
if packs["phases"][2] >= 0:
    raise SystemExit("phases must have a negative optical Y offset")
PY

for alias in \
    '"filled-dot": "workflow"' \
    '"dots": "workflow"' \
    '"diamonds": "workflow"' \
    '"squares": "workflow"' \
    '"triangles": "workflow"' \
    '"minimal": "workflow"' \
    '"spark": "workflow"'
do
    contains "$BAR_STATE" "$alias" \
        "legacy workspace style migration is missing ${alias}"
done

contains "$BAR_STATE" 'function workspaceIconPackFor(style)' \
    'BarState has no pack lookup helper'
contains "$BAR_STATE" 'function workspaceIconPixelSize()' \
    'BarState has no per-pack workspace glyph sizing helper'
contains "$BAR_STATE" 'function workspaceIconYOffset()' \
    'BarState has no per-pack optical Y-offset helper'
contains "$BAR_STATE" 'pack.symbols[value - 1]' \
    'workspace icon resolver does not select the pack symbol for each workspace'

contains "$BAR_SETTINGS" 'property var clipboardQueue: []' \
    'clipboard writes are not serialized'
contains "$BAR_SETTINGS" 'id: clipboardWriter' \
    'clipboard helper is not a managed Process'
contains "$BAR_SETTINGS" 'function runNextClipboardCopy()' \
    'clipboard queue has no runner'
contains "$BAR_SETTINGS" '["wl-copy", "--type", "text/plain", "--", next.text]' \
    'clipboard Process does not pass text safely to wl-copy'
not_contains "$BAR_SETTINGS" 'Quickshell.execDetached(["wl-copy"' \
    'clipboard still uses fire-and-forget execDetached'
contains "$BAR_SETTINGS" 'onExited: (exitCode, exitStatus) =>' \
    'clipboard Process does not inspect completion status'
contains "$BAR_SETTINGS" 'function copyWorkspacePack(styleKey, text)' \
    'Copy all still depends on passing a QML model object'
contains "$BAR_SETTINGS" 'packRow.modelData.symbols.join(" ")' \
    'Copy all does not pass the final pack text explicitly'
contains "$BAR_SETTINGS" '"✓ Copied all" : " Copy all"' \
    'Copy all control does not visibly confirm success'
contains "$BAR_SETTINGS" 'text: root.workspaceCopyFeedback' \
    'workspace heading does not expose copy feedback'
contains "$BAR_SETTINGS" 'text: root.launcherCopyFeedback' \
    'application launcher heading does not expose copy feedback'
contains "$BAR_SETTINGS" 'Layout.preferredWidth: 30' \
    'launcher copy controls are not compact enough to avoid truncation'
contains "$BAR_SETTINGS" '? "✓" : ""' \
    'launcher copy control does not show compact success feedback'
contains "$BAR_SETTINGS" 'https://www.nerdfonts.com/cheat-sheet' \
    'workspace editor does not link to the Nerd Fonts cheat sheet'
contains "$BAR_SETTINGS" 'https://symbl.cc/en/unicode/' \
    'workspace editor does not link to a Unicode symbol browser'

contains "$BAR_BUTTON" 'property int workspaceGlyphYOffset: 0' \
    'BarButton has no optical workspace glyph offset input'
contains "$BAR_BUTTON" 'anchors.verticalCenterOffset:' \
    'workspace glyph rendering does not apply an optical vertical offset'
contains "$BAR_QML" 'workspaceGlyphYOffset: BarState.workspaceIconYOffset()' \
    'workspace bar buttons do not consume the selected pack optical offset'

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

for style in workflow phases; do
    run_state set-workspace-icon-style "$style"
    jq -e --arg style "$style" '
        .bar_appearance.workspace_icon_style == $style
        and .unrelated.preserve == true
    ' "$STATE_FILE" >/dev/null || fail "state writer did not persist ${style}"
done

for removed_style in dots diamonds squares triangles minimal spark; do
    cp "$STATE_FILE" "$TMP/before-${removed_style}.json"
    if run_state set-workspace-icon-style "$removed_style" >/dev/null 2>&1; then
        fail "state writer still accepts removed ${removed_style} preset"
    fi
    cmp -s "$STATE_FILE" "$TMP/before-${removed_style}.json" \
        || fail "rejected ${removed_style} preset modified persistent state"
done

printf '%s\n' 'PASS: role-based workspace presets, optical alignment, and completion-aware clipboard actions are validated.'
