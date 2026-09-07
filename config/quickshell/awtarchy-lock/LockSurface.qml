import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland

WlSessionLockSurface {
    id: root

    required property var auth
    required property var theme
    required property bool unlocking

    color: "#000000"

    readonly property real uiScale: Math.max(0.72, Math.min(1.35,
        Math.min(width / 1920, height / 1080)))
    readonly property int maskedCount: Math.min(password.text.length, 10)
    readonly property real maskSpread: maskedCount === 0 ? 0
        : Math.round((24 + maskedCount * 14) * uiScale)
    readonly property var wordmarkRows: [
        " ▄▄▄      ██     █ ▄▄▄█████ ▄▄▄      ██▀███  ▄████▄  ██  ██ ██   ██",
        " ████▄     █  █  █ █  ██  █ ████▄    ██   ██ ██▀ ▀█  ██  ██  ██  ██",
        " ██  ▀█▄  ██  █  ██   ██    ██  ▀█▄  ██  ▄█  ██    ▄ ██▀▀██   ██ ██",
        " ██▄▄▄▄██ ██  █  ██   ██    ██▄▄▄▄██ ██▀▀█▄  ██▄ ▄██ ██  ██    ▐██",
        "███    ██  ███████    ██    ██    ██ ██   ██  ████▀  ██  ██    ██",
        "             ███                                              ██",
        "                                                              ██"
    ]
    readonly property int wordmarkColumns: 67
    readonly property int wordmarkCellWidth: Math.max(8, Math.floor(18 * uiScale))
    readonly property int wordmarkCellHeight: Math.max(12, Math.floor(24 * uiScale))

    property bool entered: false

    function submitPassword() {
        if ((auth.busy && !auth.responseRequired) || password.text.length === 0)
            return;

        const response = password.text;
        if (auth.submit(response))
            password.text = "";
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

    Item {
        id: visualLayer
        anchors.fill: parent
        opacity: root.unlocking ? 0 : root.entered ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.unlocking ? 160 : 220
                easing.type: Easing.OutCubic
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(root.width * 0.94, 1260 * root.uiScale)
            spacing: Math.round(34 * root.uiScale)

            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: root.wordmarkColumns * root.wordmarkCellWidth
                Layout.preferredHeight: root.wordmarkRows.length * root.wordmarkCellHeight

                Repeater {
                    model: root.wordmarkRows.length

                    delegate: Item {
                        id: wordmarkRow
                        readonly property int rowIndex: index
                        readonly property string rowText: root.wordmarkRows[rowIndex]

                        x: 0
                        y: rowIndex * root.wordmarkCellHeight
                        width: root.wordmarkColumns * root.wordmarkCellWidth
                        height: root.wordmarkCellHeight

                        Repeater {
                            model: wordmarkRow.rowText.length

                            delegate: Item {
                                id: wordmarkCell
                                readonly property int columnIndex: index
                                property string glyph: wordmarkRow.rowText.charAt(columnIndex)
                                readonly property int halfWidth: Math.floor(root.wordmarkCellWidth / 2)
                                readonly property int halfHeight: Math.floor(root.wordmarkCellHeight / 2)

                                x: columnIndex * root.wordmarkCellWidth
                                y: 0
                                width: root.wordmarkCellWidth
                                height: root.wordmarkCellHeight

                                Rectangle {
                                    x: wordmarkCell.glyph === "▐" ? wordmarkCell.halfWidth : 0
                                    y: wordmarkCell.glyph === "▄" ? wordmarkCell.halfHeight : 0
                                    width: wordmarkCell.glyph === "▐"
                                        ? root.wordmarkCellWidth - wordmarkCell.halfWidth
                                        : root.wordmarkCellWidth
                                    height: wordmarkCell.glyph === "▄"
                                        ? root.wordmarkCellHeight - wordmarkCell.halfHeight
                                        : wordmarkCell.glyph === "▀"
                                            ? wordmarkCell.halfHeight
                                            : root.wordmarkCellHeight
                                    visible: wordmarkCell.glyph === "█"
                                        || wordmarkCell.glyph === "▄"
                                        || wordmarkCell.glyph === "▀"
                                        || wordmarkCell.glyph === "▐"
                                    color: root.theme.foreground
                                    antialiasing: false
                                }
                            }
                        }
                    }
                }
            }

            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.round(320 * root.uiScale)
                Layout.preferredHeight: Math.round(42 * root.uiScale)

                Rectangle {
                    anchors.centerIn: parent
                    width: root.maskSpread
                    height: Math.round(14 * root.uiScale)
                    color: root.theme.accent
                    opacity: password.text.length > 0 ? 0.09 : 0
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

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: Math.round(250 * root.uiScale)
                    height: root.auth.statusIsError ? 2 : 1
                    color: root.auth.statusIsError ? root.theme.error
                        : password.activeFocus ? root.theme.accent : root.theme.muted
                    opacity: root.auth.statusIsError || password.activeFocus ? 0.85 : 0.45
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

                    onTextChanged: {
                        if (text.length > 0 && root.auth.statusIsError)
                            root.auth.clearStatus();
                    }

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
        root.entered = true;
        Qt.callLater(() => password.forceActiveFocus());
    }
}
