#!/usr/bin/env python3
from pathlib import Path
import hashlib

QUICK = Path("config/quickshell/awtarchy/QuickSettings.qml")
FLYOUT = Path("config/quickshell/awtarchy/FlyoutSettings.qml")
BAR = Path("config/quickshell/awtarchy/BarSettingsSection.qml")
DISPLAY = Path("config/quickshell/awtarchy/DisplayScaleSettings.qml")
HISTORY = Path("local/share/awtarchy/quickshell-managed-history.sha256")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def matching_brace(text: str, brace: int) -> int:
    depth = 0
    quote = None
    escaped = False
    for i in range(brace, len(text)):
        ch = text[i]
        if quote is not None:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = None
            continue
        if ch in ('"', "'"):
            quote = ch
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
    raise SystemExit("unterminated QML/JS block")


def remove_function(text: str, name: str) -> str:
    marker = f"    function {name}("
    start = text.find(marker)
    if start < 0:
        raise SystemExit(f"missing function {name}")
    brace = text.find("{", start)
    end = matching_brace(text, brace) + 1
    while end < len(text) and text[end] == "\n":
        end += 1
    return text[:start] + text[end:]


def remove_handler(text: str, marker: str) -> str:
    start = text.find(marker)
    if start < 0:
        raise SystemExit(f"missing handler {marker.strip()}")
    brace = text.find("{", start)
    end = matching_brace(text, brace) + 1
    while end < len(text) and text[end] == "\n":
        end += 1
    return text[:start] + text[end:]


def remove_enclosing_block(text: str, needle: str, opener: str) -> str:
    pos = text.find(needle)
    if pos < 0:
        raise SystemExit(f"missing block marker {needle}")
    start = text.rfind(opener, 0, pos)
    if start < 0:
        raise SystemExit(f"missing opener {opener!r} for {needle}")
    brace = text.find("{", start)
    end = matching_brace(text, brace) + 1
    while end < len(text) and text[end] == "\n":
        end += 1
    return text[:start] + text[end:]


# QuickSettings: layout customization is its own immediately persisted state.
quick = QUICK.read_text()
quick = replace_once(
    quick,
    '''    readonly property bool layoutDirty: layoutSignature(layoutOrderDraft, layoutHiddenDraft)
        !== layoutSignature(savedLayout.order, savedLayout.hidden)
    readonly property bool settingsDirty: savedView.width !== livePanelWidth
        || savedView.height !== livePanelHeight
        || savedView.textScale !== effectiveTextScale
        || savedView.iconScale !== effectiveIconScale
        || savedView.captureAllowed !== captureAllowed
        || layoutDirty
''',
    '''    readonly property bool settingsDirty: savedView.width !== livePanelWidth
        || savedView.height !== livePanelHeight
        || savedView.textScale !== effectiveTextScale
        || savedView.iconScale !== effectiveIconScale
        || savedView.captureAllowed !== captureAllowed
''',
    "settingsDirty")
quick = replace_once(
    quick,
    '''    onBottomEdgeLayoutChanged: Qt.callLater(() => alignContentToBar())
    onLayoutEditorOpenChanged: {
        if (settingsOpen)
            Qt.callLater(() => resizeForSettingsMode());
    }
''',
    '''    onBottomEdgeLayoutChanged: Qt.callLater(() => alignContentToBar())
    onSettingsModePanelHeightChanged: {
        if (settingsOpen)
            Qt.callLater(() => resizeForSettingsMode());
    }
''',
    "settings-mode height handler")

layout_helpers_anchor = '''    function quickSettingsSectionVisible(sectionId) {
        return layoutHiddenDraft.indexOf(sectionId) < 0;
    }
'''
layout_helpers = '''    function persistQuickSettingsLayout() {
        if (activeMonitorName.length === 0)
            return;
        queueStateCommand([
            "save-quick-settings-layout", activeMonitorName,
            JSON.stringify(layoutOrderDraft), JSON.stringify(layoutHiddenDraft)
        ]);
        savedLayout = ({
            order: layoutOrderDraft.slice(),
            hidden: layoutHiddenDraft.slice()
        });
        settingsMessage = "Quick Settings layout updated";
    }

    function resetQuickSettingsLayout() {
        if (activeMonitorName.length === 0)
            return;
        queueStateCommand(["reset-quick-settings-layout", activeMonitorName]);
        savedLayout = ({
            order: layoutOrderDraft.slice(),
            hidden: layoutHiddenDraft.slice()
        });
        settingsMessage = "Stock Quick Settings layout restored";
    }

'''
quick = replace_once(quick, layout_helpers_anchor, layout_helpers + layout_helpers_anchor,
                     "layout persistence helpers")
