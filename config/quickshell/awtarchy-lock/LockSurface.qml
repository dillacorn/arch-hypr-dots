import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland

WlSessionLockSurface {
    id: root

    required property var auth
    required property var theme
    required property bool unlocking
    required property string animationPreference
    required property int randomFormationMode

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
    readonly property int formationMode: animationPreference === "swarm" ? 0
        : animationPreference === "edges" ? 1
        : animationPreference === "center" ? 2
        : animationPreference === "split" ? 3
        : randomFormationMode

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
                                readonly property real wordmarkWidth: root.wordmarkColumns
                                    * root.wordmarkCellWidth
                                readonly property real wordmarkHeight: root.wordmarkRows.length
                                    * root.wordmarkCellHeight
                                readonly property real finalCellX: columnIndex * root.wordmarkCellWidth
                                readonly property real finalCellY: wordmarkRow.rowIndex
                                    * root.wordmarkCellHeight

                                // These values intentionally have no reactive dependencies: each
                                // surface creation gets a new animation family and fresh paths.
                                readonly property real randomA: Math.random()
                                readonly property real randomB: Math.random()
                                readonly property real randomC: Math.random()
                                readonly property real randomD: Math.random()
                                readonly property real randomE: Math.random()
                                readonly property real startAngle: randomA * Math.PI * 2
                                readonly property real startDistance: (150 + randomB * 330)
                                    * root.uiScale
                                readonly property int edgeSide: Math.floor(randomC * 4)
                                readonly property real edgeMargin: (100 + randomD * 180)
                                    * root.uiScale
                                readonly property real jitterX: (randomD - 0.5) * 180 * root.uiScale
                                readonly property real jitterY: (randomE - 0.5) * 130 * root.uiScale

                                readonly property real swarmStartX: Math.cos(startAngle) * startDistance
                                readonly property real swarmStartY: Math.sin(startAngle) * startDistance
                                readonly property real edgeStartX: edgeSide === 0
                                    ? -finalCellX - edgeMargin
                                    : edgeSide === 1
                                        ? wordmarkWidth - finalCellX + edgeMargin
                                        : jitterX
                                readonly property real edgeStartY: edgeSide === 2
                                    ? -finalCellY - edgeMargin
                                    : edgeSide === 3
                                        ? wordmarkHeight - finalCellY + edgeMargin
                                        : jitterY
                                readonly property real centerStartX: wordmarkWidth / 2
                                    - finalCellX + jitterX * 0.35
                                readonly property real centerStartY: wordmarkHeight / 2
                                    - finalCellY + jitterY * 0.35
                                readonly property real splitStartX: columnIndex < root.wordmarkColumns / 2
                                    ? -finalCellX - edgeMargin
                                    : wordmarkWidth - finalCellX + edgeMargin
                                readonly property real splitStartY: jitterY
                                    + (wordmarkRow.rowIndex % 2 === 0 ? -1 : 1)
                                        * (35 + randomC * 70) * root.uiScale

                                readonly property real startX: root.formationMode === 0
                                    ? swarmStartX
                                    : root.formationMode === 1
                                        ? edgeStartX
                                        : root.formationMode === 2
                                            ? centerStartX
                                            : splitStartX
                                readonly property real startY: root.formationMode === 0
                                    ? swarmStartY
                                    : root.formationMode === 1
                                        ? edgeStartY
                                        : root.formationMode === 2
                                            ? centerStartY
                                            : splitStartY
                                readonly property real curveX: (randomC - 0.5)
                                    * (root.formationMode === 3 ? 150 : 240) * root.uiScale
                                readonly property real curveY: (randomD - 0.5)
                                    * (root.formationMode === 2 ? 100 : 170) * root.uiScale
                                readonly property int formationDelay: Math.floor(Math.random() * 451)
                                readonly property int formationDuration: 2300
                                    + Math.floor(Math.random() * 451)
                                property real formationProgress:
                                    root.animationPreference === "off" ? 1 : 0

                                x: finalCellX
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
                                    opacity: wordmarkCell.formationProgress <= 0 ? 0
                                        : 0.35 + 0.65 * wordmarkCell.formationProgress
                                    antialiasing: false
                                }

                                SequentialAnimation on formationProgress {
                                    running: wordmarkCell.isFilledGlyph
                                        && root.entered && !root.unlocking
                                        && root.animationPreference !== "off"

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
