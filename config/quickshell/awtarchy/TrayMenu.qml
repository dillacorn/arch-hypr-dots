pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets

Item {
    id: root

    required property Item anchorItem
    property var menu: null
    property string barPosition: "top"
    property var menuStack: []
    property var currentMenu: null

    visible: false
    implicitWidth: 0
    implicitHeight: 0

    function open() {
        if (!menu)
            return;
        menuStack = [];
        currentMenu = menu;
        popup.anchor.updateAnchor();
        popup.visible = true;
    }

    function close() {
        popup.visible = false;
        menuStack = [];
        currentMenu = null;
    }

    function openChild(entry) {
        if (!entry || !entry.hasChildren)
            return;
        menuStack = [...menuStack, currentMenu];
        currentMenu = entry;
    }

    function goBack() {
        if (menuStack.length === 0)
            return;
        const stack = [...menuStack];
        currentMenu = stack.pop();
        menuStack = stack;
    }

    QsMenuOpener {
        id: opener
        menu: root.currentMenu
    }

    PopupWindow {
        id: popup
        visible: false
        color: "transparent"
        grabFocus: true
        implicitWidth: 270
        implicitHeight: Math.min(520, Math.max(36, menuList.contentHeight + 8))

        anchor.item: root.anchorItem
        anchor.edges: root.barPosition === "top"
            ? Edges.Bottom | Edges.Left
            : root.barPosition === "bottom"
                ? Edges.Top | Edges.Left
                : root.barPosition === "left"
                    ? Edges.Top | Edges.Right
                    : Edges.Top | Edges.Left
        anchor.gravity: root.barPosition === "bottom"
            ? Edges.Top | Edges.Right
            : root.barPosition === "right"
                ? Edges.Bottom | Edges.Left
                : Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.All

        onVisibleChanged: {
            if (!visible) {
                root.menuStack = [];
                root.currentMenu = null;
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.background
            border.width: 1
            border.color: Theme.active
            radius: 0

            ListView {
                id: menuList
                anchors.fill: parent
                anchors.margins: 4
                clip: true
                model: opener.children

                header: Rectangle {
                    width: menuList.width
                    height: root.menuStack.length > 0 ? 30 : 0
                    visible: height > 0
                    color: backMouse.containsMouse ? Theme.subtleHover : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "‹  Back"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: backMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.goBack()
                    }
                }

                delegate: Rectangle {
                    id: menuRow
                    required property var modelData
                    width: ListView.view.width
                    height: modelData.isSeparator ? 7 : 30
                    color: modelData.isSeparator
                        ? "transparent"
                        : (rowMouse.containsMouse && modelData.enabled ? Theme.subtleHover : "transparent")

                    Rectangle {
                        visible: menuRow.modelData.isSeparator
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        height: 1
                        color: Theme.focus
                    }

                    Row {
                        visible: !menuRow.modelData.isSeparator
                        anchors.fill: parent
                        anchors.leftMargin: 7
                        anchors.rightMargin: 7
                        spacing: 7

                        Item {
                            width: 16
                            height: parent.height

                            IconImage {
                                anchors.centerIn: parent
                                visible: menuRow.modelData.icon && menuRow.modelData.icon.toString().length > 0
                                implicitSize: 15
                                source: visible ? menuRow.modelData.icon : ""
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !parent.children[0].visible && menuRow.modelData.checkState === Qt.Checked
                                text: "✓"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                        }

                        Text {
                            width: parent.width - 16 - 14 - parent.spacing * 2
                            height: parent.height
                            text: menuRow.modelData.text || ""
                            color: menuRow.modelData.enabled ? Theme.foreground : Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            width: 14
                            height: parent.height
                            text: menuRow.modelData.hasChildren ? "›" : ""
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        enabled: !menuRow.modelData.isSeparator && menuRow.modelData.enabled
                        hoverEnabled: true
                        onClicked: {
                            if (menuRow.modelData.hasChildren) {
                                root.openChild(menuRow.modelData);
                            } else {
                                menuRow.modelData.triggered();
                                root.close();
                            }
                        }
                    }
                }
            }
        }
    }
}