quick = replace_once(
    quick,
    '''        layoutOrderDraft = next;
        Qt.callLater(() => alignContentToBar());
    }

    function setQuickSettingsSectionVisible''',
    '''        layoutOrderDraft = next;
        persistQuickSettingsLayout();
        Qt.callLater(() => alignContentToBar());
    }

    function setQuickSettingsSectionVisible''',
    "instant reorder persistence")
quick = replace_once(
    quick,
    '''        layoutHiddenDraft = next;
        Qt.callLater(() => alignContentToBar());
    }

    function resetQuickSettingsLayoutDraft''',
    '''        layoutHiddenDraft = next;
        persistQuickSettingsLayout();
        Qt.callLater(() => alignContentToBar());
    }

    function resetQuickSettingsLayoutDraft''',
    "instant visibility persistence")
quick = replace_once(
    quick,
    '''    function resetQuickSettingsLayoutDraft() {
        layoutOrderDraft = BarState.defaultQuickSettingsSectionOrder.slice();
        layoutHiddenDraft = [];
        settingsMessage = "Stock Quick Settings layout restored in draft";
        Qt.callLater(() => alignContentToBar());
    }
''',
    '''    function resetQuickSettingsLayoutDraft() {
        layoutOrderDraft = BarState.defaultQuickSettingsSectionOrder.slice();
        layoutHiddenDraft = [];
        resetQuickSettingsLayout();
        Qt.callLater(() => alignContentToBar());
    }
''',
    "instant layout reset")
quick = replace_once(
    quick,
    '''        queueStateCommand([
            "save-quick-settings-layout", activeMonitorName,
            JSON.stringify(layoutOrderDraft), JSON.stringify(layoutHiddenDraft)
        ]);
        panelWidthOverride = livePanelWidth;
''',
    '''        panelWidthOverride = livePanelWidth;
''',
    "remove layout from header save")

bar_icon_anchor = '''                                BarIconSettings {
                                    Layout.fillWidth: true
                                    visible: root.barIconEditorOpen
                                }
'''
bar_appearance = '''

                                BarSettingsSection {
                                    Layout.fillWidth: true
                                    active: quickSettingsWindow.visible
                                        && root.quickSettingsSectionVisible("bar")
                                    monitorName: root.activeMonitorName
                                    monitorNames: [root.activeMonitorName]
                                        .concat(root.otherMonitorNames())
                                    onThemePickerRequested: root.openThemeMenu()
                                }
'''
quick = replace_once(quick, bar_icon_anchor, bar_icon_anchor + bar_appearance,
                     "embed Bar Appearance")
QUICK.write_text(quick)


# BarSettingsSection: remove the monitor Display Scale concern entirely.
bar = BAR.read_text()
for line in [
    '    property real displayScale: 1\n',
    '    property int monitorPixelWidth: 0\n',
    '    property int monitorPixelHeight: 0\n',
    '    property real pendingDisplayScale: 1\n',
    '    property string displayScaleError: ""\n',
    '    property bool customScaleOpen: false\n',
    '    property string customScaleText: "1"\n',
    '    readonly property string displayScaleScript: configHome + "/hypr/scripts/quickshell_display_scale.sh"\n',
    '    readonly property var displayScalePresets: [1, 1.25, 1.5, 2]\n',
]:
    if line not in bar:
        raise SystemExit(f"missing BarSettings scale line: {line.strip()}")
    bar = bar.replace(line, "", 1)

for name in [
    "displayScaleLabel",
    "displayScaleIsPreset",
    "displayScaleValid",
    "toggleCustomDisplayScale",
    "applyCustomDisplayScale",
    "refreshDisplayScale",
    "setDisplayScale",
]:
    bar = remove_function(bar, name)
bar = remove_handler(bar, "    onMonitorNameChanged: {")
bar = remove_handler(bar, "    onActiveChanged: {")
bar = remove_enclosing_block(bar, "id: scaleStatusRunner", "    Process {")
bar = remove_enclosing_block(bar, "id: scaleWriter", "    Process {")
bar = remove_enclosing_block(bar, 'text: "Display scale"', "            RowLayout {")
bar = remove_enclosing_block(bar, "visible: root.customScaleOpen", "            RowLayout {")
BAR.write_text(bar)


