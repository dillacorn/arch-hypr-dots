import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property bool active: false
    property int textScale: 100
    property int iconScale: 100

    readonly property string floatingState: FloatingWindowsState.state
    readonly property bool operationBusy: FloatingWindowsState.busy

    Layout.fillWidth: true
    Layout.preferredHeight: content.implicitHeight + 16
    color: Theme.popupButton
    border.width: 1
    border.color: Theme.active

    function scaledText(baseSize) {
        return Math.max(8, Math.round(baseSize * textScale / 100));
    }

    function statusLabel() {
        if (floatingState === "enabled")
            return "Enabled";
        if (floatingState === "disabled")
            return "Disabled";
        if (floatingState === "unavailable")
            return "Unavailable";
        return "Checking…";
    }

    function requestToggle() {
        FloatingWindowsState.toggle();
    }

    onActiveChanged: {
        if (!active)
            return;
        FloatingWindowsState.clearFeedback();
        if (!FloatingWindowsState.available)
            Qt.callLater(() => FloatingWindowsState.refresh());
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: "Window Behavior"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(12)
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: "Floating Windows"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(8)
                }
            }

            Text {
                text: root.statusLabel()
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
            }

            SettingsButton {
                label: root.floatingState === "enabled" ? "Disable" : "Enable"
                active: root.floatingState === "enabled"
                textSize: root.scaledText(9)
                enabled: FloatingWindowsState.available && !root.operationBusy
                onClicked: root.requestToggle()
            }
        }

        Text {
            Layout.fillWidth: true
            text: FloatingWindowsState.errorMessage.length > 0
                ? FloatingWindowsState.errorMessage
                : (FloatingWindowsState.message.length > 0
                    ? FloatingWindowsState.message
                    : (root.floatingState === "enabled"
                        ? "New windows open floating by default. Existing windows keep their current state. Use SUPER+ALT+F to disable this mode or SUPER+F to tile/float the focused window."
                        : "New windows use Awtarchy's normal tiling behavior. Existing windows keep their current state. Use SUPER+ALT+F to toggle floating-spawn mode."))
            color: FloatingWindowsState.errorMessage.length > 0 ? Theme.urgent : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }
    }
}
