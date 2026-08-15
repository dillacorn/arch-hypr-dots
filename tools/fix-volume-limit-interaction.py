#!/usr/bin/env python3
from pathlib import Path


def read(path):
    return Path(path).read_text(encoding="utf-8")


def write(path, text):
    Path(path).write_text(text, encoding="utf-8")


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


# Quick Settings: brightness-style hover/click interaction for the max-volume track.
path = "config/quickshell/awtarchy/QuickSettings.qml"
text = read(path)
text = replace_once(
    text,
    '    property int brightnessHoverPercent: -1\n',
    '    property int brightnessHoverPercent: -1\n    property int outputVolumeHoverPercent: -1\n',
    "QuickSettings hover state",
)

anchor = '''    function clampHeight(value) {
        return Math.max(minimumPanelHeight, Math.min(maximumPanelHeight, Math.round(value)));
    }
'''
replacement = '''    function clampHeight(value) {
        return Math.max(minimumPanelHeight, Math.min(maximumPanelHeight, Math.round(value)));
    }

    function outputLimitForPosition(x, width) {
        if (width <= 0)
            return AudioLimitState.limitPercent;
        const ratio = Math.max(0, Math.min(1, x / width));
        const raw = AudioLimitState.minimumPercent
            + ratio * (AudioLimitState.maximumPercent - AudioLimitState.minimumPercent);
        return AudioLimitState.normalized(raw);
    }
'''
text = replace_once(text, anchor, replacement, "QuickSettings position mapping")

old_track = '''                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 24
                                        color: Theme.active
                                        border.width: 0

                                        Rectangle {
                                            width: parent.width * AudioLimitState.limitPercent
                                                / AudioLimitState.maximumPercent
                                            height: parent.height
                                            color: Theme.focus
                                        }
                                    }
'''
new_track = '''                                    Rectangle {
                                        id: outputVolumeTrack
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 24
                                        color: Theme.active
                                        border.width: 0

                                        Rectangle {
                                            width: parent.width
                                                * (AudioLimitState.limitPercent - AudioLimitState.minimumPercent)
                                                / (AudioLimitState.maximumPercent - AudioLimitState.minimumPercent)
                                            height: parent.height
                                            color: Theme.focus
                                        }

                                        Rectangle {
                                            visible: root.outputVolumeHoverPercent >= 0
                                            width: 46
                                            height: 21
                                            x: {
                                                const ratio = (root.outputVolumeHoverPercent
                                                    - AudioLimitState.minimumPercent)
                                                    / (AudioLimitState.maximumPercent
                                                        - AudioLimitState.minimumPercent);
                                                return Math.max(0, Math.min(parent.width - width,
                                                    parent.width * ratio - width / 2));
                                            }
                                            y: -25
                                            color: Theme.background
                                            border.width: 1
                                            border.color: Theme.focus
                                            z: 4

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.outputVolumeHoverPercent + "%"
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledText(9)
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onPositionChanged: mouse => root.outputVolumeHoverPercent
                                                = root.outputLimitForPosition(mouse.x, width)
                                            onExited: root.outputVolumeHoverPercent = -1
                                            onPressed: mouse => {
                                                root.outputVolumeHoverPercent
                                                    = root.outputLimitForPosition(mouse.x, width);
                                                AudioLimitState.setLimit(root.outputVolumeHoverPercent);
                                            }
                                        }
                                    }
'''
text = replace_once(text, old_track, new_track, "QuickSettings interactive track")
text = replace_once(
    text,
    '                                    text: "Global limit for Wiremix and bar volume scrolling · range 10–200%"\n',
    '                                    text: "Global limit for Wiremix and bar volume scrolling · click bar to set · range 10–200%"\n',
    "QuickSettings helper text",
)
write(path, text)


# Bar: use WirePlumber's relative volume command so amplification above 100% works.
path = "config/quickshell/awtarchy/Bar.qml"
text = read(path)
old = '''    function adjustAudio(delta) {
        const sink = Pipewire.defaultAudioSink;
        if (!sink || !sink.audio)
            return;
        sink.audio.volume = Math.max(0, Math.min(
            AudioLimitState.limitPercent / 100, sink.audio.volume + delta));
    }
'''
new = '''    function adjustAudio(delta) {
        if (delta === 0)
            return;
        const stepPercent = Math.max(1, Math.round(Math.abs(delta) * 100));
        const direction = delta > 0 ? "+" : "-";
        Quickshell.execDetached([
            "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@",
            String(stepPercent) + "%" + direction,
            "--limit", String(AudioLimitState.limitPercent / 100)
        ]);
    }
'''
text = replace_once(text, old, new, "Bar wpctl volume scrolling")
write(path, text)


# Audio limit: use wpctl when lowering an amplified output back under the configured limit.
path = "config/quickshell/awtarchy/AudioLimitState.qml"
text = read(path)
old = '''    function clampCurrentOutput() {
        const sink = Pipewire.defaultAudioSink;
        const maximum = limitPercent / 100;
        if (sink && sink.audio && sink.audio.volume > maximum)
            sink.audio.volume = maximum;
    }
'''
new = '''    function clampCurrentOutput() {
        const sink = Pipewire.defaultAudioSink;
        const maximum = limitPercent / 100;
        if (sink && sink.audio && sink.audio.volume > maximum) {
            Quickshell.execDetached([
                "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@",
                String(limitPercent) + "%"
            ]);
        }
    }
'''
text = replace_once(text, old, new, "AudioLimitState wpctl clamp")
write(path, text)


# Static regressions for both interaction and >100% scroll behavior.
path = "tests/test-quickshell-production-readiness.sh"
text = read(path)
anchor = '''assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/QuickSettings.qml" 'text: "Maximum output volume"'
'''
replacement = '''assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/QuickSettings.qml" 'text: "Maximum output volume"'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/QuickSettings.qml" 'property int outputVolumeHoverPercent: -1'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/QuickSettings.qml" 'function outputLimitForPosition(x, width)'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/QuickSettings.qml" 'AudioLimitState.setLimit(root.outputVolumeHoverPercent)'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/Bar.qml" '"wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@"'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/Bar.qml" '"--limit", String(AudioLimitState.limitPercent / 100)'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/AudioLimitState.qml" 'String(limitPercent) + "%"'
'''
text = replace_once(text, anchor, replacement, "production readiness volume assertions")
write(path, text)