# Display Scale stays behind Quick Settings settings, but is no longer a bar setting.
display = r'''pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string monitorName: ""
    property bool active: false
    property string message: ""
    property real displayScale: 1
    property int monitorPixelWidth: 0
    property int monitorPixelHeight: 0
    property real pendingDisplayScale: 1
    property string displayScaleError: ""
    property bool customScaleOpen: false
    property string customScaleText: "1"

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string displayScaleScript: configHome
        + "/hypr/scripts/quickshell_display_scale.sh"
    readonly property var displayScalePresets: [1, 1.25, 1.5, 2]

    implicitHeight: active ? controls.implicitHeight + 12 : 0

    function displayScaleLabel(value) {
        const scale = Number(value);
        if (!Number.isFinite(scale))
            return "";
        return String(Math.round(scale * 1000) / 1000);
    }

    function displayScaleIsPreset(value) {
        const scale = Number(value);
        return displayScalePresets.some(preset => Math.abs(Number(preset) - scale) < 0.001);
    }

    function displayScaleValid(value) {
        const scale = Number(value);
        const width = Number(monitorPixelWidth);
        const height = Number(monitorPixelHeight);
        if (!Number.isFinite(scale) || scale < 1 || scale > 4 || width <= 0 || height <= 0)
            return false;
        const logicalWidth = width / scale;
        const logicalHeight = height / scale;
        return Math.abs(logicalWidth - Math.round(logicalWidth)) < 0.0001
            && Math.abs(logicalHeight - Math.round(logicalHeight)) < 0.0001;
    }

    function toggleCustomDisplayScale() {
        customScaleOpen = !customScaleOpen;
        if (customScaleOpen)
            customScaleText = displayScaleLabel(displayScale);
    }

    function applyCustomDisplayScale() {
        const scale = Number(String(customScaleText || "").trim());
        if (!Number.isFinite(scale) || scale < 1 || scale > 4) {
            message = "Custom display scale must be between 1 and 4";
            return;
        }
        if (!displayScaleValid(scale)) {
            message = "Display scale " + displayScaleLabel(scale) + " is invalid for "
                + monitorPixelWidth + "×" + monitorPixelHeight;
            return;
        }
        setDisplayScale(scale);
        customScaleOpen = false;
    }

    function refreshDisplayScale() {
        if (!active || monitorName.length === 0 || scaleStatusRunner.running || scaleWriter.running)
            return;
        scaleStatusRunner.exec(["bash", root.displayScaleScript, "status", root.monitorName]);
    }

    function setDisplayScale(value) {
        const scale = Number(value);
        if (monitorName.length === 0 || scaleWriter.running || !displayScaleValid(scale)
                || Math.abs(displayScale - scale) < 0.001)
            return;
        pendingDisplayScale = scale;
        displayScaleError = "";
        message = "Display scale " + displayScaleLabel(scale) + " · " + monitorName;
        scaleWriter.exec(["bash", root.displayScaleScript, "set", root.monitorName, String(scale)]);
    }

    onMonitorNameChanged: {
        customScaleOpen = false;
        message = "";
        refreshDisplayScale();
    }
    onActiveChanged: {
        if (active)
            refreshDisplayScale();
    }

    Process {
        id: scaleStatusRunner
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const status = JSON.parse(text.trim());
                    root.displayScale = Number(status.scale || 1);
                    root.monitorPixelWidth = Number(status.width || 0);
                    root.monitorPixelHeight = Number(status.height || 0);
                } catch (error) {
                    root.monitorPixelWidth = 0;
                    root.monitorPixelHeight = 0;
                }
            }
        }
    }

    Process {
        id: scaleWriter
        stderr: StdioCollector {
            onStreamFinished: root.displayScaleError = text.trim()
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.displayScale = root.pendingDisplayScale;
                root.message = "Display scale " + root.displayScaleLabel(root.displayScale)
                    + " · " + root.monitorName;
                root.refreshDisplayScale();
                return;
            }
            const errorText = root.displayScaleError.length > 0
                ? root.displayScaleError.split("\n")[0]
                : "Display scale change failed";
            root.message = errorText;
            root.refreshDisplayScale();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.active
        border.width: 1
        border.color: Theme.focus

        ColumnLayout {
            id: controls
            anchors.fill: parent
            anchors.margins: 6
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "Display scale"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Repeater {
                    model: root.displayScalePresets
                    delegate: SettingsButton {
                        required property var modelData
                        label: root.displayScaleLabel(Number(modelData))
                        textSize: 9
                        horizontalPadding: 10
                        active: Math.abs(root.displayScale - Number(modelData)) < 0.001
                        available: !scaleWriter.running
                            && root.displayScaleValid(Number(modelData))
                        onClicked: root.setDisplayScale(Number(modelData))
                    }
                }

                SettingsButton {
                    label: "Custom"
                    textSize: 9
                    horizontalPadding: 10
                    active: root.customScaleOpen || !root.displayScaleIsPreset(root.displayScale)
                    available: !scaleWriter.running && root.monitorPixelWidth > 0
                        && root.monitorPixelHeight > 0
                    onClicked: root.toggleCustomDisplayScale()
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.monitorName.length > 0 ? "Focused · " + root.monitorName : "Focused display"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 120
                }
            }

            RowLayout {
                visible: root.customScaleOpen
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 26 : 0
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "Custom scale"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Rectangle {
                    Layout.preferredWidth: 82
                    Layout.preferredHeight: 24
                    color: Theme.popupBackground
                    border.width: 1
                    border.color: customScaleInput.activeFocus ? Theme.focus : Theme.muted
                    radius: 0

                    TextInput {
                        id: customScaleInput
                        anchors.fill: parent
                        anchors.margins: 5
                        text: root.customScaleText
                        color: Theme.foreground
                        selectionColor: Theme.focus
                        selectedTextColor: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        selectByMouse: true
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        onTextEdited: root.customScaleText = text
                        Keys.onReturnPressed: root.applyCustomDisplayScale()
                    }
                }

                SettingsButton {
                    label: "Apply"
                    textSize: 9
                    available: !scaleWriter.running && root.monitorName.length > 0
                    onClicked: root.applyCustomDisplayScale()
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        const scale = Number(root.customScaleText);
                        if (root.displayScaleValid(scale))
                            return Math.round(root.monitorPixelWidth / scale) + "×"
                                + Math.round(root.monitorPixelHeight / scale) + " logical";
                        return "1–4 · whole logical pixels only";
                    }
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.message.length > 0
                Layout.preferredHeight: visible ? 18 : 0
                text: root.message
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 9
                elide: Text.ElideRight
            }
        }
    }
}
'''
DISPLAY.write_text(display)


