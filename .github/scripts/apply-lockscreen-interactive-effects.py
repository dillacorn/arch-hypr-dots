#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one replacement target, found {count}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


APP_STATE = "config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE = "config/quickshell/awtarchy/BarState.qml"
QUICK_SETTINGS = "config/quickshell/awtarchy/QuickSettings.qml"
SURFACE = "config/quickshell/awtarchy-lock/LockSurface.qml"
RUNTIME_TEST = "tests/test-quickshell-lockscreen-runtime-regressions.sh"
ANIMATION_TEST = "tests/test-quickshell-lockscreen-animation-preference.sh"

# Persist only the four approved lockscreen booleans through the existing state writer.
old = '''set_lockscreen_animation() {
    local value="$1"
    validate_lockscreen_animation "$value"
    new_tmp
    jq --arg value "$value" '.lockscreen_animation = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}
'''
new = old + '''
set_lockscreen_option() {
    local field="$1" value="$2" label="$3" enabled
    case "$field" in
        lockscreen_audio_reactive|lockscreen_show_time|lockscreen_show_date|lockscreen_show_username) ;;
        *)
            printf 'unsupported lockscreen option: %s\\n' "$field" >&2
            exit 2
            ;;
    esac
    enabled="$(parse_bool "$value" "$label")"
    new_tmp
    jq --arg field "$field" --argjson enabled "$enabled" '.[$field] = $enabled' \
        "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}
'''
replace_once(APP_STATE, old, new)

old = '''    set-lockscreen-animation)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_animation "$2"
        ;;
'''
new = old + '''    set-lockscreen-audio-reactive)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_option lockscreen_audio_reactive "$2" 'lockscreen audio reactive'
        ;;
    set-lockscreen-show-time)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_option lockscreen_show_time "$2" 'lockscreen show time'
        ;;
    set-lockscreen-show-date)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_option lockscreen_show_date "$2" 'lockscreen show date'
        ;;
    set-lockscreen-show-username)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_option lockscreen_show_username "$2" 'lockscreen show username'
        ;;
'''
replace_once(APP_STATE, old, new)

old = 'set-lockscreen-animation <random|swarm|edges|center|split|off>|set-workspace-numbers'
new = ('set-lockscreen-animation <random|swarm|edges|center|split|off>|'
       'set-lockscreen-audio-reactive <true|false>|set-lockscreen-show-time <true|false>|'
       'set-lockscreen-show-date <true|false>|set-lockscreen-show-username <true|false>|'
       'set-workspace-numbers')
replace_once(APP_STATE, old, new)

# Extend the existing shared BarState defaults/readers rather than adding another state owner.
old = '''            update_notifications_enabled: true,
            lockscreen_animation: "split",
            monitors: {},
'''
new = '''            update_notifications_enabled: true,
            lockscreen_animation: "split",
            lockscreen_audio_reactive: true,
            lockscreen_show_time: false,
            lockscreen_show_date: false,
            lockscreen_show_username: false,
            monitors: {},
'''
replace_once(BAR_STATE, old, new)

old = '''    function lockscreenAnimationPreference() {
        const value = String(data().lockscreen_animation || "split");
        for (const preset of lockscreenAnimationPresets) {
            if (preset.key === value)
                return value;
        }
        return "split";
    }
'''
new = old + '''
    function lockscreenBooleanPreference(field, fallback) {
        const value = data()[field];
        return typeof value === "boolean" ? value : fallback;
    }

    function lockscreenAudioReactiveEnabled() {
        return lockscreenBooleanPreference("lockscreen_audio_reactive", true);
    }

    function lockscreenShowTime() {
        return lockscreenBooleanPreference("lockscreen_show_time", false);
    }

    function lockscreenShowDate() {
        return lockscreenBooleanPreference("lockscreen_show_date", false);
    }

    function lockscreenShowUsername() {
        return lockscreenBooleanPreference("lockscreen_show_username", false);
    }
'''
replace_once(BAR_STATE, old, new)

