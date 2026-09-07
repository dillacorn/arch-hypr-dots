import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

WlSessionLockSurface {
    id: root

    required property var auth
    required property var theme

    color: "#000000"

    readonly property real uiScale: Math.max(0.72, Math.min(1.35,
        Math.min(width / 1920, height / 1080)))
    readonly property int maskedCount: Math.min(password.text.length, 10)
    readonly property real maskSpread: maskedCount === 0 ? 0
        : Math.round((24 + maskedCount * 14) * uiScale)

    property string timeText: ""
    property string dateText: ""

    function refreshClock() {
        const now = new Date();
        timeText = Qt.formatDateTime(now, "HH:mm");
        dateText = Qt.formatDateTime(now, "dddd, MMMM d");
    }

    function submitPassword() {
        if ((auth.busy && !auth.responseRequired) || password.text.length === 0)
            return;

        const response = password.text;
        if (auth.submit(response))
            password.text = "";
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshClock()
    }

    PinchHandler {
        target: null
    }

    WheelHandler {
        target: null
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onClicked: password.forceActiveFocus()
        onWheel: wheel => { wheel.accepted = true; }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(root.width * 0.78, 560 * root.uiScale)
        spacing: Math.round(12 * root.uiScale)

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "── AWTARCHY ──"
            color: root.theme.foreground
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(13 * root.uiScale)
            font.letterSpacing: 1.2
            horizontalAlignment: Text.AlignHCenter
        }

        Item {
            Layout.preferredHeight: Math.round(8 * root.uiScale)
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.timeText
            color: root.theme.foreground
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(76 * root.uiScale)
            font.weight: Font.Light
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.dateText
            color: root.theme.muted
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(15 * root.uiScale)
        }

        Item {
            Layout.preferredHeight: Math.round(18 * root.uiScale)
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Quickshell.env("USER") || ""
            color: root.theme.foreground
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(14 * root.uiScale)
            font.weight: Font.Medium
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "PASSWORD"
            color: root.theme.muted
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(9 * root.uiScale)
            font.letterSpacing: 1.4
        }

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.round(290 * root.uiScale)
            Layout.preferredHeight: Math.round(34 * root.uiScale)

            Rectangle {
                anchors.centerIn: parent
                width: root.maskSpread
                height: Math.round(14 * root.uiScale)
                color: root.theme.accent
                opacity: password.text.length > 0 ? 0.10 : 0
            }

            Row {
                anchors.centerIn: parent
                spacing: Math.round(7 * root.uiScale)

                Repeater {
                    model: root.maskedCount

                    Rectangle {
                        width: Math.round(7 * root.uiScale)
                        height: Math.round(10 * root.uiScale)
                        color: root.theme.foreground
                        opacity: 0.82
                    }
                }
            }

            TextInput {
                id: password
                anchors.fill: parent

                color: "transparent"
                selectionColor: "transparent"
                selectedTextColor: "transparent"
                cursorVisible: false
                font.family: root.theme.fontFamily
                font.pixelSize: Math.round(18 * root.uiScale)
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData
                enabled: !auth.busy || auth.responseRequired
                activeFocusOnTab: true

                Keys.onReturnPressed: event => {
                    root.submitPassword();
                    event.accepted = true;
                }

                Keys.onEnterPressed: event => {
                    root.submitPassword();
                    event.accepted = true;
                }

                Keys.onEscapePressed: event => {
                    password.text = "";
                    auth.clearStatus();
                    event.accepted = true;
                }
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.round(290 * root.uiScale)
            Layout.preferredHeight: password.activeFocus ? 2 : 1
            color: root.auth.statusIsError ? root.theme.error
                : password.activeFocus ? root.theme.accent : root.theme.muted
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.round(430 * root.uiScale)
            Layout.preferredHeight: Math.round(22 * root.uiScale)
            text: root.auth.statusText
            color: root.auth.statusIsError ? root.theme.error : root.theme.muted
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(11 * root.uiScale)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    Connections {
        target: root.auth

        function onAuthenticationFailed() {
            password.text = "";
            Qt.callLater(() => password.forceActiveFocus());
        }

        function onBusyChanged() {
            if (!root.auth.busy)
                Qt.callLater(() => password.forceActiveFocus());
        }

        function onResponseRequiredChanged() {
            if (root.auth.responseRequired)
                Qt.callLater(() => password.forceActiveFocus());
        }
    }

    Component.onCompleted: {
        root.refreshClock();
        Qt.callLater(() => password.forceActiveFocus());
    }
}
