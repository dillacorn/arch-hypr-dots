#!/usr/bin/env python3
from pathlib import Path
import hashlib


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}")
    target.write_text(text.replace(old, new, 1))


replace_once(
    "config/quickshell/awtarchy/QuickSettings.qml",
    """                Flickable {
                    id: contentFlick
                    Layout.row: root.bottomEdgeLayout ? 0 : 2
""",
    """                Flickable {
                    id: contentFlick
                    visible: !root.settingsOpen
                    Layout.row: root.bottomEdgeLayout ? 0 : 2
""",
)

replace_once(
    "config/quickshell/awtarchy/FlyoutSettings.qml",
    '                    text: "Copy to Displays…"\n',
    '                    text: root.surfaceLabel === "Quick Settings" ? "Copy Quick Settings…" : "Copy to Displays…"\n',
)

replace_once(
    "config/quickshell/awtarchy/BarSettingsSection.qml",
    """    property bool barTransparencyDragging: false
    property var barTransparencyDragTargets: []

    signal themePickerRequested()
""",
    """    property bool barTransparencyDragging: false
    property var barTransparencyDragTargets: []
    property bool copyOpen: false
    property var copyTargets: ({})
    property int copySelectionRevision: 0

    signal themePickerRequested()
""",
)

replace_once(
    "config/quickshell/awtarchy/BarSettingsSection.qml",
    """    function resolvedTargets() {
        if (targetKey === "all")
            return uniqueMonitorNames();
        if (targetKey === "current")
            return monitorName.length > 0 ? [monitorName] : [];
        return uniqueMonitorNames().indexOf(targetKey) >= 0 ? [targetKey] : [];
    }

    function rawBarSize(name) {
""",
    """    function resolvedTargets() {
        if (targetKey === "all")
            return uniqueMonitorNames();
        if (targetKey === "current")
            return monitorName.length > 0 ? [monitorName] : [];
        return uniqueMonitorNames().indexOf(targetKey) >= 0 ? [targetKey] : [];
    }

    function copyMonitorNames() {
        return uniqueMonitorNames().filter(name => name !== monitorName);
    }

    function copyTargetSelected(name) {
        const dependency = copySelectionRevision;
        return copyTargets[name] === true;
    }

    function selectedCopyTargets() {
        return copyMonitorNames().filter(name => copyTargetSelected(name));
    }

    function setCopyTargetSelected(name, selected) {
        const next = Object.assign({}, copyTargets);
        if (selected)
            next[name] = true;
        else
            delete next[name];
        copyTargets = next;
        copySelectionRevision++;
    }

    function allCopyTargetsSelected() {
        const names = copyMonitorNames();
        return names.length > 0 && names.every(name => copyTargetSelected(name));
    }

    function toggleAllCopyTargets() {
        const next = {};
        if (!allCopyTargetsSelected()) {
            for (const name of copyMonitorNames())
                next[name] = true;
        }
        copyTargets = next;
        copySelectionRevision++;
    }

    function resetCopySelection() {
        copyTargets = ({});
        copySelectionRevision++;
        copyOpen = false;
    }

    function copyBarSettings() {
        const targets = selectedCopyTargets();
        if (monitorName.length === 0 || targets.length === 0)
            return;
        const next = commandQueue.slice();
        next.push([managerScript, "copy-bar-settings", monitorName, ...targets]);
        commandQueue = next;
        message = "Copied bar settings to " + targets.length
            + (targets.length === 1 ? " display" : " displays");
        resetCopySelection();
        runNextCommand();
    }

    function rawBarSize(name) {
""",
)

system_stats = """            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "System stats"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                SettingsButton {
                    label: "CPU"
                    textSize: 9
                    horizontalPadding: 12
                    active: root.moduleVisibilityActive("cpu")
                    onClicked: root.toggleModuleVisibility("cpu", "CPU usage")
                }

                SettingsButton {
                    label: "Temp"
                    textSize: 9
                    horizontalPadding: 12
                    active: root.moduleVisibilityActive("temperature")
                    onClicked: root.toggleModuleVisibility("temperature", "CPU temperature")
                }

                SettingsButton {
                    label: "RAM"
                    textSize: 9
                    horizontalPadding: 12
                    active: root.moduleVisibilityActive("memory")
                    onClicked: root.toggleModuleVisibility("memory", "RAM usage")
                }

                Item { Layout.fillWidth: true }
            }
"""

