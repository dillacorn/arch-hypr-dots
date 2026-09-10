import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    required property var theme
    required property string animationPreference
    required property int randomFormationMode
    required property bool audioReactive
    required property real audioLow
    required property real audioMid
    required property real audioHigh
    required property real audioOverall
    required property bool mouseInteractive
    required property bool showLogo
    required property bool showTime
    required property bool showDate
    required property bool showUsername
    required property bool showWeather
    required property string weatherText
    required property string backgroundMode
    required property string wallpaperSource
    required property color backgroundColor
    required property var autoAccents
    required property var layout

    property bool previewMode: false
    property bool editorMode: false
    property var editorVisibility: ({})
    property bool unlocking: false
    property bool entered: false

    readonly property real uiScale: Math.max(0.72, Math.min(1.35,
        Math.min(width / 1920, height / 1080)))
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
    readonly property real wordmarkWidth: wordmarkColumns * wordmarkCellWidth
    readonly property real wordmarkHeight: wordmarkRows.length * wordmarkCellHeight
    readonly property int formationMode: animationPreference === "swarm" ? 0
        : animationPreference === "edges" ? 1
        : animationPreference === "center" ? 2
        : animationPreference === "split" ? 3
        : randomFormationMode
    readonly property real audioLevel: audioOverall
    readonly property real audioSilenceThreshold: 0.01
    readonly property bool pointerEffectsEnabled: mouseInteractive && pointerActive
    readonly property bool audioEffectsEnabled: audioReactive && audioLevel > audioSilenceThreshold
    readonly property int ghostTrailLength: 6
    readonly property int pointerUpdateIntervalMs: 16
    readonly property int cursorFadeDelayMs: 180
    readonly property int cursorFadeDurationMs: 320
    readonly property real pointerInfluenceRadius: 72 * uiScale
    readonly property real pointerDisplacementCap: 24 * uiScale
    readonly property real clickInfluenceRadius: 110 * uiScale
    readonly property real clickDisplacementCap: 38 * uiScale
    readonly property real audioDisplacementCap: 6 * uiScale
    readonly property real logoBridgeMaxDistance: Math.sqrt(
        wordmarkCellWidth * wordmarkCellWidth + wordmarkCellHeight * wordmarkCellHeight) * 1.35
    readonly property real logoBridgeInteractionBoost: 0.30
    readonly property var logoBridgePairs: buildLogoBridgePairs()
    readonly property real pointerMovementThreshold: 3 * uiScale
    readonly property string usernameText: showUsername ? Quickshell.env("USER") : ""

    readonly property real passwordCenterX: normalizedX("password", 0.50) * width
    readonly property real passwordCenterY: normalizedY("password", 0.70) * height
    readonly property real passwordWidth: Math.round(420 * uiScale * elementScale("password"))
    readonly property real passwordHeight: Math.round(58 * uiScale * elementScale("password"))

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

    function normalizedPoint(name) {
        const value = root.layout && typeof root.layout === "object"
            ? root.layout[name] : null;
        return value && typeof value === "object" ? value : null;
    }

    function normalizedX(name, fallback) {
        const point = normalizedPoint(name);
        const value = point ? Number(point.x) : Number.NaN;
        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;
    }

    function normalizedY(name, fallback) {
        const point = normalizedPoint(name);
        const value = point ? Number(point.y) : Number.NaN;
        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;
    }

    function elementScale(name) {
        const point = normalizedPoint(name);
        const value = point ? Number(point.scale === undefined ? 1 : point.scale) : 1;
        return Number.isFinite(value) ? Math.max(0.50, Math.min(2.00, value)) : 1;
    }

    function elementColor(name) {
        const point = normalizedPoint(name);
        const value = String(point && point.color !== undefined ? point.color : "auto");
        const automatic = String(root.autoAccents && root.autoAccents[name] !== undefined
            ? root.autoAccents[name] : "#ffffff");
        const safeAuto = /^#[0-9a-fA-F]{6}$/.test(automatic) ? automatic : "#ffffff";
        return value === "auto" ? safeAuto
            : /^#[0-9a-fA-F]{6}$/.test(value) ? value : safeAuto;
    }

    function presentationVisible(name, configuredVisible) {
        return configuredVisible || root.editorMode;
    }

    function presentationOpacity(name) {
        return root.editorMode && root.editorVisibility[name] === false ? 0.30 : 1.0;
    }

    function elementVisualWidth(name) {
        if (name === "logo") return root.wordmarkWidth * root.elementScale("logo");
        if (name === "time") return timeItem.implicitWidth * root.elementScale("time");
        if (name === "date") return dateItem.implicitWidth * root.elementScale("date");
        if (name === "username") return usernameItem.implicitWidth * root.elementScale("username");
        if (name === "weather") return weatherItem.implicitWidth * root.elementScale("weather");
        if (name === "password") return root.passwordWidth;
        return 48 * root.uiScale;
    }

    function elementVisualHeight(name) {
        if (name === "logo") return root.wordmarkHeight * root.elementScale("logo");
        if (name === "time") return timeItem.implicitHeight * root.elementScale("time");
        if (name === "date") return dateItem.implicitHeight * root.elementScale("date");
        if (name === "username") return usernameItem.implicitHeight * root.elementScale("username");
        if (name === "weather") return weatherItem.implicitHeight * root.elementScale("weather");
        if (name === "password") return root.passwordHeight;
        return 28 * root.uiScale;
    }

    function isFilledWordmarkCell(row, column) {
        if (row < 0 || row >= wordmarkRows.length || column < 0 || column >= wordmarkColumns)
            return false;
        const rowText = wordmarkRows[row];
        if (column >= rowText.length)
            return false;
        const glyph = rowText.charAt(column);
        return glyph === "█" || glyph === "▄" || glyph === "▀" || glyph === "▐";
    }

    function buildLogoBridgePairs() {
        const pairs = [];
        const neighbors = [({ row: 0, column: 1 }), ({ row: 1, column: 0 })];
        for (let row = 0; row < wordmarkRows.length; ++row) {
            for (let column = 0; column < wordmarkColumns; ++column) {
                if (!isFilledWordmarkCell(row, column))
                    continue;
                for (let i = 0; i < neighbors.length; ++i) {
                    const nextRow = row + neighbors[i].row;
                    const nextColumn = column + neighbors[i].column;
                    if (isFilledWordmarkCell(nextRow, nextColumn)) {
                        pairs.push(({
                            a: String(row) + ":" + String(column),
                            b: String(nextRow) + ":" + String(nextColumn)
                        }));
                    }
                }
            }
        }
        return pairs;
    }

    function registerWordmarkCell(row, column, cell) {
        wordmarkCells[String(row) + ":" + String(column)] = cell;
        logoBridgeCanvas.requestPaint();
    }

    function logoBridgeInteractionEnergy(cellA, cellB) {
        const offsetA = Math.sqrt(cellA.combinedOffsetX * cellA.combinedOffsetX
            + cellA.combinedOffsetY * cellA.combinedOffsetY);
        const offsetB = Math.sqrt(cellB.combinedOffsetX * cellB.combinedOffsetX
            + cellB.combinedOffsetY * cellB.combinedOffsetY);
        return Math.max(0, Math.min(1, Math.max(offsetA, offsetB) / clickDisplacementCap));
    }

    function minuteTimeFormat() {
        const localeFormat = String(Qt.locale().timeFormat(Locale.ShortFormat) || "");
        const withoutSeconds = localeFormat
            .replace(/([:.\-\s])s{1,2}(?:\.z{1,3})?/g, "")
            .replace(/s{1,2}([:.\-\s])/g, "")
            .replace(/z{1,3}/g, "")
            .replace(/\s{2,}/g, " ")
            .trim();
        return withoutSeconds.length > 0 ? withoutSeconds : "HH:mm";
    }

    function updateClockText() {
        const now = new Date();
        timeText = Qt.formatTime(now, minuteTimeFormat());
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

        const local = wordmarkItem.mapFromItem(root, x, y);
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

    function applyClickImpulse(x, y) {
        if (!mouseInteractive)
            return;

        const local = wordmarkItem.mapFromItem(root, x, y);
        const radius = clickInfluenceRadius;
        if (local.x < -radius || local.y < -radius
                || local.x > wordmarkItem.width + radius
                || local.y > wordmarkItem.height + radius)
            return;

        const minColumn = Math.max(0, Math.floor((local.x - radius) / wordmarkCellWidth));
        const maxColumn = Math.min(wordmarkColumns - 1, Math.floor((local.x + radius) / wordmarkCellWidth));
        const minRow = Math.max(0, Math.floor((local.y - radius) / wordmarkCellHeight));
        const maxRow = Math.min(wordmarkRows.length - 1, Math.floor((local.y + radius) / wordmarkCellHeight));
        for (let row = minRow; row <= maxRow; ++row) {
            for (let column = minColumn; column <= maxColumn; ++column) {
                const cell = wordmarkCells[String(row) + ":" + String(column)];
                if (cell)
                    cell.applyClickImpulse(local.x, local.y);
            }
        }
    }

    function handlePointerClick(x, y) {
        if (!mouseInteractive)
            return;
        pointerActive = true;
        pushGhostSample(x, y);
        applyClickImpulse(x, y);
        lastPointerX = x;
        lastPointerY = y;
        lastPointerSampleTime = Date.now();
    }

    function handlePointerMotion(x, y) {
        if (!mouseInteractive)
            return;

        pointerActive = true;
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

    Rectangle {
        anchors.fill: parent
        color: root.backgroundMode === "color" ? root.backgroundColor : "#000000"
    }

    Image {
        anchors.fill: parent
        visible: root.backgroundMode === "wallpaper" && root.wallpaperSource.length > 0
        source: root.wallpaperSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
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

        Item {
            id: wordmarkItem
            visible: root.presentationVisible("logo", root.showLogo)
            opacity: root.presentationOpacity("logo")
            x: root.normalizedX("logo", 0.50) * parent.width - width / 2
            y: root.normalizedY("logo", 0.34) * parent.height - height / 2
            width: root.wordmarkWidth
            height: root.wordmarkHeight
            scale: root.elementScale("logo")
            transformOrigin: Item.Center

            Canvas {
                id: logoBridgeCanvas
                anchors.fill: parent
                z: -1
                antialiasing: true

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.clearRect(0, 0, width, height);
                    ctx.strokeStyle = root.elementColor("logo");
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";

                    for (let i = 0; i < root.logoBridgePairs.length; ++i) {
                        const pair = root.logoBridgePairs[i];
                        const cellA = root.wordmarkCells[pair.a];
                        const cellB = root.wordmarkCells[pair.b];
                        if (!cellA || !cellB)
                            continue;

                        const formation = Math.min(cellA.formationProgress, cellB.formationProgress);
                        if (formation <= 0.35)
                            continue;

                        const pointA = cellA.mapToItem(wordmarkItem,
                            cellA.width / 2, cellA.height / 2);
                        const pointB = cellB.mapToItem(wordmarkItem,
                            cellB.width / 2, cellB.height / 2);
                        const dx = pointB.x - pointA.x;
                        const dy = pointB.y - pointA.y;
                        const distance = Math.sqrt(dx * dx + dy * dy);
                        if (distance >= root.logoBridgeMaxDistance)
                            continue;

                        const closeness = 1 - distance / root.logoBridgeMaxDistance;
                        const interaction = root.logoBridgeInteractionEnergy(cellA, cellB);
                        const interactionScale = 1 + interaction * root.logoBridgeInteractionBoost;
                        ctx.globalAlpha = Math.min(0.48,
                            (0.10 + 0.24 * closeness) * formation * interactionScale);
                        ctx.lineWidth = Math.max(1.2 * root.uiScale,
                            (2.0 + 2.2 * closeness) * root.uiScale * interactionScale);
                        ctx.beginPath();
                        ctx.moveTo(pointA.x, pointA.y);
                        ctx.lineTo(pointB.x, pointB.y);
                        ctx.stroke();
                    }
                    ctx.globalAlpha = 1;
                }
            }

            Repeater {
                model: root.wordmarkRows.length

                delegate: Item {
                    id: wordmarkRow
                    readonly property int rowIndex: index
                    readonly property string rowText: root.wordmarkRows[rowIndex]

                    x: 0
                    y: rowIndex * root.wordmarkCellHeight
                    width: root.wordmarkWidth
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
                            readonly property real finalCellX: columnIndex * root.wordmarkCellWidth
                            readonly property real finalCellY: wordmarkRow.rowIndex
                                * root.wordmarkCellHeight
                            property real pointerOffsetX: 0
                            property real pointerOffsetY: 0
                            readonly property real normalizedCenterX: root.wordmarkWidth > 0
                                ? (finalCellX + root.wordmarkCellWidth / 2) / root.wordmarkWidth - 0.5 : 0
                            readonly property real normalizedCenterY: root.wordmarkHeight > 0
                                ? (finalCellY + root.wordmarkCellHeight / 2) / root.wordmarkHeight - 0.5 : 0
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
                                -root.clickDisplacementCap,
                                Math.min(root.clickDisplacementCap,
                                    pointerOffsetX + audioOffsetX))
                            readonly property real combinedOffsetY: Math.max(
                                -root.clickDisplacementCap,
                                Math.min(root.clickDisplacementCap,
                                    pointerOffsetY + audioOffsetY))

                            readonly property real randomA: Math.random()
                            readonly property real randomB: Math.random()
                            readonly property real randomC: Math.random()
                            readonly property real randomD: Math.random()
                            readonly property real randomE: Math.random()
                            readonly property real startAngle: randomA * Math.PI * 2
                            readonly property real startDistance: (150 + randomB * 330) * root.uiScale
                            readonly property int edgeSide: Math.floor(randomC * 4)
                            readonly property real edgeMargin: (100 + randomD * 180) * root.uiScale
                            readonly property real jitterX: (randomD - 0.5) * 180 * root.uiScale
                            readonly property real jitterY: (randomE - 0.5) * 130 * root.uiScale
                            readonly property real swarmStartX: Math.cos(startAngle) * startDistance
                            readonly property real swarmStartY: Math.sin(startAngle) * startDistance
                            readonly property real edgeStartX: edgeSide === 0
                                ? -finalCellX - edgeMargin
                                : edgeSide === 1
                                    ? root.wordmarkWidth - finalCellX + edgeMargin
                                    : jitterX
                            readonly property real edgeStartY: edgeSide === 2
                                ? -finalCellY - edgeMargin
                                : edgeSide === 3
                                    ? root.wordmarkHeight - finalCellY + edgeMargin
                                    : jitterY
                            readonly property real centerStartX: root.wordmarkWidth / 2
                                - finalCellX + jitterX * 0.35
                            readonly property real centerStartY: root.wordmarkHeight / 2
                                - finalCellY + jitterY * 0.35
                            readonly property real splitStartX: columnIndex < root.wordmarkColumns / 2
                                ? -finalCellX - edgeMargin
                                : root.wordmarkWidth - finalCellX + edgeMargin
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
                                logoBridgeCanvas.requestPaint();
                            }

                            function applyClickImpulse(localX, localY) {
                                if (!wordmarkCell.isFilledGlyph
                                        || wordmarkCell.formationProgress < 0.96
                                        || !root.mouseInteractive)
                                    return;

                                const centerX = wordmarkCell.finalCellX + root.wordmarkCellWidth / 2;
                                const centerY = wordmarkCell.finalCellY + root.wordmarkCellHeight / 2;
                                let dx = centerX - localX;
                                let dy = centerY - localY;
                                let distance = Math.sqrt(dx * dx + dy * dy);
                                if (distance >= root.clickInfluenceRadius)
                                    return;
                                if (distance < 0.001) {
                                    dx = Math.cos(wordmarkCell.audioAngle);
                                    dy = Math.sin(wordmarkCell.audioAngle);
                                    distance = 1;
                                }

                                const proximity = 1 - distance / root.clickInfluenceRadius;
                                const impulse = root.clickDisplacementCap * proximity * (0.82 + 0.18 * wordmarkCell.randomC);
                                const targetX = Math.max(-root.clickDisplacementCap,
                                    Math.min(root.clickDisplacementCap,
                                        wordmarkCell.pointerOffsetX + dx / distance * impulse));
                                const targetY = Math.max(-root.clickDisplacementCap,
                                    Math.min(root.clickDisplacementCap,
                                        wordmarkCell.pointerOffsetY + dy / distance * impulse));

                                pointerReturnX.stop();
                                pointerReturnY.stop();
                                wordmarkCell.pointerOffsetX = targetX;
                                wordmarkCell.pointerOffsetY = targetY;
                                pointerReturnX.restart();
                                pointerReturnY.restart();
                                logoBridgeCanvas.requestPaint();
                            }

                            onFormationProgressChanged: logoBridgeCanvas.requestPaint()
                            onCombinedOffsetXChanged: logoBridgeCanvas.requestPaint()
                            onCombinedOffsetYChanged: logoBridgeCanvas.requestPaint()

                            Component.onCompleted: {
                                if (wordmarkCell.isFilledGlyph)
                                    root.registerWordmarkCell(wordmarkRow.rowIndex,
                                        wordmarkCell.columnIndex, wordmarkCell);
                            }

                            x: finalCellX
                                + (1 - formationProgress) * startX
                                + Math.sin(Math.PI * formationProgress) * curveX
                                + combinedOffsetX
                            y: (1 - formationProgress) * startY
                                + Math.sin(Math.PI * formationProgress) * curveY
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
                                color: root.elementColor("logo")
                                opacity: wordmarkCell.formationProgress <= 0 ? 0
                                    : 0.35 + 0.65 * wordmarkCell.formationProgress
                                antialiasing: false
                            }

                            SequentialAnimation on formationProgress {
                                running: wordmarkCell.isFilledGlyph
                                    && root.entered && !root.unlocking
                                    && root.animationPreference !== "off"

                                PauseAnimation { duration: wordmarkCell.formationDelay }
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

        Text {
            id: timeItem
            visible: root.presentationVisible("time", root.showTime)
            opacity: root.presentationOpacity("time")
            scale: root.elementScale("time")
            transformOrigin: Item.Center
            x: root.normalizedX("time", 0.50) * parent.width - width / 2
            y: root.normalizedY("time", 0.51) * parent.height - height / 2
            text: root.timeText
            color: root.elementColor("time")
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(64 * root.uiScale)
            font.weight: Font.Medium
        }

        Text {
            id: dateItem
            visible: root.presentationVisible("date", root.showDate)
            opacity: 0.78 * root.presentationOpacity("date")
            scale: root.elementScale("date")
            transformOrigin: Item.Center
            x: root.normalizedX("date", 0.50) * parent.width - width / 2
            y: root.normalizedY("date", 0.555) * parent.height - height / 2
            text: root.dateText
            color: root.elementColor("date")
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(22 * root.uiScale)
        }

        Text {
            id: usernameItem
            visible: root.presentationVisible("username", root.showUsername)
            opacity: 0.72 * root.presentationOpacity("username")
            scale: root.elementScale("username")
            transformOrigin: Item.Center
            x: root.normalizedX("username", 0.50) * parent.width - width / 2
            y: root.normalizedY("username", 0.595) * parent.height - height / 2
            text: root.usernameText.length > 0 ? root.usernameText : Quickshell.env("USER")
            color: root.elementColor("username")
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(18 * root.uiScale)
        }

        Text {
            id: weatherItem
            visible: root.presentationVisible("weather", root.showWeather) && root.weatherText.length > 0
            opacity: 0.76 * root.presentationOpacity("weather")
            scale: root.elementScale("weather")
            transformOrigin: Item.Center
            x: root.normalizedX("weather", 0.50) * parent.width - width / 2
            y: root.normalizedY("weather", 0.635) * parent.height - height / 2
            text: root.weatherText
            color: root.elementColor("weather")
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(18 * root.uiScale)
        }

        Item {
            visible: root.previewMode
            x: root.passwordCenterX - width / 2
            y: root.passwordCenterY - height / 2
            width: root.passwordWidth
            height: root.passwordHeight

            Rectangle {
                anchors.centerIn: parent
                width: Math.round(80 * root.uiScale * root.elementScale("password"))
                height: Math.round(14 * root.uiScale * root.elementScale("password"))
                color: root.elementColor("password")
                opacity: 0.09
            }

            Row {
                anchors.centerIn: parent
                spacing: Math.round(7 * root.uiScale * root.elementScale("password"))
                Repeater {
                    model: 4
                    Rectangle {
                        width: Math.round(7 * root.uiScale * root.elementScale("password"))
                        height: Math.round(10 * root.uiScale * root.elementScale("password"))
                        color: root.elementColor("password")
                        opacity: 0.82
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
        onTriggered: {
            root.audioPhase += 0.22;
            logoBridgeCanvas.requestPaint();
        }
    }

    Timer {
        interval: 15000
        repeat: true
        triggeredOnStart: true
        running: root.showTime || root.showDate
        onTriggered: root.updateClockText()
    }

    Component.onCompleted: {
        root.updateClockText();
        root.entered = true;
    }
}
