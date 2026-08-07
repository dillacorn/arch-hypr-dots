pragma Singleton

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Widgets

Singleton {
    id: root

    property bool dnd: false
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
    readonly property string dndPath: cacheHome + "/awtarchy/quickshell-dnd"

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0] : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function setDnd(value) {
        dnd = value;
        dndFile.setText(value ? "1\n" : "0\n");
        if (value)
            dismissAll();
    }

    function toggleDnd() { setDnd(!dnd); }

    function dismissFirst() {
        const values = server.trackedNotifications.values;
        if (values.length > 0)
            values[0].dismiss();
    }

    function dismissAll() {
        const values = [...server.trackedNotifications.values];
        for (let i = 0; i < values.length; ++i)
            values[i].dismiss();
    }

    FileView {
        id: dndFile
        path: root.dndPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: root.dnd = text().trim() === "1"
        onFileChanged: {
            reload();
            root.dnd = text().trim() === "1";
        }
    }

    IpcHandler {
        target: "notifications"
        function toggleDnd(): void { root.toggleDnd(); }
        function enable(): void { root.setDnd(false); }
        function disable(): void { root.setDnd(true); }
        function dismissFirst(): void { root.dismissFirst(); }
        function dismissAll(): void { root.dismissAll(); }
        function dndEnabled(): bool { return root.dnd; }
    }

    NotificationServer {
        id: server
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        actionsSupported: false
        persistenceSupported: true
        keepOnReload: true

        onNotification: notification => {
            if (root.dnd) {
                notification.dismiss();
                return;
            }
            notification.tracked = true;
            const target = root.focusedScreen();
            if (target)
                popupWindow.screen = target;
        }
    }

    PanelWindow {
        id: popupWindow
        visible: !root.dnd && server.trackedNotifications.values.length > 0
        color: "transparent"
        focusable: false
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.right: true
        margins.top: 10
        margins.right: 10
        implicitWidth: 380
        implicitHeight: Math.min(700, notificationColumn.implicitHeight)

        Column {
            id: notificationColumn
            width: parent.width
            spacing: 8

            Repeater {
                model: server.trackedNotifications

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    width: notificationColumn.width
                    height: Math.max(86, content.implicitHeight + 20)
                    color: Theme.popupBackground
                    border.width: 1
                    border.color: Theme.active
                    radius: 0

                    Timer {
                        running: card.modelData.expireTimeout > 0
                        interval: Math.max(1000, card.modelData.expireTimeout * 1000)
                        repeat: false
                        onTriggered: card.modelData.expire()
                    }

                    RowLayout {
                        id: content
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        IconImage {
                            visible: source.toString().length > 0
                            Layout.preferredWidth: visible ? 42 : 0
                            Layout.preferredHeight: visible ? 42 : 0
                            implicitSize: 42
                            source: card.modelData.image || (card.modelData.appIcon ? Quickshell.iconPath(card.modelData.appIcon, true) : "")
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.summary || "Notification"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: card.modelData.body || ""
                                textFormat: Text.PlainText
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                wrapMode: Text.Wrap
                                maximumLineCount: 5
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            text: "×"
                            color: Theme.foreground
                            font.pixelSize: 20

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -8
                                onClicked: card.modelData.dismiss()
                            }
                        }
                    }
                }
            }
        }
    }
}