# FlyoutSettings: keep Quick Settings window/display controls behind the cog only.
flyout = FLYOUT.read_text()
flyout = replace_once(
    flyout,
    '''    implicitHeight: copyOpen ? 104
        : 139 + (surfaceLabel === "Quick Settings" ? barSection.implicitHeight + 37 : 0)
''',
    '''    implicitHeight: copyOpen ? 104
        : 139 + (surfaceLabel === "Quick Settings" ? displayScaleSection.implicitHeight + 37 : 0)
''',
    "FlyoutSettings height")
old_bar = '''        BarSettingsSection {
            id: barSection
            Layout.fillWidth: true
            visible: !root.copyOpen && root.surfaceLabel === "Quick Settings"
            active: visible
            monitorName: root.monitorName
            monitorNames: [root.monitorName].concat(root.otherMonitorNames || [])
            onThemePickerRequested: root.themePickerRequested()
        }
'''
new_scale = '''        DisplayScaleSettings {
            id: displayScaleSection
            Layout.fillWidth: true
            visible: !root.copyOpen && root.surfaceLabel === "Quick Settings"
            active: visible
            monitorName: root.monitorName
        }
'''
flyout = replace_once(flyout, old_bar, new_scale, "FlyoutSettings Bar/Display Scale split")
FLYOUT.write_text(flyout)


# Managed-history recognition for every managed stock file changed/added here.
history = HISTORY.read_text()
for source, managed in [
    (QUICK, ".config/quickshell/awtarchy/QuickSettings.qml"),
    (FLYOUT, ".config/quickshell/awtarchy/FlyoutSettings.qml"),
    (BAR, ".config/quickshell/awtarchy/BarSettingsSection.qml"),
    (DISPLAY, ".config/quickshell/awtarchy/DisplayScaleSettings.qml"),
]:
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    entry = f"{digest}\t{managed}\n"
    if entry not in history:
        history += entry
HISTORY.write_text(history)
