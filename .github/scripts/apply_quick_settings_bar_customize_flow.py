#!/usr/bin/env python3
from pathlib import Path
import hashlib

QUICK = Path("config/quickshell/awtarchy/QuickSettings.qml")
FLYOUT = Path("config/quickshell/awtarchy/FlyoutSettings.qml")
BAR_SETTINGS = Path("config/quickshell/awtarchy/BarSettingsSection.qml")
POSITION = Path("config/hypr/scripts/quickshell_flyout_position.sh")
ICON_TEST = Path("tests/test-bar-icon-customization.sh")
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
    raise SystemExit("unterminated block")


def block_from_start(text: str, start: int) -> tuple[int, int]:
    brace = text.find("{", start)
    if brace < 0:
        raise SystemExit("missing block brace")
    end = matching_brace(text, brace) + 1
    while end < len(text) and text[end] == "\n":
        end += 1
    return start, end


# Quick Settings: compact settings resize and one unified Bar customization expansion.
quick = QUICK.read_text()
quick = replace_once(
    quick,
    '    property bool barIconEditorOpen: false\n',
    '    property bool barCustomizeOpen: false\n',
    "bar customize state")
quick = replace_once(
    quick,
    '    readonly property int minimumPanelHeight: Math.min(460, maximumPanelHeight)\n',
    '    readonly property int minimumPanelHeight: Math.min(460, maximumPanelHeight)\n'
    '    readonly property int minimumSettingsPanelHeight: Math.min(180, maximumPanelHeight)\n',
    "compact settings minimum")
quick = replace_once(
    quick,
    '''    readonly property int settingsModePanelHeight: clampHeight(38
        + (layoutEditorOpen ? layoutEditor.implicitHeight : settingsPanel.implicitHeight) + 12)
''',
    '''    readonly property int settingsModePanelHeight: clampSettingsHeight(38
        + (layoutEditorOpen ? layoutEditor.implicitHeight : settingsPanel.implicitHeight) + 12)
''',
    "settings height clamp")
quick = replace_once(
    quick,
    '''    function clampHeight(value) {
        return Math.max(minimumPanelHeight, Math.min(maximumPanelHeight, Math.round(value)));
    }
''',
    '''    function clampHeight(value) {
        return Math.max(minimumPanelHeight, Math.min(maximumPanelHeight, Math.round(value)));
    }

    function clampSettingsHeight(value) {
        return Math.max(minimumSettingsPanelHeight,
            Math.min(maximumPanelHeight, Math.round(value)));
    }
''',
    "compact settings clamp function")
quick = replace_once(
    quick,
    '''                positionScript, "quick-settings", activeMonitorName, placement, "resize",
                String(panelWidthOverride),
                String(settingsOpen ? settingsModePanelHeight : panelHeightOverride)
''',
    '''                positionScript, "quick-settings", activeMonitorName, placement,
                settingsOpen ? "resize-compact" : "resize",
                String(panelWidthOverride),
                String(settingsOpen ? settingsModePanelHeight : panelHeightOverride)
''',
    "applyWindowSize compact action")
quick = replace_once(
    quick,
    '''            positionScript, "quick-settings", activeMonitorName, placement, "resize",
            String(configuredPanelWidth),
            String(settingsOpen ? settingsModePanelHeight : configuredPanelHeight)
''',
    '''            positionScript, "quick-settings", activeMonitorName, placement,
            settingsOpen ? "resize-compact" : "resize",
            String(configuredPanelWidth),
            String(settingsOpen ? settingsModePanelHeight : configuredPanelHeight)
''',
    "settings resize compact action")

# Replace the Bar card controls from its header through the embedded appearance component.
bar_title = 'text: "Bar · " + root.activeMonitorName'
bar_title_pos = quick.find(bar_title)
if bar_title_pos < 0:
    raise SystemExit("missing Bar card title")
bar_region_start = quick.rfind('                                RowLayout {\n', 0, bar_title_pos)
if bar_region_start < 0:
    raise SystemExit("missing Bar card header start")
