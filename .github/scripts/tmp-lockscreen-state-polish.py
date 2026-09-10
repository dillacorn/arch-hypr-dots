#!/usr/bin/env python3
from pathlib import Path

SCENE = Path("config/quickshell/awtarchy-lock/LockScene.qml")
PREVIEW = Path("config/quickshell/awtarchy/LockPreviewScene.qml")
EFFECTS_TEST = Path("tests/test-quickshell-lockscreen-interactive-effects.sh")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


def remove_between(text: str, start: str, end: str, label: str) -> str:
    start_count = text.count(start)
    end_count = text.count(end)
    if start_count != 1 or end_count < 1:
        raise SystemExit(
            f"{label}: expected one start and at least one end; got {start_count}/{end_count}"
        )
    begin = text.index(start)
    finish = text.index(end, begin)
    return text[:begin] + text[finish:]


text = SCENE.read_text()

text = replace_once(
    text,
    '''    readonly property real audioDisplacementCap: 6 * uiScale
    readonly property real logoBridgeMaxDistance: Math.sqrt(
        wordmarkCellWidth * wordmarkCellWidth + wordmarkCellHeight * wordmarkCellHeight) * 1.35
    readonly property real logoBridgeInteractionBoost: 0.30
    readonly property var logoBridgePairs: buildLogoBridgePairs()
    readonly property real pointerMovementThreshold: 3 * uiScale''',
    '''    readonly property real audioDisplacementCap: 6 * uiScale
    readonly property int pointerResponseDurationMs: 100
    readonly property int pointerReturnDurationMs: 180
    readonly property var logoCohesionGroups: buildLogoCohesionGroups()
    readonly property real pointerMovementThreshold: 3 * uiScale''',
    "cohesion properties",
)

text = replace_once(
    text,
    '''    property bool pointerActive: false
    property var wordmarkCells: ({})
    property real ghostHeadX: -100''',
    '''    property bool pointerActive: false
    property var wordmarkCells: ({})
    property real pointerFieldX: -1000
    property real pointerFieldY: -1000
    property real pointerFieldStrength: 0
    property real clickFieldX: -1000
    property real clickFieldY: -1000
    property real clickFieldStrength: 0
    property real ghostHeadX: -100''',
    "interaction fields",
)

