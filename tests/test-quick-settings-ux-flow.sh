#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QUICK_SETTINGS="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
FLYOUT_SETTINGS="$ROOT/config/quickshell/awtarchy/FlyoutSettings.qml"
BAR_SETTINGS="$ROOT/config/quickshell/awtarchy/BarSettingsSection.qml"
DISPLAY_SCALE="$ROOT/config/quickshell/awtarchy/DisplayScaleSettings.qml"
HISTORY="$ROOT/local/share/awtarchy/quickshell-managed-history.sha256"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$DISPLAY_SCALE" ]] || fail 'Display Scale is still coupled to Bar Appearance instead of its own Quick Settings control'

python3 - "$QUICK_SETTINGS" "$FLYOUT_SETTINGS" "$BAR_SETTINGS" "$DISPLAY_SCALE" <<'PY'
from pathlib import Path
import sys

quick = Path(sys.argv[1]).read_text()
flyout = Path(sys.argv[2]).read_text()
bar = Path(sys.argv[3]).read_text()
display = Path(sys.argv[4]).read_text()


def fail(message):
    raise SystemExit(f"FAIL: {message}")


def function_body(text, name):
    marker = f"function {name}("
    start = text.find(marker)
    if start < 0:
        fail(f"missing {name}()")
    brace = text.find("{", start)
    depth = 0
    for i in range(brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1:i]
    fail(f"unterminated {name}()")

for name in ("moveQuickSettingsSection", "setQuickSettingsSectionVisible"):
    if "persistQuickSettingsLayout()" not in function_body(quick, name):
        fail(f"{name} does not persist layout changes immediately")

reset_body = function_body(quick, "resetQuickSettingsLayoutDraft")
if "resetQuickSettingsLayout()" not in reset_body:
    fail("layout reset is still only a draft instead of an immediate persisted reset")

save_body = function_body(quick, "saveDisplaySettings")
if "save-quick-settings-layout" in save_body:
    fail("header Save still owns Quick Settings layout persistence")

settings_dirty_start = quick.find("readonly property bool settingsDirty:")
settings_dirty_end = quick.find("readonly property var brightnessStatus:", settings_dirty_start)
if settings_dirty_start < 0 or settings_dirty_end < 0:
    fail("could not locate settingsDirty declaration")
if "layoutDirty" in quick[settings_dirty_start:settings_dirty_end]:
    fail("instant layout changes still mark the header Save button dirty")

if "onSettingsModePanelHeightChanged:" not in quick:
    fail("settings/editor window height is not driven by the computed settings-mode height")
if "resizeForSettingsMode()" not in quick[quick.find("onSettingsModePanelHeightChanged:"):][:260]:
    fail("computed settings-mode height changes do not trigger a window resize")

bar_start = quick.find('quickSettingsSectionRow("bar")')
bar_end = quick.find('id: nightLightVibranceRow', bar_start)
if bar_start < 0 or bar_end < 0:
    fail("could not locate main Quick Settings Bar card")
if "BarSettingsSection {" not in quick[bar_start:bar_end]:
    fail("Bar Appearance has not moved into the main Quick Settings Bar card")

if "BarSettingsSection {" in flyout:
    fail("Bar Appearance is still duplicated behind the Quick Settings cog")
if "DisplayScaleSettings {" not in flyout:
    fail("Display Scale did not remain in the Quick Settings settings page")
if 'text: "Display scale"' in bar:
    fail("BarSettingsSection still owns Display Scale")
if 'text: "Display scale"' not in display:
    fail("DisplayScaleSettings does not expose the existing Display Scale control")

print("PASS: Quick Settings layout changes persist immediately, settings-mode resizing follows content, and Bar Appearance lives with the Bar card.")
PY

missing_history=0
for rel in \
    .config/quickshell/awtarchy/QuickSettings.qml \
    .config/quickshell/awtarchy/FlyoutSettings.qml \
    .config/quickshell/awtarchy/BarSettingsSection.qml \
    .config/quickshell/awtarchy/DisplayScaleSettings.qml
do
    source_file="$ROOT/config/${rel#.config/}"
    [[ -f "$source_file" ]] || continue
    digest="$(sha256sum "$source_file" | awk '{print $1}')"
    if ! grep -Fq -- "$digest"$'\t'"$rel" "$HISTORY"; then
        printf 'MISSING_HISTORY_HASH: %s\t%s\n' "$digest" "$rel" >&2
        missing_history=1
    fi
done
[[ $missing_history -eq 0 ]] || fail 'managed history is missing current Quick Settings UX stock hashes'