# Put the four compact controls immediately below the existing animation selector.
old = '''                                Flow {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: childrenRect.height
                                    spacing: 5

                                    Repeater {
                                        model: BarState.lockscreenAnimationPresets

                                        SettingsButton {
                                            required property var modelData
                                            label: String(modelData.label)
                                            active: BarState.lockscreenAnimationPreference()
                                                === String(modelData.key)
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueStateCommand([
                                                "set-lockscreen-animation", String(modelData.key)
                                            ])
                                        }
                                    }
                                }
'''
new = old + '''
                                Text {
                                    Layout.fillWidth: true
                                    text: "Lockscreen Options"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(9)
                                    font.bold: true
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2
                                    columnSpacing: 8
                                    rowSpacing: 4

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Audio Reactive"
                                        color: BarState.lockscreenAnimationPreference() !== "off"
                                            ? Theme.foreground : Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(9)
                                    }
                                    SettingsButton {
                                        label: BarState.lockscreenAudioReactiveEnabled() ? "On" : "Off"
                                        active: BarState.lockscreenAudioReactiveEnabled()
                                            && BarState.lockscreenAnimationPreference() !== "off"
                                        available: BarState.lockscreenAnimationPreference() !== "off"
                                        textSize: root.scaledText(9)
                                        onClicked: root.queueStateCommand([
                                            "set-lockscreen-audio-reactive",
                                            BarState.lockscreenAudioReactiveEnabled() ? "false" : "true"
                                        ])
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Time"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(9)
                                    }
                                    SettingsButton {
                                        label: BarState.lockscreenShowTime() ? "On" : "Off"
                                        active: BarState.lockscreenShowTime()
                                        textSize: root.scaledText(9)
                                        onClicked: root.queueStateCommand([
                                            "set-lockscreen-show-time",
                                            BarState.lockscreenShowTime() ? "false" : "true"
                                        ])
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Date"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(9)
                                    }
                                    SettingsButton {
                                        label: BarState.lockscreenShowDate() ? "On" : "Off"
                                        active: BarState.lockscreenShowDate()
                                        textSize: root.scaledText(9)
                                        onClicked: root.queueStateCommand([
                                            "set-lockscreen-show-date",
                                            BarState.lockscreenShowDate() ? "false" : "true"
                                        ])
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Username"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(9)
                                    }
                                    SettingsButton {
                                        label: BarState.lockscreenShowUsername() ? "On" : "Off"
                                        active: BarState.lockscreenShowUsername()
                                        textSize: root.scaledText(9)
                                        onClicked: root.queueStateCommand([
                                            "set-lockscreen-show-username",
                                            BarState.lockscreenShowUsername() ? "false" : "true"
                                        ])
                                    }
                                }
'''
replace_once(QUICK_SETTINGS, old, new)

# LockSurface: import local environment access and receive shell-owned preferences/audio.
replace_once(SURFACE,
'''import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
''',
'''import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
''')

replace_once(SURFACE,
'''    required property bool unlocking
    required property string animationPreference
    required property int randomFormationMode

    color: "#000000"
''',
'''    required property bool unlocking
    required property string animationPreference
    required property int randomFormationMode
    required property real audioLow
    required property real audioMid
    required property real audioHigh
    required property real audioOverall
    required property bool showTime
    required property bool showDate
    required property bool showUsername

    color: "#000000"
''')

replace_once(SURFACE,
'''    readonly property int formationMode: animationPreference === "swarm" ? 0
        : animationPreference === "edges" ? 1
        : animationPreference === "center" ? 2
        : animationPreference === "split" ? 3
        : randomFormationMode

    property bool entered: false

    function submitPassword() {
''',
'''    readonly property int formationMode: animationPreference === "swarm" ? 0
        : animationPreference === "edges" ? 1
        : animationPreference === "center" ? 2
        : animationPreference === "split" ? 3
        : randomFormationMode
    readonly property bool interactiveEffectsEnabled: root.animationPreference !== "off"
    readonly property int ghostTrailLength: 6
    readonly property int pointerUpdateIntervalMs: 16
    readonly property int cursorFadeDelayMs: 180
    readonly property int cursorFadeDurationMs: 320
    readonly property real pointerInfluenceRadius: 72 * root.uiScale
    readonly property real pointerDisplacementCap: 24 * root.uiScale
    readonly property real audioDisplacementCap: 6 * root.uiScale
    readonly property real pointerMovementThreshold: 3 * root.uiScale
    readonly property bool metadataVisible: root.showTime || root.showDate || root.showUsername
    readonly property string usernameText: root.showUsername ? Quickshell.env("USER") : ""

    property bool entered: false
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
        if (!interactiveEffectsEnabled)
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
        if (!interactiveEffectsEnabled)
            return;

        const now = Date.now();
        const hasPrevious = lastPointerX >= 0 && lastPointerY >= 0
            && lastPointerSampleTime > 0;
        const dx = hasPrevious ? x - lastPointerX : 0;
        const dy = hasPrevious ? y - lastPointerY : 0;
        const distance = Math.sqrt(dx * dx + dy * dy);
        const elapsed = hasPrevious ? Math.max(1, now - lastPointerSampleTime) : 1;
        const speed = hasPrevious ? distance * 1000 / elapsed : 0;

        if (!hasPrevious || distance >= pointerMovementThreshold)
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
''')

replace_once(SURFACE,
'''    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        cursorShape: Qt.BlankCursor
        onClicked: password.forceActiveFocus()
        onWheel: wheel => { wheel.accepted = true; }
    }
''',
'''    MouseArea {
        id: pointerArea
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        cursorShape: Qt.BlankCursor
        onPositionChanged: mouse => root.handlePointerMotion(mouse.x, mouse.y)
        onClicked: password.forceActiveFocus()
        onWheel: wheel => { wheel.accepted = true; }
    }
''')

replace_once(SURFACE,
'''            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: root.wordmarkColumns * root.wordmarkCellWidth
''',
'''            Item {
                id: wordmarkItem
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: root.wordmarkColumns * root.wordmarkCellWidth
''')

