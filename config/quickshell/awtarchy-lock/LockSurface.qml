import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

WlSessionLockSurface {
    id: root

    required property var auth
    required property var theme
    required property bool unlocking
    required property string animationPreference
    required property int randomFormationMode
    required property bool audioReactive
    required property real audioLow
    required property real audioMid
    required property real audioHigh
    required property real audioOverall
    required property bool mouseInteractive
    required property bool showTime
    required property bool showDate
    required property bool showUsername
    required property bool showWeather
    required property string weatherText

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
    readonly property real audioLevel: root.audioOverall
    readonly property real audioSilenceThreshold: 0.01
    readonly property bool pointerEffectsEnabled: root.mouseInteractive && root.pointerActive
    readonly property bool audioEffectsEnabled: root.audioReactive && root.audioLevel > root.audioSilenceThreshold
    readonly property int ghostTrailLength: 6
    readonly property int pointerUpdateIntervalMs: 16
    readonly property int cursorFadeDelayMs: 180
    readonly property int cursorFadeDurationMs: 320
    readonly property real pointerInfluenceRadius: 72 * root.uiScale
    readonly property real pointerDisplacementCap: 24 * root.uiScale
    readonly property real audioDisplacementCap: 6 * root.uiScale
    readonly property real pointerMovementThreshold: 3 * root.uiScale
    readonly property bool metadataVisible: root.showTime || root.showDate || root.showUsername
        || (root.showWeather && root.weatherText.length > 0)
    readonly property string usernameText: root.showUsername ? Quickshell.env("USER") : ""

    property bool entered: false
    property bool pointerActive: false
    property var wordmarkCells: ({})
    property real ghostHeadX: -100
    property real ghostHeadY: -100
    property var ghostTrail: [
        ({ x: -100, y: -100 }), ({ x: -100, y: -100 }),
        ({ x: -100, y: -100 }), ({ x: -100, y: -100 }),
        ({ x: -100, y: -100 }), ({ x: -100, y: -100 })
    ]
    property real ghostOpacity: 0
    property double lastPointerSampleTime: 0
    property double lastPhysicsUpdateTime: 0
    property real lastPointerX: -1
    property real lastPointerY: -1
    property real audioPhase: 0
    property string timeText: ""
    property string dateText: ""

    function registerWordmarkCell(row, column, cell) {
        wordmarkCells[String(row) + ":" + String(column)] = cell;
    }

    function updateClockText() {
        const now = new Date();
        timeText = Qt.formatTime(now, Locale.ShortFormat);
        dateText = Qt.formatDate(now, Locale.LongFormat);
    }

    function pushGhostSample(x, y) {
        const next = [({ x: x, y: y })];
        for (let i = 0; i < ghostTrailLength - 1; ++i)
            next.push(ghostTrail[i] || ({ x: x, y: y }));
        ghostTrail = next;
        ghostHeadX = x;
        ghostHeadY = y;
        ghostFade.stop();
        ghostOpacity = 1;
        cursorFadeDelay.restart();
    }

    function applyPointerImpulse(x, y, speed) {
        if (!pointerEffectsEnabled)
            return;

        const local = wordmarkItem.mapFromItem(pointerArea, x, y);
        const radius = pointerInfluenceRadius;
        if (local.x < -radius || local.y < -radius
                || local.x > wordmarkItem.width + radius
                || local.y > wordmarkItem.height + radius)
            return;

        const minColumn = Math.max(0,
            Math.floor((local.x - radius) / wordmarkCellWidth));
        const maxColumn = Math.min(wordmarkColumns - 1,
            Math.floor((local.x + radius) / wordmarkCellWidth));
        const minRow = Math.max(0,
            Math.floor((local.y - radius) / wordmarkCellHeight));
        const maxRow = Math.min(wordmarkRows.length - 1,
            Math.floor((local.y + radius) / wordmarkCellHeight));

        for (let row = minRow; row <= maxRow; ++row) {
            for (let column = minColumn; column <= maxColumn; ++column) {
                const cell = wordmarkCells[String(row) + ":" + String(column)];
                if (cell)
                    cell.applyPointerImpulse(local.x, local.y, speed);
            }
        }
    }

    function handlePointerMotion(x, y) {
        if (!root.mouseInteractive)
            return;

        root.pointerActive = true;
        const now = Date.now();
        const hasPrevious = lastPointerX >= 0 && lastPointerY >= 0
            && lastPointerSampleTime > 0;
        const dx = hasPrevious ? x - lastPointerX : 0;
        const dy = hasPrevious ? y - lastPointerY : 0;
        const distance = Math.sqrt(dx * dx + dy * dy);
        const elapsed = hasPrevious ? Math.max(1, now - lastPointerSampleTime) : 1;
        const speed = hasPrevious ? distance * 1000 / elapsed : 0;
        const ghostDx = x - ghostHeadX;
        const ghostDy = y - ghostHeadY;
        const ghostDistance = Math.sqrt(ghostDx * ghostDx + ghostDy * ghostDy);

        if (!hasPrevious || ghostOpacity <= 0 || ghostDistance >= pointerMovementThreshold)
            pushGhostSample(x, y);

        if (!hasPrevious || now - lastPhysicsUpdateTime >= pointerUpdateIntervalMs) {
            applyPointerImpulse(x, y, speed);
            lastPhysicsUpdateTime = now;
        }

        lastPointerX = x;
        lastPointerY = y;
        lastPointerSampleTime = now;
    }

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
        id: pointerArea
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        cursorShape: Qt.BlankCursor
        onPositionChanged: mouse => root.handlePointerMotion(mouse.x, mouse.y)
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
                id: wordmarkItem
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
                                property real pointerOffsetX: 0
                                property real pointerOffsetY: 0
                                readonly property real normalizedCenterX: wordmarkWidth > 0
                                    ? (finalCellX + root.wordmarkCellWidth / 2) / wordmarkWidth - 0.5 : 0
                                readonly property real normalizedCenterY: wordmarkHeight > 0
                                    ? (finalCellY + root.wordmarkCellHeight / 2) / wordmarkHeight - 0.5 : 0
                                readonly property real edgeWeight: Math.min(1,
                                    Math.sqrt(normalizedCenterX * normalizedCenterX
                                        + normalizedCenterY * normalizedCenterY) * 2)
                                readonly property real audioEnergy: randomA < 0.40
                                    ? root.audioLow : randomA < 0.78 ? root.audioMid : root.audioHigh
                                readonly property real audioAngle: randomB * Math.PI * 2
                                readonly property real audioEnvelope: root.audioEffectsEnabled
                                    ? Math.max(0, Math.min(1, audioEnergy)) * Math.pow(edgeWeight, 1.35) : 0
                                readonly property real audioOffsetX: audioEnvelope <= 0 ? 0
                                    : Math.max(-root.audioDisplacementCap,
                                        Math.min(root.audioDisplacementCap,
                                            Math.sin(root.audioPhase * (0.75 + randomC * 0.55) + audioAngle)
                                                * audioEnvelope * root.audioDisplacementCap))
                                readonly property real audioOffsetY: audioEnvelope <= 0 ? 0
                                    : Math.max(-root.audioDisplacementCap,
                                        Math.min(root.audioDisplacementCap,
                                            Math.cos(root.audioPhase * (0.82 + randomD * 0.50) + audioAngle)
                                                * audioEnvelope * root.audioDisplacementCap * 0.82))
                                readonly property real combinedOffsetX: Math.max(
                                    -root.pointerDisplacementCap,
                                    Math.min(root.pointerDisplacementCap,
                                        pointerOffsetX + audioOffsetX))
                                readonly property real combinedOffsetY: Math.max(
                                    -root.pointerDisplacementCap,
                                    Math.min(root.pointerDisplacementCap,
                                        pointerOffsetY + audioOffsetY))

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
                                readonly property int formationDelay: Math.floor(Math.random() * 301)
                                readonly property int formationDuration: 1700
                                    + Math.floor(Math.random() * 351)
                                property real formationProgress:
                                    root.animationPreference === "off" ? 1 : 0

                                function applyPointerImpulse(localX, localY, speed) {
                                    if (!wordmarkCell.isFilledGlyph
                                            || wordmarkCell.formationProgress < 0.96
                                            || !root.pointerEffectsEnabled)
                                        return;

                                    const centerX = wordmarkCell.finalCellX
                                        + root.wordmarkCellWidth / 2;
                                    const centerY = wordmarkCell.finalCellY
                                        + root.wordmarkCellHeight / 2;
                                    let dx = centerX - localX;
                                    let dy = centerY - localY;
                                    let distance = Math.sqrt(dx * dx + dy * dy);
                                    if (distance >= root.pointerInfluenceRadius)
                                        return;
                                    if (distance < 0.001) {
                                        dx = Math.cos(wordmarkCell.audioAngle);
                                        dy = Math.sin(wordmarkCell.audioAngle);
                                        distance = 1;
                                    }

                                    const proximity = 1 - distance / root.pointerInfluenceRadius;
                                    const speedFactor = 0.28 + 0.72 * Math.min(1, speed / 1200);
                                    const impulse = root.pointerDisplacementCap * proximity * speedFactor;
                                    const targetX = Math.max(-root.pointerDisplacementCap,
                                        Math.min(root.pointerDisplacementCap,
                                            wordmarkCell.pointerOffsetX + dx / distance * impulse));
                                    const targetY = Math.max(-root.pointerDisplacementCap,
                                        Math.min(root.pointerDisplacementCap,
                                            wordmarkCell.pointerOffsetY + dy / distance * impulse));

                                    pointerReturnX.stop();
                                    pointerReturnY.stop();
                                    wordmarkCell.pointerOffsetX = targetX;
                                    wordmarkCell.pointerOffsetY = targetY;
                                    pointerReturnX.restart();
                                    pointerReturnY.restart();
                                }

                                Component.onCompleted: {
                                    if (wordmarkCell.isFilledGlyph)
                                        root.registerWordmarkCell(wordmarkRow.rowIndex,
                                            wordmarkCell.columnIndex, wordmarkCell);
                                }

                                x: finalCellX
                                    + (1 - formationProgress) * startX
                                    + Math.sin(Math.PI * wordmarkCell.formationProgress) * curveX
                                    + combinedOffsetX
                                y: (1 - formationProgress) * startY
                                    + Math.sin(Math.PI * wordmarkCell.formationProgress) * curveY
                                    + combinedOffsetY
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

                                NumberAnimation on pointerOffsetX {
                                    id: pointerReturnX
                                    running: false
                                    to: 0
                                    duration: 450
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 0.55
                                }

                                NumberAnimation on pointerOffsetY {
                                    id: pointerReturnY
                                    running: false
                                    to: 0
                                    duration: 450
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 0.55
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: root.metadataVisible ? implicitHeight : 0
                visible: root.metadataVisible
                spacing: Math.round(3 * root.uiScale)

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.showTime
                    text: root.timeText
                    color: root.theme.lockAccent
                    font.family: root.theme.fontFamily
                    font.pixelSize: Math.round(25 * root.uiScale)
                    font.weight: Font.Medium
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.showDate
                    text: root.dateText
                    color: root.theme.lockAccent
                    opacity: 0.72
                    font.family: root.theme.fontFamily
                    font.pixelSize: Math.round(11 * root.uiScale)
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.showUsername
                    text: root.usernameText
                    color: root.theme.lockAccent
                    opacity: 0.58
                    font.family: root.theme.fontFamily
                    font.pixelSize: Math.round(10 * root.uiScale)
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.showWeather && root.weatherText.length > 0
                    text: root.weatherText
                    color: root.theme.lockAccent
                    opacity: 0.68
                    font.family: root.theme.fontFamily
                    font.pixelSize: Math.round(10 * root.uiScale)
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

        Item {
            anchors.fill: parent
            z: 100
            visible: root.pointerEffectsEnabled && root.ghostOpacity > 0

            Repeater {
                model: root.ghostTrailLength

                Rectangle {
                    required property int index
                    readonly property var sample: root.ghostTrail[index]
                    readonly property real scaleFactor: 1 - index / root.ghostTrailLength
                    width: Math.max(3, Math.round((7 * scaleFactor) * root.uiScale))
                    height: width
                    radius: width / 2
                    x: Number(sample.x) - width / 2
                    y: Number(sample.y) - height / 2
                    color: root.theme.lockAccent
                    opacity: root.ghostOpacity * 0.34 * scaleFactor
                }
            }

            Rectangle {
                width: Math.round(18 * root.uiScale)
                height: width
                radius: width / 2
                x: root.ghostHeadX - width / 2
                y: root.ghostHeadY - height / 2
                color: root.theme.lockAccent
                opacity: root.ghostOpacity * 0.12
            }

            Rectangle {
                width: Math.round(8 * root.uiScale)
                height: width
                radius: width / 2
                x: root.ghostHeadX - width / 2
                y: root.ghostHeadY - height / 2
                color: root.theme.lockAccent
                opacity: root.ghostOpacity * 0.78
            }
        }
    }

    Timer {
        id: cursorFadeDelay
        interval: root.cursorFadeDelayMs
        repeat: false
        onTriggered: ghostFade.restart()
    }

    NumberAnimation {
        id: ghostFade
        target: root
        property: "ghostOpacity"
        to: 0
        duration: root.cursorFadeDurationMs
        easing.type: Easing.OutCubic
        onFinished: root.pointerActive = false
    }

    Timer {
        interval: 33
        repeat: true
        running: root.audioEffectsEnabled
        onTriggered: root.audioPhase += 0.22
    }

    Timer {
        interval: 15000
        repeat: true
        triggeredOnStart: true
        running: root.metadataVisible && (root.showTime || root.showDate)
        onTriggered: root.updateClockText()
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
        root.updateClockText();
        root.entered = true;
        Qt.callLater(() => password.forceActiveFocus());
    }
}
