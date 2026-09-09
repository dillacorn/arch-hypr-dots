from pathlib import Path
import hashlib
import shutil


def replace_once(path, old, new):
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one exact match, found {count}: {old[:120]!r}")
    file.write_text(text.replace(old, new, 1))


scene = "config/quickshell/awtarchy-lock/LockScene.qml"

replace_once(
    scene,
    '''    readonly property real clickDisplacementCap: 38 * uiScale
    readonly property real audioDisplacementCap: 6 * uiScale
    readonly property real pointerMovementThreshold: 3 * uiScale
''',
    '''    readonly property real clickDisplacementCap: 38 * uiScale
    readonly property real audioDisplacementCap: 6 * uiScale
    readonly property real logoBridgeMaxDistance: Math.sqrt(
        wordmarkCellWidth * wordmarkCellWidth + wordmarkCellHeight * wordmarkCellHeight) * 1.35
    readonly property real logoBridgeInteractionBoost: 0.30
    readonly property var logoBridgePairs: buildLogoBridgePairs()
    readonly property real pointerMovementThreshold: 3 * uiScale
'''
)

replace_once(
    scene,
    '''    function registerWordmarkCell(row, column, cell) {
        wordmarkCells[String(row) + ":" + String(column)] = cell;
    }

''',
    '''    function isFilledWordmarkCell(row, column) {
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

'''
)

replace_once(
    scene,
    '''        Item {
            id: wordmarkItem
            visible: root.presentationVisible("logo", root.showLogo)
            opacity: root.presentationOpacity("logo")
            x: root.normalizedX("logo", 0.50) * parent.width - width / 2
            y: root.normalizedY("logo", 0.34) * parent.height - height / 2
            width: root.wordmarkWidth
            height: root.wordmarkHeight
            scale: root.elementScale("logo")
            transformOrigin: Item.Center

            Repeater {
''',
    '''        Item {
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
'''
)

replace_once(
    scene,
    '''                                pointerReturnX.restart();
                                pointerReturnY.restart();
                            }

                            function applyClickImpulse(localX, localY) {
''',
    '''                                pointerReturnX.restart();
                                pointerReturnY.restart();
                                logoBridgeCanvas.requestPaint();
                            }

                            function applyClickImpulse(localX, localY) {
'''
)

replace_once(
    scene,
    '''                                pointerReturnX.restart();
                                pointerReturnY.restart();
                            }

                            Component.onCompleted: {
''',
    '''                                pointerReturnX.restart();
                                pointerReturnY.restart();
                                logoBridgeCanvas.requestPaint();
                            }

                            onFormationProgressChanged: logoBridgeCanvas.requestPaint()
                            onCombinedOffsetXChanged: logoBridgeCanvas.requestPaint()
                            onCombinedOffsetYChanged: logoBridgeCanvas.requestPaint()

                            Component.onCompleted: {
'''
)

replace_once(
    scene,
    '''        onTriggered: root.audioPhase += 0.22
''',
    '''        onTriggered: {
            root.audioPhase += 0.22;
            logoBridgeCanvas.requestPaint();
        }
'''
)

shutil.copy2(scene, "config/quickshell/awtarchy/LockPreviewScene.qml")

history = Path("local/share/awtarchy/quickshell-managed-history.sha256")
text = history.read_text()
existing = set(text.splitlines())
additions = []
for source, installed in [
    ("config/quickshell/awtarchy-lock/LockScene.qml", ".config/quickshell/awtarchy-lock/LockScene.qml"),
    ("config/quickshell/awtarchy/LockPreviewScene.qml", ".config/quickshell/awtarchy/LockPreviewScene.qml"),
]:
    digest = hashlib.sha256(Path(source).read_bytes()).hexdigest()
    line = f"{digest}\t{installed}"
    if line not in existing:
        additions.append(line)
if additions:
    with history.open("a") as handle:
        if text and not text.endswith("\n"):
            handle.write("\n")
        handle.write("\n".join(additions) + "\n")
