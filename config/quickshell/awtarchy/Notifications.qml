pragma Singleton
pragma ComponentBehavior: Bound

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

    function synchronousKey(notification) {
        if (!notification || !notification.hints)
            return "";
        const value = notification.hints["x-canonical-private-synchronous"];
        return value === undefined || value === null ? "" : String(value);
    }

    function replaceSynchronous(notification) {
        const key = synchronousKey(notification);
        if (key.length === 0)
            return;

        const values = [...server.trackedNotifications.values];
        for (let i = 0; i < values.length; ++i) {
            if (values[i] !== notification && synchronousKey(values[i]) === key)
                values[i].expire();
        }
    }

    function timeoutFor(notification) {
        if (!notification)
            return 0;

        const requested = Number(notification.expireTimeout || 0);
        const appName = String(notification.appName || "").toLowerCase();
        const isSynchronous = synchronousKey(notification).length > 0;

        // Hyprland mode/submap messages are status feedback, not persistent
        // application notifications. Keep them visible briefly, then clear them.
        if (appName === "hyprland")
            return 2.0;

        const systemTransient = isSynchronous
            || notification.transient
            || appName === "hypr-ddc-brightness";

        if (systemTransient)
            return requested > 0 ? Math.min(2.2, requested) : 2.0;
        return requested > 0 ? requested : 0;
    }

    function activateOrDismiss(notification) {
        if (!notification)
            return;

        const actions = notification.actions || [];
        for (let i = 0; i < actions.length; ++i) {
            if (actions[i].identifier === "default") {
                const resident = notification.resident;
                actions[i].invoke();
                if (resident)
                    notification.dismiss();
                return;
            }
        }

        notification.dismiss();
    }

    FileView {
        id: dndFile
        path: root.dndPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: root.dnd = text().trim() === "1"
        onFileChanged: reload()
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
        actionsSupported: true
        actionIconsSupported: false
        persistenceSupported: true
        keepOnReload: true

        onNotification: notification => {
            if (root.dnd) {
                notification.dismiss();
                return;
            }

            root.replaceSynchronous(notification);
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

        readonly property bool barVisibleHere: screen && BarState.enabledFor(screen.name)
        readonly property string barPositionHere: screen ? BarState.positionFor(screen.name) : "top"

        anchors {
            top: true
            right: true
        }
        margins {
            top: popupWindow.barVisibleHere && popupWindow.barPositionHere === "top" ? 38 : 10
            right: popupWindow.barVisibleHere && popupWindow.barPositionHere === "right" ? 46 : 10
        }

        implicitWidth: 340
        implicitHeight: Math.min(560, notificationColumn.implicitHeight)

        Column {
            id: notificationColumn
            width: parent.width
            spacing: 6

            Repeater {
                model: server.trackedNotifications

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    width: notificationColumn.width
                    height: Math.max(64, cardContent.implicitHeight + 16)
                    color: Theme.popupBackground
                    border.width: 1
                    border.color: Theme.active
                    radius: 0

                    readonly property real timeoutSeconds: root.timeoutFor(modelData)

                    Timer {
                        running: card.timeoutSeconds > 0
                        interval: Math.max(500, card.timeoutSeconds * 1000)
                        repeat: false
                        onTriggered: card.modelData.expire()
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.activateOrDismiss(card.modelData)
                    }

                    ColumnLayout {
                        id: cardContent
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            IconImage {
                                id: notificationIcon
                                visible: Boolean(source && source.toString().length > 0)
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                implicitSize: 34
                                source: card.modelData.image || (card.modelData.appIcon ? Quickshell.iconPath(card.modelData.appIcon, true) : "")
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    Layout.fillWidth: true
                                    text: card.modelData.summary || "Notification"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
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
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: card.modelData.actions.length > 0
                            spacing: 5

                            Repeater {
                                model: card.modelData.actions

                                delegate: Rectangle {
                                    id: actionButton
                                    required property var modelData
                                    visible: modelData.text && modelData.text.length > 0 && modelData.identifier !== "default"
                                    Layout.preferredHeight: visible ? 24 : 0
                                    Layout.preferredWidth: visible ? Math.max(64, actionText.implicitWidth + 16) : 0
                                    color: actionMouse.containsMouse ? Theme.focus : Theme.active
                                    border.width: 0
                                    radius: 0

                                    Text {
                                        id: actionText
                                        anchors.centerIn: parent
                                        text: actionButton.modelData.text || ""
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }

                                    MouseArea {
                                        id: actionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: mouse => {
                                            mouse.accepted = true;
                                            actionButton.modelData.invoke();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