copy_rows = system_stats + """

            RowLayout {
                visible: !root.copyOpen
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 26 : 0
                spacing: 5

                SettingsButton {
                    label: "Copy Bar Settings…"
                    textSize: 9
                    horizontalPadding: 12
                    available: root.copyMonitorNames().length > 0
                    onClicked: {
                        root.copyTargets = ({});
                        root.copySelectionRevision++;
                        root.copyOpen = true;
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Copies bar appearance only · display scale stays per display"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                visible: root.copyOpen
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 26 : 0
                spacing: 5

                SettingsButton {
                    label: "Back"
                    textSize: 9
                    onClicked: root.resetCopySelection()
                }

                Repeater {
                    model: root.copyMonitorNames()
                    delegate: SettingsButton {
                        required property string modelData
                        label: modelData
                        textSize: 9
                        horizontalPadding: 10
                        active: root.copyTargetSelected(modelData)
                        onClicked: root.setCopyTargetSelected(modelData,
                            !root.copyTargetSelected(modelData))
                    }
                }

                SettingsButton {
                    label: root.allCopyTargetsSelected() ? "Clear" : "All"
                    textSize: 9
                    onClicked: root.toggleAllCopyTargets()
                }

                Item { Layout.fillWidth: true }

                SettingsButton {
                    label: "Copy"
                    textSize: 9
                    available: root.selectedCopyTargets().length > 0
                    onClicked: root.copyBarSettings()
                }
            }
"""
replace_once("config/quickshell/awtarchy/BarSettingsSection.qml", system_stats, copy_rows)

replace_once(
    "config/hypr/scripts/quickshell.sh",
    "reset_mon() {\n",
    """copy_bar_settings() {
    local source="$1"
    shift
    local -a targets=("$@")
    local target targets_json tmp

    [[ -n "$source" ]] || { printf 'quickshell.sh: source monitor is required\\n' >&2; exit 2; }
    (( ${#targets[@]} > 0 )) || { printf 'quickshell.sh: at least one target monitor is required\\n' >&2; exit 2; }

    ensure_state
    jq -e --arg source "$source" '.monitors[$source] | type == "object"' "$STATE_FILE" >/dev/null \\
        || { printf 'quickshell.sh: unknown source monitor: %s\\n' "$source" >&2; exit 2; }
    for target in "${targets[@]}"; do
        jq -e --arg target "$target" '.monitors[$target] | type == "object"' "$STATE_FILE" >/dev/null \\
            || { printf 'quickshell.sh: unknown target monitor: %s\\n' "$target" >&2; exit 2; }
    done

    targets_json="$(printf '%s\\n' "${targets[@]}" | jq -Rsc 'split("\\n") | map(select(length > 0)) | unique')"
    tmp="${STATE_FILE}.tmp.$$"
    jq --arg source "$source" --argjson targets "$targets_json" '
        .monitors[$source] as $source_state
        | ($source_state | {
            position,
            bar_size,
            icon_scale,
            text_scale,
            bar_transparency,
            show_tasks,
            theme_task_icons,
            theme_tray_icons,
            show_cpu,
            show_temp,
            show_memory,
            last_horizontal,
            last_vertical
        }) as $bar_settings
        | reduce $targets[] as $target
            (.;
                if $target == $source then .
                else .monitors[$target] = (.monitors[$target] + $bar_settings)
                end)
    ' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

reset_mon() {
""",
)

replace_once(
    "config/hypr/scripts/quickshell.sh",
    "  setshowmemory <MON> <true|false>\n  reset-mon <MON>\n",
    "  setshowmemory <MON> <true|false>\n  copy-bar-settings <SOURCE_MON> <TARGET_MON...>\n  reset-mon <MON>\n",
)

replace_once(
    "config/hypr/scripts/quickshell.sh",
    '    setshowmemory-focused) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; monitor="$(focused_monitor)"; set_monitor_stat_visibility "$monitor" show_memory "$2" ;;\n    reset-mon) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; reset_mon "$2" ;;\n',
    '    setshowmemory-focused) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; monitor="$(focused_monitor)"; set_monitor_stat_visibility "$monitor" show_memory "$2" ;;\n    copy-bar-settings) [[ -n "${2:-}" && -n "${3:-}" ]] || { usage >&2; exit 2; }; copy_bar_settings "$2" "${@:3}" ;;\n    reset-mon) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; reset_mon "$2" ;;\n',
)

history = Path("local/share/awtarchy/quickshell-managed-history.sha256")
history_text = history.read_text()
for path in [
    "config/quickshell/awtarchy/QuickSettings.qml",
    "config/quickshell/awtarchy/FlyoutSettings.qml",
    "config/quickshell/awtarchy/BarSettingsSection.qml",
    "config/hypr/scripts/quickshell.sh",
]:
    digest = hashlib.sha256(Path(path).read_bytes()).hexdigest()
    managed = ".config/" + path.removeprefix("config/")
    line = f"{digest}\t{managed}\n"
    if line not in history_text:
        history_text += line
history.write_text(history_text)