appearance_pos = quick.find('                                BarSettingsSection {', bar_title_pos)
if appearance_pos < 0:
    raise SystemExit("missing embedded BarSettingsSection")
_, bar_region_end = block_from_start(quick, appearance_pos)

bar_region = '''                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 5

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Bar · " + root.activeMonitorName
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(12)
                                        font.bold: true
                                    }

                                    SettingsButton {
                                        label: "Themes"
                                        textSize: root.scaledText(9)
                                        onClicked: root.openThemeMenu()
                                    }

                                    SettingsButton {
                                        label: "Customize…"
                                        active: root.barCustomizeOpen
                                        textSize: root.scaledText(9)
                                        onClicked: {
                                            root.barCustomizeOpen = !root.barCustomizeOpen;
                                            if (!root.barCustomizeOpen)
                                                barAppearanceSettings.resetTransientState();
                                            if (root.bottomEdgeLayout)
                                                Qt.callLater(() => root.alignContentToBar());
                                        }
                                    }

                                    SettingsButton {
                                        label: root.barStatus.enabled ? "Visible" : "Hidden"
                                        active: Boolean(root.barStatus.enabled)
                                        textSize: root.scaledText(9)
                                        onClicked: root.queueAction([
                                            "bar-enabled", root.activeMonitorName,
                                            root.barStatus.enabled ? "false" : "true"
                                        ], "Updating bar visibility…")
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Flow {
                                        spacing: 5
                                        Repeater {
                                            model: ["top", "bottom", "left", "right"]
                                            SettingsButton {
                                                required property var modelData
                                                label: String(modelData)
                                                active: String(root.barStatus.position) === String(modelData)
                                                textSize: root.scaledText(9)
                                                onClicked: root.queueAction([
                                                    "bar-position", root.activeMonitorName, String(modelData)
                                                ], "Moving bar to " + String(modelData) + "…")
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Tip: drag the bar with SUPER+Mouse1 or ALT+Mouse1."
                                        color: Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(8)
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: root.barCustomizeOpen
                                    spacing: 6

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Icons"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(10)
                                        font.bold: true
                                    }

                                    BarIconSettings {
                                        Layout.fillWidth: true
                                        visible: root.barCustomizeOpen
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Appearance"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(10)
                                        font.bold: true
                                    }

                                    BarSettingsSection {
                                        id: barAppearanceSettings
                                        Layout.fillWidth: true
                                        active: quickSettingsWindow.visible
                                            && root.quickSettingsSectionVisible("bar")
                                            && root.barCustomizeOpen
                                        monitorName: root.activeMonitorName
                                        monitorNames: [root.activeMonitorName]
                                            .concat(root.otherMonitorNames())
                                    }
                                }
'''
quick = quick[:bar_region_start] + bar_region + quick[bar_region_end:]

# Reset all visual-only settings state when switching/opening/closing surfaces.
quick = replace_once(
    quick,
    '''    function toggleSettings() {
        settingsOpen = !settingsOpen;
        layoutEditorOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        Qt.callLater(() => root.resizeForSettingsMode());
    }
''',
    '''    function toggleSettings() {
        settingsOpen = !settingsOpen;
        layoutEditorOpen = false;
        if (settingsOpen) {
            barCustomizeOpen = false;
            barAppearanceSettings.resetTransientState();
        }
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        Qt.callLater(() => root.resizeForSettingsMode());
    }
''',
    "toggle settings transient reset")
quick = replace_once(
    quick,
    '''        settingsOpen = false;
        layoutEditorOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        schedulerEditorOpen = false;
''',
    '''        settingsOpen = false;
        layoutEditorOpen = false;
        barCustomizeOpen = false;
        settingsPanel.resetCopySelection();
        barAppearanceSettings.resetTransientState();
        settingsMessage = "";
        schedulerEditorOpen = false;
''',
    "open transient reset")