old_group_start = '''    function buildLogoBridgePairs() {'''
old_group_end = '''    function minuteTimeFormat() {'''
new_group_block = '''    function logoCellKey(row, column) {
        return String(row) + ":" + String(column);
    }

    function buildLogoCohesionGroups() {
        const groups = [];
        const visited = ({});
        const neighbors = [
            ({ row: 0, column: 1 }),
            ({ row: 1, column: 0 }),
            ({ row: 0, column: -1 }),
            ({ row: -1, column: 0 })
        ];
        let groupId = 0;

        for (let row = 0; row < wordmarkRows.length; ++row) {
            for (let column = 0; column < wordmarkColumns; ++column) {
                const firstKey = logoCellKey(row, column);
                if (!isFilledWordmarkCell(row, column) || visited[firstKey])
                    continue;

                const queue = [({ row: row, column: column })];
                const cells = [];
                const members = ({});
                let cursor = 0;
                let sumX = 0;
                let sumY = 0;
                visited[firstKey] = true;

                while (cursor < queue.length) {
                    const cell = queue[cursor++];
                    const key = logoCellKey(cell.row, cell.column);
                    cells.push(cell);
                    members[key] = true;
                    sumX += (cell.column + 0.5) * wordmarkCellWidth;
                    sumY += (cell.row + 0.5) * wordmarkCellHeight;

                    for (let i = 0; i < neighbors.length; ++i) {
                        const nextRow = cell.row + neighbors[i].row;
                        const nextColumn = cell.column + neighbors[i].column;
                        const nextKey = logoCellKey(nextRow, nextColumn);
                        if (!visited[nextKey] && isFilledWordmarkCell(nextRow, nextColumn)) {
                            visited[nextKey] = true;
                            queue.push(({ row: nextRow, column: nextColumn }));
                        }
                    }
                }

                groups.push(({
                    id: groupId,
                    cells: cells,
                    members: members,
                    centerX: sumX / Math.max(1, cells.length),
                    centerY: sumY / Math.max(1, cells.length)
                }));
                ++groupId;
            }
        }
        return groups;
    }

    function logoGroupFor(row, column) {
        const key = logoCellKey(row, column);
        for (let i = 0; i < logoCohesionGroups.length; ++i) {
            const group = logoCohesionGroups[i];
            if (group.members && group.members[key])
                return group;
        }
        return null;
    }

    function registerWordmarkCell(row, column, cell) {
        const next = Object.assign({}, wordmarkCells);
        next[logoCellKey(row, column)] = cell;
        wordmarkCells = next;
    }

    function logoGroupReady(group) {
        if (!group || !Array.isArray(group.cells) || group.cells.length === 0)
            return false;
        for (let i = 0; i < group.cells.length; ++i) {
            const member = group.cells[i];
            const cell = wordmarkCells[logoCellKey(member.row, member.column)];
            if (!cell || cell.formationProgress < 0.96)
                return false;
        }
        return true;
    }

    function radialFieldOffset(group, fieldX, fieldY, strength, radius, cap) {
        if (!group || strength <= 0 || radius <= 0 || cap <= 0)
            return ({ x: 0, y: 0 });

        let dx = group.centerX - fieldX;
        let dy = group.centerY - fieldY;
        let distance = Math.sqrt(dx * dx + dy * dy);
        if (distance >= radius)
            return ({ x: 0, y: 0 });
        if (distance < 0.001) {
            const angle = (group.id + 1) * 2.399963229728653;
            dx = Math.cos(angle);
            dy = Math.sin(angle);
            distance = 1;
        }

        const raw = Math.max(0, Math.min(1, 1 - distance / radius));
        const proximity = raw * raw * (3 - 2 * raw);
        const magnitude = cap * proximity * Math.max(0, Math.min(1, strength));
        return ({
            x: dx / distance * magnitude,
            y: dy / distance * magnitude
        });
    }

    function logoDeformationOffset(group) {
        if (!group)
            return ({ x: 0, y: 0 });
        const pointer = pointerEffectsEnabled
            ? radialFieldOffset(group, pointerFieldX, pointerFieldY,
                pointerFieldStrength, pointerInfluenceRadius, pointerDisplacementCap)
            : ({ x: 0, y: 0 });
        const click = mouseInteractive
            ? radialFieldOffset(group, clickFieldX, clickFieldY,
                clickFieldStrength, clickInfluenceRadius, clickDisplacementCap)
            : ({ x: 0, y: 0 });
        return ({
            x: Math.max(-clickDisplacementCap,
                Math.min(clickDisplacementCap, pointer.x + click.x)),
            y: Math.max(-clickDisplacementCap,
                Math.min(clickDisplacementCap, pointer.y + click.y))
        });
    }

    function logoGroupAudioOffset(group) {
        if (!group || !audioEffectsEnabled)
            return ({ x: 0, y: 0 });
        const normalizedX = wordmarkWidth > 0 ? group.centerX / wordmarkWidth - 0.5 : 0;
        const normalizedY = wordmarkHeight > 0 ? group.centerY / wordmarkHeight - 0.5 : 0;
        const edgeWeight = Math.min(1,
            Math.sqrt(normalizedX * normalizedX + normalizedY * normalizedY) * 2);
        const band = group.id % 3;
        const energy = band === 0 ? audioLow : band === 1 ? audioMid : audioHigh;
        const envelope = Math.max(0, Math.min(1, energy)) * Math.pow(edgeWeight, 1.35);
        if (envelope <= 0)
            return ({ x: 0, y: 0 });
        const angle = (group.id + 1) * 1.61803398875;
        const rate = 0.82 + (group.id % 5) * 0.07;
        return ({
            x: Math.max(-audioDisplacementCap,
                Math.min(audioDisplacementCap,
                    Math.sin(audioPhase * rate + angle) * envelope * audioDisplacementCap)),
            y: Math.max(-audioDisplacementCap,
                Math.min(audioDisplacementCap,
                    Math.cos(audioPhase * (rate + 0.09) + angle)
                        * envelope * audioDisplacementCap * 0.82))
        });
    }

    function minuteTimeFormat() {'''
start = text.index(old_group_start)
finish = text.index(old_group_end, start)
text = text[:start] + new_group_block + text[finish + len(old_group_end):]

old_pointer_start = '''    function applyPointerImpulse(x, y, speed) {'''
old_pointer_end = '''    Rectangle {
        anchors.fill: parent
        color: root.backgroundMode === "color" ? root.backgroundColor : "#000000"
    }'''
new_pointer_block = '''    function updatePointerField(x, y, speed) {
        if (!pointerEffectsEnabled)
            return;
        const local = wordmarkItem.mapFromItem(root, x, y);
        pointerFieldX = local.x;
        pointerFieldY = local.y;
        pointerFieldStrength = 0.35 + 0.65 * Math.min(1, Math.max(0, speed) / 1400);
    }

    function applyClickField(x, y) {
        if (!mouseInteractive)
            return;
        const local = wordmarkItem.mapFromItem(root, x, y);
        clickFieldX = local.x;
        clickFieldY = local.y;
        clickFieldStrength = 1;
        clickFieldDecay.restart();
    }

    function handlePointerClick(x, y) {
        if (!mouseInteractive)
            return;
        pointerActive = true;
        pushGhostSample(x, y);
        applyClickField(x, y);
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
            updatePointerField(x, y, speed);
            lastPhysicsUpdateTime = now;
        }

        lastPointerX = x;
        lastPointerY = y;
        lastPointerSampleTime = now;
    }

    NumberAnimation {
        id: clickFieldDecay
        target: root
        property: "clickFieldStrength"
        from: 1
        to: 0
        duration: 260
        easing.type: Easing.OutCubic
    }

    Rectangle {
        anchors.fill: parent
        color: root.backgroundMode === "color" ? root.backgroundColor : "#000000"
    }'''
start = text.index(old_pointer_start)
finish = text.index(old_pointer_end, start)
text = text[:start] + new_pointer_block + text[finish + len(old_pointer_end):]

