import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

WlSessionLockSurface {
    id: root

    required property var auth
    required property var theme

    color: "#000000"

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string logoPath: configHome + "/fastfetch/ascii/awtarchy.txt"
    readonly property real uiScale: Math.max(0.72, Math.min(1.35,
        Math.min(width / 1920, height / 1080)))
    readonly property int maskedCount: Math.min(password.text.length, 10)
    readonly property real maskSpread: password.text.length === 0 ? 0
        : Math.min(250 * uiScale,
            (28 + maskedCount * 16 + Math.min(password.text.length, 18) * 3) * uiScale)

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

    FileView {
        id: logoFile
        path: root.logoPath
        blockLoading: true
        printErrors: false
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
        id: content
        anchors.centerIn: parent
        width: Math.min(root.width * 0.78, 620 * root.uiScale)
        spacing: Math.round(12 * root.uiScale)

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: {
                const raw = logoFile.text();
                return raw && raw.length > 0 ? raw.replace(/\n$/, "") : "AWTARCHY";
            }
            color: root.theme.foreground
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(15 * root.uiScale)
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
        }

        Item {
            Layout.preferredHeight: Math.round(12 * root.uiScale)
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.timeText
            color: root.theme.foreground
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(78 * root.uiScale)
            font.weight: Font.Light
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.dateText
            color: root.theme.muted
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(16 * root.uiScale)
        }

        Item {
            Layout.preferredHeight: Math.round(20 * root.uiScale)
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Quickshell.env("USER") || ""
            color: root.theme.foreground
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(15 * root.uiScale)
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
            Layout.preferredHeight: Math.round(36 * root.uiScale)

            Rectangle {
                anchors.centerIn: parent
                width: root.maskSpread
                height: Math.round(14 * root.uiScale)
                color: root.theme.accent
                opacity: password.text.length > 0 ? 0.08 : 0
            }

            Repeater {
                model: 3

                Rectangle {
                    required property int index
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    y: Math.round((index - 1) * 3 * root.uiScale)
                    width: Math.max(0, root.maskSpread - index * 8 * root.uiScale)
                    height: Math.round((2 + index) * root.uiScale)
                    color: root.theme.accent
                    opacity: password.text.length > 0 ? 0.12 - index * 0.025 : 0
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: Math.round(7 * root.uiScale)

                Repeater {
                    model: root.maskedCount

                    Rectangle {
                        required property int index
                        width: Math.round(7 * root.uiScale)
                        height: Math.round((9 + (index % 3)) * root.uiScale)
                        color: root.theme.foreground
                        opacity: 0.78 - (index % 4) * 0.05
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