quick = replace_once(
    quick,
    '''        settingsOpen = false;
        layoutEditorOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        schedulerEditorOpen = false;
''',
    '''        settingsOpen = false;
        layoutEditorOpen = false;
        barCustomizeOpen = false;
        settingsPanel.resetCopySelection();
        barAppearanceSettings.resetTransientState();
        settingsMessage = "";
        schedulerEditorOpen = false;
''',
    "close transient reset")
QUICK.write_text(quick)


# Bar appearance component: it is now an embedded advanced section, not a second Bar card.
bar = BAR_SETTINGS.read_text()
bar = replace_once(bar, '    signal themePickerRequested()\n\n', '', "remove nested Themes signal")
bar = replace_once(
    bar,
    '''    function resetCopySelection() {
        copyTargets = ({});
        copySelectionRevision++;
        copyOpen = false;
    }
''',
    '''    function resetCopySelection() {
        copyTargets = ({});
        copySelectionRevision++;
        copyOpen = false;
    }

    function resetTransientState() {
        resetCopySelection();
        targetKey = "current";
        message = "";
        cancelTransparencyDrag();
    }
''',
    "Bar appearance transient reset")

header_marker = '                    text: "Bar Appearance"'
header_pos = bar.find(header_marker)
if header_pos < 0:
    raise SystemExit("missing old Bar Appearance header")
header_start = bar.rfind('            Item {\n', 0, header_pos)
if header_start < 0:
    raise SystemExit("missing Bar Appearance header Item")
_, header_end = block_from_start(bar, header_start)
new_header = '''            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 26

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    SettingsButton {
                        label: "‹"
                        textSize: 11
                        onClicked: root.cycleTarget(-1)
                    }

                    Text {
                        width: 240
                        height: 24
                        text: "Apply to: " + root.targetLabel()
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideMiddle
                    }

                    SettingsButton {
                        label: "›"
                        textSize: 11
                        onClicked: root.cycleTarget(1)
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    SettingsButton {
                        label: "Reset"
                        textSize: 9
                        onClicked: root.resetAppearance()
                    }
                }
            }
'''
bar = bar[:header_start] + new_header + bar[header_end:]
BAR_SETTINGS.write_text(bar)


# Flyout settings: Quick Settings copy selection expands inline while other flyouts retain existing behavior.
fly = FLYOUT.read_text()
fly = replace_once(
    fly,
    '''    readonly property bool managedConnectivityCapture: surfaceLabel === "Network"
        || surfaceLabel === "Bluetooth"
''',
    '''    readonly property bool inlineCopy: surfaceLabel === "Quick Settings"
    readonly property bool managedConnectivityCapture: surfaceLabel === "Network"
        || surfaceLabel === "Bluetooth"
''',
    "inline copy property")
fly = replace_once(
    fly,
    '''    implicitHeight: copyOpen ? 104
        : 139 + (surfaceLabel === "Quick Settings" ? displayScaleSection.implicitHeight + 37 : 0)
''',
    '''    implicitHeight: inlineCopy
        ? 139 + displayScaleSection.implicitHeight + 37 + (copyOpen ? 31 : 0)
        : (copyOpen ? 104 : 139)
''',
    "inline copy height")
fly = fly.replace(
    '            visible: !root.copyOpen && root.surfaceLabel === "Quick Settings"\n',
    '            visible: root.surfaceLabel === "Quick Settings"\n')
fly = fly.replace(
    '            visible: !root.copyOpen\n',
    '            visible: root.inlineCopy || !root.copyOpen\n')
fly = fly.replace(
    '            visible: root.copyOpen\n',
    '            visible: root.copyOpen && !root.inlineCopy\n')

old_copy_click = '''                    onClicked: {
                        root.copyTargets = ({});
                        root.copySelectionRevision++;
                        root.copyOpen = true;
                    }
'''
new_copy_click = '''                    onClicked: {
                        if (root.inlineCopy && root.copyOpen) {
                            root.resetCopySelection();
                            return;
                        }
                        root.copyTargets = ({});
                        root.copySelectionRevision++;
                        root.copyOpen = true;
                    }
'''
fly = replace_once(fly, old_copy_click, new_copy_click, "inline copy toggle")

