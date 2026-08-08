import QtQuick

Item {
    id: root

    required property var flickable
    property int minimumThumbHeight: 28
    property int trackWidth: 7

    readonly property real minimumContentY: {
        if (!flickable)
            return 0;
        return flickable.originY !== undefined ? flickable.originY : 0;
    }
    readonly property real maximumContentY: flickable
        ? Math.max(minimumContentY, minimumContentY + flickable.contentHeight - flickable.height)
        : minimumContentY
    readonly property bool needed: flickable
        && flickable.height > 0
        && flickable.contentHeight > flickable.height + 0.5

    visible: needed
    width: visible ? 13 : 0

    Rectangle {
        id: track
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        anchors.rightMargin: 3
        width: root.trackWidth
        radius: width / 2
        color: Theme.subtleHover

        Rectangle {
            id: thumb
            width: parent.width
            height: {
                if (!root.flickable || root.flickable.contentHeight <= 0)
                    return parent.height;
                return Math.min(parent.height,
                    Math.max(root.minimumThumbHeight,
                        parent.height * root.flickable.height / root.flickable.contentHeight));
            }
            y: {
                const scrollRange = root.maximumContentY - root.minimumContentY;
                const travel = Math.max(0, track.height - height);
                if (scrollRange <= 0 || travel <= 0)
                    return 0;
                const ratio = (root.flickable.contentY - root.minimumContentY) / scrollRange;
                return travel * Math.max(0, Math.min(1, ratio));
            }
            radius: width / 2
            color: scrollbarMouse.pressed || scrollbarMouse.containsMouse
                ? Theme.foreground
                : Theme.muted
        }

        MouseArea {
            id: scrollbarMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            preventStealing: true
            property real grabOffset: 0

            function setFromPointer(pointerY) {
                const travel = Math.max(0, track.height - thumb.height);
                const scrollRange = root.maximumContentY - root.minimumContentY;
                if (travel <= 0 || scrollRange <= 0)
                    return;

                const thumbY = Math.max(0, Math.min(travel, pointerY - grabOffset));
                root.flickable.contentY = root.minimumContentY + (thumbY / travel) * scrollRange;
            }

            onPressed: mouse => {
                root.flickable.cancelFlick();

                if (mouse.y >= thumb.y && mouse.y <= thumb.y + thumb.height) {
                    grabOffset = mouse.y - thumb.y;
                } else {
                    grabOffset = thumb.height / 2;
                    setFromPointer(mouse.y);
                }
                mouse.accepted = true;
            }

            onPositionChanged: mouse => {
                if (pressed)
                    setFromPointer(mouse.y);
            }

            onWheel: wheel => {
                const target = root.flickable.contentY - wheel.angleDelta.y;
                root.flickable.contentY = Math.max(root.minimumContentY,
                    Math.min(root.maximumContentY, target));
                wheel.accepted = true;
            }
        }
    }
}
