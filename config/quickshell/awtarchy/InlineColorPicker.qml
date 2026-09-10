import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: root

    property string colorValue: "#ffffff"
    property real hue: 0
    property real saturation: 0
    property real value: 1
    property bool syncing: false

    signal colorEdited(string hex)

    implicitWidth: 320
    implicitHeight: 142

    function clamp01(number) {
        return Math.max(0, Math.min(1, Number(number)));
    }

    function componentHex(number) {
        const text = Math.max(0, Math.min(255, Math.round(number))).toString(16);
        return text.length < 2 ? "0" + text : text;
    }

    function hsvHex(h, s, v) {
        h = ((Number(h) % 1) + 1) % 1;
        s = clamp01(s);
        v = clamp01(v);
        const sector = h * 6;
        const index = Math.floor(sector);
        const fraction = sector - index;
        const p = v * (1 - s);
        const q = v * (1 - fraction * s);
        const t = v * (1 - (1 - fraction) * s);
        let r = v;
        let g = t;
        let b = p;
        switch (index % 6) {
        case 0: r = v; g = t; b = p; break;
        case 1: r = q; g = v; b = p; break;
        case 2: r = p; g = v; b = t; break;
        case 3: r = p; g = q; b = v; break;
        case 4: r = t; g = p; b = v; break;
        case 5: r = v; g = p; b = q; break;
        }
        return ("#" + componentHex(r * 255) + componentHex(g * 255)
            + componentHex(b * 255)).toLowerCase();
    }

    function hexHsv(hex) {
        const normalized = String(hex || "").trim().toLowerCase();
        if (!/^#[0-9a-f]{6}$/.test(normalized))
            return null;
        const r = parseInt(normalized.slice(1, 3), 16) / 255;
        const g = parseInt(normalized.slice(3, 5), 16) / 255;
        const b = parseInt(normalized.slice(5, 7), 16) / 255;
        const maxValue = Math.max(r, g, b);
        const minValue = Math.min(r, g, b);
        const delta = maxValue - minValue;
        let nextHue = 0;
        if (delta > 0) {
            if (maxValue === r)
                nextHue = ((g - b) / delta) % 6;
            else if (maxValue === g)
                nextHue = (b - r) / delta + 2;
            else
                nextHue = (r - g) / delta + 4;
            nextHue /= 6;
            if (nextHue < 0)
                nextHue += 1;
        }
        return ({
            hue: nextHue,
            saturation: maxValue <= 0 ? 0 : delta / maxValue,
            value: maxValue
        });
    }

    function setHex(hex, emitChange) {
        const normalized = String(hex || "").trim().toLowerCase();
        const hsv = hexHsv(normalized);
        if (!hsv)
            return false;
        syncing = true;
        hue = hsv.hue;
        saturation = hsv.saturation;
        value = hsv.value;
        colorValue = normalized;
        syncing = false;
        if (emitChange)
            colorEdited(normalized);
        return true;
    }

    function commitPicker() {
        const next = hsvHex(hue, saturation, value);
        syncing = true;
        colorValue = next;
        syncing = false;
        colorEdited(next);
    }

    onColorValueChanged: {
        if (!syncing)
            setHex(colorValue, false);
    }

    Component.onCompleted: setHex(colorValue, false)

    ColumnLayout {
        anchors.fill: parent
        spacing: 5

        Item {
            id: palette
            Layout.fillWidth: true
            Layout.preferredHeight: 88

            Rectangle {
                anchors.fill: parent
                color: Qt.hsva(root.hue, 1, 1, 1)
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#ffffffff" }
                    GradientStop { position: 1; color: "#00ffffff" }
                }
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: "#00000000" }
                    GradientStop { position: 1; color: "#ff000000" }
                }
            }

            Rectangle {
                width: 10
                height: 10
                radius: 5
                x: Math.max(-5, Math.min(palette.width - 5,
                    root.saturation * palette.width - width / 2))
                y: Math.max(-5, Math.min(palette.height - 5,
                    (1 - root.value) * palette.height - height / 2))
                color: "transparent"
                border.width: 2
                border.color: root.value > 0.55 ? "#000000" : "#ffffff"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                function updateColor(mouse) {
                    root.saturation = root.clamp01(mouse.x / Math.max(1, width));
                    root.value = root.clamp01(1 - mouse.y / Math.max(1, height));
                    root.commitPicker();
                }
                onPressed: mouse => updateColor(mouse)
                onPositionChanged: mouse => {
                    if (pressed)
                        updateColor(mouse);
                }
            }
        }

        Item {
            id: hueBar
            Layout.fillWidth: true
            Layout.preferredHeight: 14

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.00; color: "#ff0000" }
                    GradientStop { position: 0.17; color: "#ffff00" }
                    GradientStop { position: 0.33; color: "#00ff00" }
                    GradientStop { position: 0.50; color: "#00ffff" }
                    GradientStop { position: 0.67; color: "#0000ff" }
                    GradientStop { position: 0.83; color: "#ff00ff" }
                    GradientStop { position: 1.00; color: "#ff0000" }
                }
            }

            Rectangle {
                width: 4
                height: parent.height + 4
                y: -2
                x: Math.max(-2, Math.min(hueBar.width - 2,
                    root.hue * hueBar.width - width / 2))
                color: "#ffffff"
                border.width: 1
                border.color: "#000000"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function updateHue(mouse) {
                    root.hue = root.clamp01(mouse.x / Math.max(1, width));
                    root.commitPicker();
                }
                onPressed: mouse => updateHue(mouse)
                onPositionChanged: mouse => {
                    if (pressed)
                        updateHue(mouse);
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                color: root.colorValue
                border.width: 1
                border.color: "#808080"
            }

            TextField {
                Layout.fillWidth: true
                placeholderText: "#RRGGBB"
                text: root.colorValue
                selectByMouse: true
                onEditingFinished: root.setHex(text, true)
            }
        }
    }
}
