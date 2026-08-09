pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root

    required property var notification
    property int textScale: 100
    property int iconScale: 100
    property bool showDismiss: true
    property int bodyLineLimit: 5

    signal activated()
    signal dismissRequested()
    signal notificationClosed()

    implicitHeight: Math.max(68, content.implicitHeight + 16)
    height: implicitHeight
    color: Theme.popupBackground
    border.width: 1
    border.color: Theme.active
    radius: 0

    Connections {
        target: root.notification
        function onClosed() { root.notificationClosed(); }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.activated()
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 8
        anchors.rightMargin: root.showDismiss ? 34 : 8
        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IconImage {
                id: notificationIcon
                readonly property int scaledSize: Math.max(22,
                    Math.min(64, Math.round(34 * root.iconScale / 100)))
                visible: Boolean(source && source.toString().length > 0)
                Layout.preferredWidth: visible ? scaledSize : 0
                Layout.preferredHeight: visible ? scaledSize : 0
                implicitSize: scaledSize
                source: root.notification.image
                    || (root.notification.appIcon
                        ? Quickshell.iconPath(root.notification.appIcon, true) : "")
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    text: root.notification.summary || "Notification"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(9, Math.round(13 * root.textScale / 100))
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.notification.body || ""
                    textFormat: Text.PlainText
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(8, Math.round(12 * root.textScale / 100))
                    wrapMode: Text.Wrap
                    maximumLineCount: root.bodyLineLimit
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.notification.appName || ""
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(7, Math.round(9 * root.textScale / 100))
                    elide: Text.ElideRight
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? childrenRect.height : 0
            visible: root.notification.actions.length > 0
            spacing: 5

            Repeater {
                model: root.notification.actions

                delegate: Rectangle {
                    id: actionButton
                    required property var modelData
                    visible: modelData.text && modelData.text.length > 0
                        && modelData.identifier !== "default"
                    width: visible ? Math.max(64, actionText.implicitWidth + 16) : 0
                    height: visible ? 24 : 0
                    color: actionMouse.containsMouse ? Theme.focus : Theme.active
                    border.width: 0
                    radius: 0

                    Text {
                        id: actionText
                        anchors.centerIn: parent
                        width: parent.width - 10
                        text: actionButton.modelData.text || ""
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.max(8, Math.round(11 * root.textScale / 100))
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            mouse.accepted = true;
                            actionButton.modelData.invoke();
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        visible: root.showDismiss
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 6
        width: 24
        height: 24
        color: dismissMouse.containsMouse ? Theme.focus : "transparent"
        border.width: 0
        z: 3

        Text {
            anchors.centerIn: parent
            text: "×"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 14
        }

        MouseArea {
            id: dismissMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                mouse.accepted = true;
                root.dismissRequested();
            }
        }
    }
}