text = remove_between(
    text,
    '''            Canvas {
                id: logoBridgeCanvas''',
    '''            Repeater {
                model: root.wordmarkRows.length''',
    "legacy bridge canvas",
)

cell_start = '''                            property real pointerOffsetX: 0
                            property real pointerOffsetY: 0'''
cell_end = '''                            readonly property real randomA: Math.random()'''
cell_block = '''                            readonly property var cohesionGroup: isFilledGlyph
                                ? root.logoGroupFor(wordmarkRow.rowIndex, columnIndex) : null
                            readonly property bool cohesionReady: isFilledGlyph
                                && root.logoGroupReady(cohesionGroup)
                            readonly property var pointerTarget: cohesionReady
                                ? root.logoDeformationOffset(cohesionGroup) : ({ x: 0, y: 0 })
                            readonly property bool pointerTargetActive:
                                Math.abs(pointerTarget.x) + Math.abs(pointerTarget.y) > 0.01
                            property real pointerOffsetX: pointerTarget.x
                            property real pointerOffsetY: pointerTarget.y
                            readonly property var groupAudioOffset: cohesionReady
                                ? root.logoGroupAudioOffset(cohesionGroup) : ({ x: 0, y: 0 })
                            readonly property real audioOffsetX: groupAudioOffset.x
                            readonly property real audioOffsetY: groupAudioOffset.y
                            readonly property real combinedOffsetX: Math.max(
                                -root.clickDisplacementCap,
                                Math.min(root.clickDisplacementCap,
                                    pointerOffsetX + audioOffsetX))
                            readonly property real combinedOffsetY: Math.max(
                                -root.clickDisplacementCap,
                                Math.min(root.clickDisplacementCap,
                                    pointerOffsetY + audioOffsetY))

                            readonly property real randomA: Math.random()'''
start = text.index(cell_start)
finish = text.index(cell_end, start)
text = text[:start] + cell_block + text[finish + len(cell_end):]

text = remove_between(
    text,
    '''                            function applyPointerImpulse(localX, localY, speed) {''',
    '''                            Component.onCompleted: {''',
    "per-cell impulse functions",
)

old_returns = '''                            NumberAnimation on pointerOffsetX {
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
                            }'''
new_returns = '''                            Behavior on pointerOffsetX {
                                NumberAnimation {
                                    duration: wordmarkCell.pointerTargetActive
                                        ? root.pointerResponseDurationMs
                                        : root.pointerReturnDurationMs
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Behavior on pointerOffsetY {
                                NumberAnimation {
                                    duration: wordmarkCell.pointerTargetActive
                                        ? root.pointerResponseDurationMs
                                        : root.pointerReturnDurationMs
                                    easing.type: Easing.OutCubic
                                }
                            }'''
text = replace_once(text, old_returns, new_returns, "smooth shared deformation behavior")

for forbidden in (
    "logoBridgeCanvas",
    "logoBridgePairs",
    "logoBridgeMaxDistance",
    "logoBridgeInteractionBoost",
    "buildLogoBridgePairs",
    "logoBridgeInteractionEnergy",
    "Easing.OutBack",
    "pointerReturnX",
    "pointerReturnY",
):
    if forbidden in text:
        raise SystemExit(f"legacy cohesion token remains after patch: {forbidden}")

SCENE.write_text(text)
PREVIEW.write_text(text)

# Align older interaction contracts with the new group-field implementation.
test = EFFECTS_TEST.read_text()
test = replace_once(
    test,
    '''require_text "$SCENE_QML" 'property real pointerOffsetX: 0' \\
    'wordmark cells have no pointer displacement state'
require_text "$SCENE_QML" 'property real pointerOffsetY: 0' \\
    'wordmark cells have no pointer displacement state' ''',
    '''require_text "$SCENE_QML" 'property real pointerOffsetX:' \\
    'wordmark cells have no pointer displacement state'
require_text "$SCENE_QML" 'property real pointerOffsetY:' \\
    'wordmark cells have no pointer displacement state' ''',
    "legacy pointer state assertions",
)
test = replace_once(
    test,
    '''require_text "$SCENE_QML" 'function applyClickImpulse(x, y)' \\
    'shared scene has no distinct click impulse path' ''',
    '''require_text "$SCENE_QML" 'function applyClickField(x, y)' \\
    'shared scene has no distinct cohesive click field path' ''',
    "legacy click assertion",
)
test = replace_once(
    test,
    '''require_text "$SCENE_QML" 'NumberAnimation on pointerOffsetX' \\
    'pointer X displacement has no return-to-rest animation'
require_text "$SCENE_QML" 'NumberAnimation on pointerOffsetY' \\
    'pointer Y displacement has no return-to-rest animation' ''',
    '''require_text "$SCENE_QML" 'Behavior on pointerOffsetX {' \\
    'pointer X displacement has no smooth response/return behavior'
require_text "$SCENE_QML" 'Behavior on pointerOffsetY {' \\
    'pointer Y displacement has no smooth response/return behavior' ''',
    "legacy return-animation assertions",
)
EFFECTS_TEST.write_text(test)
