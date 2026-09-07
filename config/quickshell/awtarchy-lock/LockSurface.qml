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
                                readonly property bool isFilledGlyph: glyph === "█"
                                    || glyph === "▄" || glyph === "▀" || glyph === "▐"
                                readonly property int halfWidth: Math.floor(root.wordmarkCellWidth / 2)
                                readonly property int halfHeight: Math.floor(root.wordmarkCellHeight / 2)
                                readonly property real finalGlyphX: glyph === "▐" ? halfWidth : 0
                                readonly property real finalGlyphY: glyph === "▄" ? halfHeight : 0
                                readonly property real finalGlyphWidth: glyph === "▐"
                                    ? root.wordmarkCellWidth - halfWidth : root.wordmarkCellWidth
                                readonly property real finalGlyphHeight: glyph === "▄"
                                    ? root.wordmarkCellHeight - halfHeight
                                    : glyph === "▀" ? halfHeight : root.wordmarkCellHeight
                                readonly property real particleSize: Math.max(3,
                                    Math.floor(7 * root.uiScale))

                                // These values intentionally have no reactive dependencies: each
                                // surface creation gets a new randomized assembly path per cell.
                                readonly property real startAngle: Math.random() * Math.PI * 2
                                readonly property real startDistance: (140 + Math.random() * 360)
                                    * root.uiScale
                                readonly property real startX: Math.cos(startAngle) * startDistance
                                readonly property real startY: Math.sin(startAngle) * startDistance
                                readonly property real curveX: (Math.random() - 0.5) * 260 * root.uiScale
                                readonly property real curveY: (Math.random() - 0.5) * 180 * root.uiScale
                                readonly property int formationDelay: Math.floor(Math.random() * 651)
                                readonly property int formationDuration: 3000
                                    + Math.floor(Math.random() * 551)
                                property real formationProgress: 0

                                x: columnIndex * root.wordmarkCellWidth
                                    + (1 - formationProgress) * startX
                                    + Math.sin(Math.PI * wordmarkCell.formationProgress) * curveX
                                y: (1 - formationProgress) * startY
                                    + Math.sin(Math.PI * wordmarkCell.formationProgress) * curveY
                                width: root.wordmarkCellWidth
                                height: root.wordmarkCellHeight
                                visible: isFilledGlyph

                                Rectangle {
                                    x: (1 - wordmarkCell.formationProgress)
                                            * ((root.wordmarkCellWidth - wordmarkCell.particleSize) / 2)
                                        + wordmarkCell.formationProgress * wordmarkCell.finalGlyphX
                                    y: (1 - wordmarkCell.formationProgress)
                                            * ((root.wordmarkCellHeight - wordmarkCell.particleSize) / 2)
                                        + wordmarkCell.formationProgress * wordmarkCell.finalGlyphY
                                    width: (1 - wordmarkCell.formationProgress) * wordmarkCell.particleSize
                                        + wordmarkCell.formationProgress * wordmarkCell.finalGlyphWidth
                                    height: (1 - wordmarkCell.formationProgress) * wordmarkCell.particleSize
                                        + wordmarkCell.formationProgress * wordmarkCell.finalGlyphHeight
                                    color: root.theme.lockAccent
                                    opacity: 0.35 + 0.65 * wordmarkCell.formationProgress
                                    antialiasing: false
                                }

                                SequentialAnimation on formationProgress {
                                    running: wordmarkCell.isFilledGlyph
                                        && root.entered && !root.unlocking

                                    PauseAnimation {
                                        duration: wordmarkCell.formationDelay
                                    }

                                    NumberAnimation {
                                        from: 0
                                        to: 1
                                        duration: wordmarkCell.formationDuration
                                        easing.type: Easing.OutCubic
                                    }
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
                    color: root.theme.lockAccent
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
                            color: root.theme.lockAccent
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