replace_once(SURFACE,
'''                                readonly property real finalCellX: columnIndex * root.wordmarkCellWidth
                                readonly property real finalCellY: wordmarkRow.rowIndex
                                    * root.wordmarkCellHeight

                                // These values intentionally have no reactive dependencies: each
''',
'''                                readonly property real finalCellX: columnIndex * root.wordmarkCellWidth
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
                                readonly property real audioEnvelope: root.interactiveEffectsEnabled
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

                                // These values intentionally have no reactive dependencies: each
''')

replace_once(SURFACE,
'''                                property real formationProgress:
                                    root.animationPreference === "off" ? 1 : 0

                                x: finalCellX
                                    + (1 - formationProgress) * startX
                                    + Math.sin(Math.PI * wordmarkCell.formationProgress) * curveX
                                y: (1 - formationProgress) * startY
                                    + Math.sin(Math.PI * wordmarkCell.formationProgress) * curveY
                                width: root.wordmarkCellWidth
''',
'''                                property real formationProgress:
                                    root.animationPreference === "off" ? 1 : 0

                                function applyPointerImpulse(localX, localY, speed) {
                                    if (!wordmarkCell.isFilledGlyph
                                            || wordmarkCell.formationProgress < 0.96
                                            || !root.interactiveEffectsEnabled)
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
                                    + pointerOffsetX + audioOffsetX
                                y: (1 - formationProgress) * startY
                                    + Math.sin(Math.PI * wordmarkCell.formationProgress) * curveY
                                    + pointerOffsetY + audioOffsetY
                                width: root.wordmarkCellWidth
''')

replace_once(SURFACE,
'''                                SequentialAnimation on formationProgress {
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
''',
'''                                SequentialAnimation on formationProgress {
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
''')

# Add optional metadata between wordmark and password input.
replace_once(SURFACE,
'''            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.round(320 * root.uiScale)
                Layout.preferredHeight: Math.round(42 * root.uiScale)
''',
'''            ColumnLayout {
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
            }

            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.round(320 * root.uiScale)
                Layout.preferredHeight: Math.round(42 * root.uiScale)
''')

# Add surface-local ghost rendering and timers after the central visual stack.
replace_once(SURFACE,
'''        }
    }

    Connections {
        target: root.auth
''',
'''        }

        Item {
            anchors.fill: parent
            z: 100
            visible: root.interactiveEffectsEnabled && root.ghostOpacity > 0

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
    }

    Timer {
        interval: 33
        repeat: true
        running: root.interactiveEffectsEnabled && root.audioOverall > 0.01
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
''')

replace_once(SURFACE,
'''    Component.onCompleted: {
        root.entered = true;
        Qt.callLater(() => password.forceActiveFocus());
    }
''',
'''    Component.onCompleted: {
        root.updateClockText();
        root.entered = true;
        Qt.callLater(() => password.forceActiveFocus());
    }
''')

# Historical minimal-default guards now assert optional metadata instead of forbidding it.
old = '''reject_text "$SURFACE_QML" 'property string timeText' \\
    'lockscreen still owns clock state'
reject_text "$SURFACE_QML" 'property string dateText' \\
    'lockscreen still owns date state'
reject_text "$SURFACE_QML" 'Quickshell.env("USER")' \\
    'lockscreen still displays the username'
'''
new = '''require_text "$SURFACE_QML" 'required property bool showTime' \\
    'lockscreen does not gate optional time display'
require_text "$SURFACE_QML" 'required property bool showDate' \\
    'lockscreen does not gate optional date display'
require_text "$SURFACE_QML" 'required property bool showUsername' \\
    'lockscreen does not gate optional username display'
require_text "$SURFACE_QML" 'readonly property bool metadataVisible: root.showTime || root.showDate || root.showUsername' \\
    'lockscreen metadata does not collapse when every local-info option is disabled'
require_text "$SURFACE_QML" 'visible: root.showTime' \\
    'time metadata is not optional'
require_text "$SURFACE_QML" 'visible: root.showDate' \\
    'date metadata is not optional'
require_text "$SURFACE_QML" 'visible: root.showUsername' \\
    'username metadata is not optional'
'''
replace_once(RUNTIME_TEST, old, new)

# Keep the existing Off preference as the explicit master suppression contract.
old = '''require_text "$SURFACE_QML" 'root.animationPreference !== "off"' \\
    'Off does not suppress particle formation animation'
'''
new = old + '''require_text "$SURFACE_QML" 'readonly property bool interactiveEffectsEnabled: root.animationPreference !== "off"' \\
    'Off does not suppress ghost cursor and pointer physics'
require_text "$SHELL_QML" 'enabled: root.lockAudioReactive && root.lockAnimationPreference !== "off"' \\
    'Off does not suppress the lockscreen audio analyzer'
'''
replace_once(ANIMATION_TEST, old, new)

print("Applied lockscreen interactive effects patch")