insert_marker = '''        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 6
            visible: root.copyOpen && !root.inlineCopy

            Rectangle {
                Layout.preferredWidth: 62
'''
if insert_marker not in fly:
    raise SystemExit("missing generic copy Back row insertion point")
inline_row = '''        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 28 : 0
            spacing: 5
            visible: root.copyOpen && root.inlineCopy

            Text {
                text: "Copy to:"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }

            Repeater {
                model: root.otherMonitorNames
                delegate: SettingsButton {
                    required property string modelData
                    label: modelData
                    textSize: 9
                    horizontalPadding: 10
                    active: root.targetSelected(modelData)
                    onClicked: root.setTargetSelected(modelData,
                        !root.targetSelected(modelData))
                }
            }

            SettingsButton {
                label: root.allTargetsSelected() ? "Clear" : "All"
                textSize: 9
                available: root.otherMonitorNames.length > 0
                onClicked: root.toggleAllTargets()
            }

            Item { Layout.fillWidth: true }

            SettingsButton {
                label: "Back"
                textSize: 9
                onClicked: root.resetCopySelection()
            }

            SettingsButton {
                label: "Copy"
                textSize: 9
                available: root.selectedTargetNames().length > 0
                onClicked: {
                    const targets = root.selectedTargetNames();
                    root.copyRequested(targets);
                    root.resetCopySelection();
                }
            }
        }

'''
fly = fly.replace(insert_marker, inline_row + insert_marker, 1)
FLYOUT.write_text(fly)


# Positioning: settings-mode resize may go below the normal Quick Settings 460px minimum.
pos = POSITION.read_text()
pos = replace_once(
    pos,
    '''case "$action" in
    spawn|resize|clamp) ;;
''',
    '''case "$action" in
    spawn|resize|resize-compact|clamp) ;;
''',
    "compact action validation")
pos = replace_once(
    pos,
    '''esac

command -v hyprctl >/dev/null 2>&1 || exit 127
''',
    '''esac

if [[ "$surface" == quick-settings && "$action" == resize-compact ]]; then
    min_h=180
fi

command -v hyprctl >/dev/null 2>&1 || exit 127
''',
    "compact quick settings minimum")
pos = replace_once(
    pos,
    '''    resize)
        [[ "$requested_w" =~ ^[0-9]+$ && "$requested_h" =~ ^[0-9]+$ ]] || {
''',
    '''    resize|resize-compact)
        [[ "$requested_w" =~ ^[0-9]+$ && "$requested_h" =~ ^[0-9]+$ ]] || {
''',
    "compact resize implementation")
POSITION.write_text(pos)


# Existing icon customization regression follows the renamed unified expansion.
icon_test = ICON_TEST.read_text()
icon_test = icon_test.replace(
    'property bool barIconEditorOpen: false',
    'property bool barCustomizeOpen: false')
icon_test = icon_test.replace(
    'label: "Customize Icons…"',
    'label: "Customize…"')
icon_test = icon_test.replace(
    'visible: root.barIconEditorOpen',
    'visible: root.barCustomizeOpen')
icon_test = icon_test.replace(
    'transient Bar icon editor expansion state',
    'transient Bar customization expansion state')
icon_test = icon_test.replace(
    'Bar section does not expose the icon customization editor',
    'Bar section does not expose the unified customization editor')
ICON_TEST.write_text(icon_test)


# Append current managed stock hashes so updater policy recognizes this testing state.
history = HISTORY.read_text()
for path, managed in [
    (QUICK, '.config/quickshell/awtarchy/QuickSettings.qml'),
    (FLYOUT, '.config/quickshell/awtarchy/FlyoutSettings.qml'),
    (BAR_SETTINGS, '.config/quickshell/awtarchy/BarSettingsSection.qml'),
    (POSITION, '.config/hypr/scripts/quickshell_flyout_position.sh'),
]:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    line = f"{digest}\t{managed}\n"
    if line not in history:
        history += line
HISTORY.write_text(history)
