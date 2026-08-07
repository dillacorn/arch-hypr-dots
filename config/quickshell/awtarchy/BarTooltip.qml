import QtQuick
import Quickshell

Item {
    id: root

    required property Item anchorItem
    property string text: ""
    property bool hovered: false
    property bool vertical: false
    property int delay: 350

    implicitWidth: 0
    implicitHeight: 0
    visible: false

    onHoveredChanged: {
        if (hovered && text.length > 0) {
            hideTimer.stop();
            showTimer.restart();
        } else {
            showTimer.stop();
            hideTimer.restart();
        }
    }

    onTextChanged: {
        if (text.length === 0) {
            showTimer.stop();
            popup.visible = false;
        }
    }

    Timer {
        id: showTimer
        interval: root.delay
        repeat: false
        onTriggered: {
            if (root.hovered && root.text.length > 0) {
                popup.anchor.updateAnchor();
                popup.visible = true;
            }
        }
    }

    Timer {
        id: hideTimer
        interval: 40
        repeat: false
        onTriggered: popup.visible = false
    }

    PopupWindow {
        id: popup
        visible: false
        color: "transparent"
        surfaceFormat.opaque: false
        implicitWidth: Math.min(360, Math.max(72, tooltipText.implicitWidth + 18))
        implicitHeight: Math.max(28, tooltipText.implicitHeight + 10)

        // Tooltips are visual-only. They must never steal clicks from the bar
        // or the application behind them.
        mask: Region { width: 0; height: 0 }

        anchor.item: root.anchorItem
        anchor.edges: root.vertical
            ? Edges.Top | Edges.Right
            : Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.All

        Rectangle {
            anchors.fill: parent
            color: Theme.background
            radius: 0

            Text {
                id: tooltipText
                anchors.centerIn: parent
                text: root.text
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
