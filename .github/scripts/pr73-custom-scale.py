#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "config/hypr/scripts/quickshell_display_scale.sh"
QML = ROOT / "config/quickshell/awtarchy/BarSettingsSection.qml"
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"


def replace_exact(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


helper = HELPER.read_text()
helper = replace_exact(
    helper,
    '''valid_scale() {\n    case "${1:-}" in\n        1|1.25|1.5|2) return 0 ;;\n        *) return 1 ;;\n    esac\n}\n\nscale_ratio() {\n    case "${1:-}" in\n        1) printf '%s\\n' '1 1' ;;\n        1.25) printf '%s\\n' '5 4' ;;\n        1.5) printf '%s\\n' '3 2' ;;\n        2) printf '%s\\n' '2 1' ;;\n        *) return 1 ;;\n    esac\n}\n''',
    '''normalize_scale() {\n    local raw="${1:-}"\n\n    command -v python3 >/dev/null 2>&1 || return 1\n\n    python3 - "$raw" <<'PY'\nfrom decimal import Decimal, InvalidOperation\nimport sys\n\nraw = sys.argv[1].strip()\ntry:\n    value = Decimal(raw)\nexcept (InvalidOperation, ValueError):\n    raise SystemExit(1)\n\nif not value.is_finite() or value < Decimal("1") or value > Decimal("4"):\n    raise SystemExit(1)\n\nnormalized = format(value.normalize(), "f")\nif "." in normalized:\n    normalized = normalized.rstrip("0").rstrip(".")\nprint(normalized)\nPY\n}\n''',
    "preset-only scale validation",
)
helper = replace_exact(
    helper,
    '''scale_compatible() {\n    local width="$1"\n    local height="$2"\n    local scale="$3"\n    local numerator denominator\n\n    read -r numerator denominator < <(scale_ratio "$scale") || return 1\n    (( width > 0 && height > 0 )) || return 1\n    (( (width * denominator) % numerator == 0 )) || return 1\n    (( (height * denominator) % numerator == 0 ))\n}\n''',
    '''scale_compatible() {\n    local width="$1"\n    local height="$2"\n    local scale="$3"\n\n    command -v python3 >/dev/null 2>&1 || return 1\n\n    python3 - "$width" "$height" "$scale" <<'PY'\nfrom decimal import Decimal, InvalidOperation\nimport sys\n\ntry:\n    width = Decimal(sys.argv[1])\n    height = Decimal(sys.argv[2])\n    scale = Decimal(sys.argv[3])\nexcept (InvalidOperation, ValueError):\n    raise SystemExit(1)\n\nif width <= 0 or height <= 0 or scale <= 0:\n    raise SystemExit(1)\n\nfor pixels in (width, height):\n    logical = pixels / scale\n    if logical != logical.to_integral_value():\n        raise SystemExit(1)\nPY\n}\n''',
    "resolution compatibility validation",
)
helper = replace_exact(
    helper,
    '''    local status width height existing_errors post_errors backup\n\n    [[ -n $monitor ]] || fail 'monitor name is required'\n    valid_scale "$scale" || fail "unsupported display scale: $scale"\n    [[ -f $HYPR_LUA ]] || fail "Hyprland config is missing: $HYPR_LUA"\n''',
    '''    local status width height existing_errors post_errors backup normalized_scale\n\n    [[ -n $monitor ]] || fail 'monitor name is required'\n    if ! normalized_scale="$(normalize_scale "$scale")"; then\n        fail "unsupported display scale: $scale (expected 1.0-4.0)"\n        return 1\n    fi\n    scale="$normalized_scale"\n    [[ -f $HYPR_LUA ]] || fail "Hyprland config is missing: $HYPR_LUA"\n''',
    "set-scale normalization",
)
if "1|1.25|1.5|2)" in helper or "scale_ratio" in helper or "valid_scale" in helper:
    raise SystemExit("stale preset-only scale validation remains")
HELPER.write_text(helper)

qml = QML.read_text()
qml = replace_exact(
    qml,
    '''    property string displayScaleError: ""\n''',
    '''    property string displayScaleError: ""\n    property bool customScaleOpen: false\n    property string customScaleText: "1"\n''',
    "custom scale state",
)
qml = replace_exact(
    qml,
    '''    function displayScalePercent(value) {\n        return Math.round(Number(value) * 100) + "%";\n    }\n\n    function displayScaleValid(value) {\n        const scale = Number(value);\n        const width = Number(monitorPixelWidth);\n        const height = Number(monitorPixelHeight);\n        if (!Number.isFinite(scale) || scale <= 0 || width <= 0 || height <= 0)\n            return false;\n        const logicalWidth = width / scale;\n        const logicalHeight = height / scale;\n        return Math.abs(logicalWidth - Math.round(logicalWidth)) < 0.0001\n            && Math.abs(logicalHeight - Math.round(logicalHeight)) < 0.0001;\n    }\n''',
    '''    function displayScaleLabel(value) {\n        const scale = Number(value);\n        if (!Number.isFinite(scale))\n            return "";\n        return String(Math.round(scale * 1000) / 1000);\n    }\n\n    function displayScaleIsPreset(value) {\n        const scale = Number(value);\n        return displayScalePresets.some(preset => Math.abs(Number(preset) - scale) < 0.001);\n    }\n\n    function displayScaleValid(value) {\n        const scale = Number(value);\n        const width = Number(monitorPixelWidth);\n        const height = Number(monitorPixelHeight);\n        if (!Number.isFinite(scale) || scale < 1 || scale > 4 || width <= 0 || height <= 0)\n            return false;\n        const logicalWidth = width / scale;\n        const logicalHeight = height / scale;\n        return Math.abs(logicalWidth - Math.round(logicalWidth)) < 0.0001\n            && Math.abs(logicalHeight - Math.round(logicalHeight)) < 0.0001;\n    }\n\n    function toggleCustomDisplayScale() {\n        customScaleOpen = !customScaleOpen;\n        if (customScaleOpen)\n            customScaleText = displayScaleLabel(displayScale);\n    }\n\n    function applyCustomDisplayScale() {\n        const scale = Number(String(customScaleText || "").trim());\n        if (!Number.isFinite(scale) || scale < 1 || scale > 4) {\n            message = "Custom display scale must be between 1 and 4";\n            return;\n        }\n        if (!displayScaleValid(scale)) {\n            message = "Display scale " + displayScaleLabel(scale) + " is invalid for "\n                + monitorPixelWidth + "×" + monitorPixelHeight;\n            return;\n        }\n        setDisplayScale(scale);\n        customScaleOpen = false;\n    }\n''',
    "display scale UI helpers",
)
qml = replace_exact(
    qml,
    '''        message = "Display scale " + displayScalePercent(scale) + " · " + monitorName;\n''',
    '''        message = "Display scale " + displayScaleLabel(scale) + " · " + monitorName;\n''',
    "display scale request message",
)
qml = replace_exact(
    qml,
    '''    onMonitorNameChanged: refreshDisplayScale()\n''',
    '''    onMonitorNameChanged: {\n        customScaleOpen = false;\n        refreshDisplayScale();\n    }\n''',
    "monitor change custom editor reset",
)
qml = replace_exact(
    qml,
    '''                root.message = "Display scale " + root.displayScalePercent(root.displayScale)\n                    + " · " + root.monitorName;\n''',
    '''                root.message = "Display scale " + root.displayScaleLabel(root.displayScale)\n                    + " · " + root.monitorName;\n''',
    "display scale completion message",
)
old_row = '''            RowLayout {\n                Layout.fillWidth: true\n                Layout.preferredHeight: 26\n                spacing: 5\n\n                Text {\n                    Layout.preferredWidth: 78\n                    text: "Display scale"\n                    color: Theme.foreground\n                    font.family: Theme.fontFamily\n                    font.pixelSize: 10\n                }\n\n                Repeater {\n                    model: root.displayScalePresets\n                    delegate: SettingsButton {\n                        required property var modelData\n\n                        label: root.displayScalePercent(Number(modelData))\n                        textSize: 9\n                        horizontalPadding: 10\n                        active: Math.abs(root.displayScale - Number(modelData)) < 0.001\n                        available: !scaleWriter.running\n                            && root.displayScaleValid(Number(modelData))\n                        onClicked: root.setDisplayScale(Number(modelData))\n                    }\n                }\n\n                Item { Layout.fillWidth: true }\n\n                Text {\n                    text: root.monitorName.length > 0 ? "Focused · " + root.monitorName : "Focused display"\n                    color: Theme.muted\n                    font.family: Theme.fontFamily\n                    font.pixelSize: 9\n                    elide: Text.ElideMiddle\n                    Layout.maximumWidth: 120\n                }\n            }\n'''
new_row = '''            RowLayout {\n                Layout.fillWidth: true\n                Layout.preferredHeight: 26\n                spacing: 5\n\n                Text {\n                    Layout.preferredWidth: 78\n                    text: "Display scale"\n                    color: Theme.foreground\n                    font.family: Theme.fontFamily\n                    font.pixelSize: 10\n                }\n\n                Repeater {\n                    model: root.displayScalePresets\n                    delegate: SettingsButton {\n                        required property var modelData\n\n                        label: root.displayScaleLabel(Number(modelData))\n                        textSize: 9\n                        horizontalPadding: 10\n                        active: Math.abs(root.displayScale - Number(modelData)) < 0.001\n                        available: !scaleWriter.running\n                            && root.displayScaleValid(Number(modelData))\n                        onClicked: root.setDisplayScale(Number(modelData))\n                    }\n                }\n\n                SettingsButton {\n                    label: "Custom"\n                    textSize: 9\n                    horizontalPadding: 10\n                    active: root.customScaleOpen || !root.displayScaleIsPreset(root.displayScale)\n                    available: !scaleWriter.running && root.monitorPixelWidth > 0\n                        && root.monitorPixelHeight > 0\n                    onClicked: root.toggleCustomDisplayScale()\n                }\n\n                Item { Layout.fillWidth: true }\n\n                Text {\n                    text: root.monitorName.length > 0 ? "Focused · " + root.monitorName : "Focused display"\n                    color: Theme.muted\n                    font.family: Theme.fontFamily\n                    font.pixelSize: 9\n                    elide: Text.ElideMiddle\n                    Layout.maximumWidth: 120\n                }\n            }\n\n            RowLayout {\n                visible: root.customScaleOpen\n                Layout.fillWidth: true\n                Layout.preferredHeight: visible ? 26 : 0\n                spacing: 5\n\n                Text {\n                    Layout.preferredWidth: 78\n                    text: "Custom scale"\n                    color: Theme.foreground\n                    font.family: Theme.fontFamily\n                    font.pixelSize: 10\n                }\n\n                Rectangle {\n                    Layout.preferredWidth: 82\n                    Layout.preferredHeight: 24\n                    color: Theme.popupBackground\n                    border.width: 1\n                    border.color: customScaleInput.activeFocus ? Theme.focus : Theme.muted\n                    radius: 0\n\n                    TextInput {\n                        id: customScaleInput\n                        anchors.fill: parent\n                        anchors.margins: 5\n                        text: root.customScaleText\n                        color: Theme.foreground\n                        selectionColor: Theme.focus\n                        selectedTextColor: Theme.foreground\n                        font.family: Theme.fontFamily\n                        font.pixelSize: 10\n                        horizontalAlignment: Text.AlignHCenter\n                        verticalAlignment: Text.AlignVCenter\n                        selectByMouse: true\n                        inputMethodHints: Qt.ImhFormattedNumbersOnly\n                        onTextEdited: root.customScaleText = text\n                        Keys.onReturnPressed: root.applyCustomDisplayScale()\n                    }\n                }\n\n                SettingsButton {\n                    label: "Apply"\n                    textSize: 9\n                    available: !scaleWriter.running && root.monitorName.length > 0\n                    onClicked: root.applyCustomDisplayScale()\n                }\n\n                Text {\n                    Layout.fillWidth: true\n                    text: {\n                        const scale = Number(root.customScaleText);\n                        if (root.displayScaleValid(scale))\n                            return Math.round(root.monitorPixelWidth / scale) + "×"\n                                + Math.round(root.monitorPixelHeight / scale) + " logical";\n                        return "1–4 · whole logical pixels only";\n                    }\n                    color: Theme.muted\n                    font.family: Theme.fontFamily\n                    font.pixelSize: 9\n                    elide: Text.ElideRight\n                }\n            }\n'''
qml = replace_exact(qml, old_row, new_row, "display scale row")
if "displayScalePercent" in qml:
    raise SystemExit("stale percentage display-scale helper remains")
QML.write_text(qml)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

history = HISTORY.read_text().rstrip("\n") + "\n"
marker = "# 2026-08-27 custom focused-display scale input."
if marker in history:
    raise SystemExit("managed-history custom scale section already exists")
history += (\
    f"\n{marker}\n"\
    f"{sha256(HELPER)}\t.config/hypr/scripts/quickshell_display_scale.sh\n"\
    f"{sha256(QML)}\t.config/quickshell/awtarchy/BarSettingsSection.qml\n"\
)
HISTORY.write_text(history)

print("Applied PR #73 custom display scale refinement.")
print(f"helper sha256={sha256(HELPER)}")
print(f"qml sha256={sha256(QML)}")
