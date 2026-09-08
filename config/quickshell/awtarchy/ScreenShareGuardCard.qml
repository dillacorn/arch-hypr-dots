import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    property bool active: false
    property int textScale: 100
    property int iconScale: 100
    property bool optionalExpanded: false
    property bool busy: false
    property string actionMessage: ""
    property string actionError: ""
    property var guardData: ({ targets: ({}) })

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string helper: configHome + "/hypr/scripts/screenshare_guard.sh"
    readonly property var protectedTargetIds: [
        "security",
        "mullvad-browser",
        "localsend",
        "telegram",
        "matrix",
        "discord",
        "teams",
        "messages",
        "notifications"
    ]
    readonly property var optionalTargetIds: [
        "obs",
        "steam",
        "rustdesk",
        "files",
        "wallpicker",
        "virt-manager",
        "alacritty",
        "mpv",
        "ags",
        "logout-dialog",
        "waybar"
    ]

    Layout.fillWidth: true
    Layout.preferredHeight: content.implicitHeight + 16
    color: Theme.popupButton
    border.width: 1
    border.color: Theme.active

    function scaledText(baseSize) {
        return Math.max(8, Math.round(baseSize * textScale / 100));
    }

    function scaledIcon(baseSize) {
        return Math.max(9, Math.round(baseSize * iconScale / 100));
    }

    function targetById(targetId) {
        const targets = guardData && guardData.targets ? guardData.targets : ({});
        return targets[targetId] || ({
            id: targetId,
            label: targetId,
            default_protected: false,
            desired_protected: false,
            effective_protected: null,
            locked: false,
            session_override: null,
            in_sync: false
        });
    }

    function targetModel(ids) {
        return ids.map(targetId => targetById(targetId));
    }

    function stateLabel(target) {
        const desired = Boolean(target.desired_protected);
        const effectiveKnown = typeof target.effective_protected === "boolean";
        const effective = effectiveKnown ? Boolean(target.effective_protected) : desired;
        if (effectiveKnown && effective !== desired)
            return "Applying…";

        let suffix = " · Default";
        if (Boolean(target.locked))
            suffix = " · Locked";
        else if (typeof target.session_override === "boolean")
            suffix = " · Session";
        else if (!effectiveKnown)
            suffix = " · Pending";
        return (effective ? "Protected" : "Capture allowed") + suffix;
    }

    function refresh() {
        if (!active || statusReader.running || actionRunner.running)
            return;
        statusReader.exec([helper, "status-json"]);
    }

    function runAction(args, message) {
        if (busy || actionRunner.running)
            return;
        busy = true;
        actionError = "";
        actionMessage = message;
        actionRunner.exec([helper, ...args]);
    }

    function toggleTarget(targetId) {
        const target = targetById(targetId);
        const next = Boolean(target.desired_protected) ? "allowed" : "protected";
        runAction(["set", targetId, next],
            next === "protected" ? "Protecting " + target.label + "…"
                : "Allowing capture for " + target.label + "…");
    }

    function toggleLock(targetId) {
        const target = targetById(targetId);
        runAction([Boolean(target.locked) ? "unlock" : "lock", targetId],
            Boolean(target.locked) ? "Using session-only state for " + target.label + "…"
                : "Remembering " + target.label + "…");
    }

    function restoreDefaults() {
        runAction(["reset"], "Restoring Awtarchy Screen Share Guard defaults…");
    }

    onActiveChanged: {
        if (active)
            Qt.callLater(() => refresh());
    }

    Process {
        id: statusReader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    root.guardData = parsed && parsed.targets ? parsed : ({ targets: ({}) });
                    root.actionError = "";
                } catch (error) {
                    root.actionError = "Screen Share Guard status unavailable";
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = text.trim();
                if (errorText.length > 0)
                    root.actionError = errorText.split("\n")[0];
            }
        }
    }

    Process {
        id: actionRunner
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = text.trim();
                if (errorText.length > 0)
                    root.actionError = errorText.split("\n")[0];
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.busy = false;
            if (exitCode === 0) {
                root.actionMessage = "Updated";
                Qt.callLater(() => root.refresh());
            } else if (root.actionError.length === 0) {
                root.actionError = "Screen Share Guard update failed";
            }
        }
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.active && !root.busy
        onTriggered: root.refresh()
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "Screen Share Guard"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(12)
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                text: root.busy ? "Applying…" : "Privacy"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Block sensitive windows from screenshots and screen sharing. Unlocked changes last for this session; lock a row to remember it."
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }

        Repeater {
            model: root.targetModel(root.protectedTargetIds)

            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 6

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: String(parent.parent.modelData.label || parent.parent.modelData.id)
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: root.scaledText(9)
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.stateLabel(parent.parent.modelData)
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: root.scaledText(7)
                        elide: Text.ElideRight
                    }
                }

                SettingsButton {
                    label: Boolean(parent.modelData.desired_protected) ? "Allow capture" : "Protect"
                    active: Boolean(parent.modelData.desired_protected)
                    available: !root.busy
                    textSize: root.scaledText(8)
                    horizontalPadding: 10
                    onClicked: root.toggleTarget(String(parent.modelData.id))
                }

                SettingsButton {
                    label: Boolean(parent.modelData.locked) ? "" : ""
                    active: Boolean(parent.modelData.locked)
                    available: !root.busy
                    textSize: root.scaledIcon(10)
                    horizontalPadding: 8
                    onClicked: root.toggleLock(String(parent.modelData.id))
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.active
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: "Optional protections"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(9)
                font.bold: true
            }

            SettingsButton {
                label: root.optionalExpanded ? "Hide" : "Show 11"
                active: root.optionalExpanded
                textSize: root.scaledText(8)
                onClicked: root.optionalExpanded = !root.optionalExpanded
            }
        }

        Repeater {
            model: root.optionalExpanded ? root.targetModel(root.optionalTargetIds) : []

            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 6

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: String(parent.parent.modelData.label || parent.parent.modelData.id)
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: root.scaledText(9)
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.stateLabel(parent.parent.modelData)
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: root.scaledText(7)
                        elide: Text.ElideRight
                    }
                }

                SettingsButton {
                    label: Boolean(parent.modelData.desired_protected) ? "Allow capture" : "Protect"
                    active: Boolean(parent.modelData.desired_protected)
                    available: !root.busy
                    textSize: root.scaledText(8)
                    horizontalPadding: 10
                    onClicked: root.toggleTarget(String(parent.modelData.id))
                }

                SettingsButton {
                    label: Boolean(parent.modelData.locked) ? "" : ""
                    active: Boolean(parent.modelData.locked)
                    available: !root.busy
                    textSize: root.scaledIcon(10)
                    horizontalPadding: 8
                    onClicked: root.toggleLock(String(parent.modelData.id))
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: root.actionError.length > 0 ? root.actionError : root.actionMessage
                visible: text.length > 0
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(7)
                elide: Text.ElideRight
            }

            SettingsButton {
                label: "Restore Awtarchy Defaults"
                available: !root.busy
                textSize: root.scaledText(8)
                onClicked: root.restoreDefaults()
            }
        }
    }
}
