pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string monitorName: ""
    property var order: []
    property var hidden: []

    signal backRequested()
    signal moveRequested(string sectionId, int delta)
    signal visibilityRequested(string sectionId, bool visible)
    signal resetRequested()

    implicitHeight: 300

    function sectionLabel(sectionId) {
        const labels = {
            "brightness": "Brightness",
            "output-volume": "Maximum output volume",
            "power-mode": "Power Mode",
            "bar": "Bar",
            "display-effects": "Night Light + Vibrance",
            "screen-share-guard": "Screen Share Guard",
            "submap": "Hyprland Submap",
            "wallpaper": "Wallpaper Picker",
            "awtarchy": "Awtarchy",
            "smtty": "smtty",
            "scheduler": "sched-ext",
            "numlock": "Num Lock",
            "title-bars": "Title Bars"
        };
        return labels[sectionId] || sectionId;
    }

    function sectionVisible(sectionId) {
        return (hidden || []).indexOf(sectionId) < 0;
    }

    function visibleCount() {
        let count = 0;
        for (const sectionId of order || []) {
            if (sectionVisible(sectionId))
                count++;
        }
        return count;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.active
        border.width: 1
        border.color: Theme.focus

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 5

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 27
                spacing: 6

                SettingsButton {
                    label: "Back"
                    textSize: 9
                    onClicked: root.backRequested()
                }

                Text {
                    Layout.fillWidth: true
                    text: "Quick Settings Layout · " + root.monitorName
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    elide: Text.ElideRight
                }

                SettingsButton {
                    label: "Stock Layout"
                    textSize: 9
                    onClicked: root.resetRequested()
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Reorder sections or hide what this display does not need. Changes preview immediately; use the disk button to save."
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 9
                wrapMode: Text.Wrap
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Flickable {
                    id: layoutFlick
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: layoutScrollBar.visible ? layoutScrollBar.width : 0
                    clip: true
                    contentWidth: width
                    contentHeight: sectionRows.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: sectionRows
                        width: layoutFlick.width
                        spacing: 3

                        Repeater {
                            model: root.order || []

                            Rectangle {
                                id: sectionRow
                                required property var modelData
                                readonly property string sectionId: String(modelData)
                                readonly property int sectionIndex: root.order.indexOf(sectionId)
                                readonly property bool shown: root.sectionVisible(sectionId)

                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                color: Theme.popupButton
                                border.width: 1
                                border.color: Theme.active

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    spacing: 5

                                    SettingsButton {
                                        label: sectionRow.shown ? "Shown" : "Hidden"
                                        active: sectionRow.shown
                                        available: !sectionRow.shown || root.visibleCount() > 1
                                        textSize: 8
                                        onClicked: root.visibilityRequested(
                                            sectionRow.sectionId, !sectionRow.shown)
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.sectionLabel(sectionRow.sectionId)
                                        color: sectionRow.shown ? Theme.foreground : Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }

                                    SettingsButton {
                                        label: "↑"
                                        available: sectionRow.sectionIndex > 0
                                        textSize: 10
                                        onClicked: root.moveRequested(sectionRow.sectionId, -1)
                                    }

                                    SettingsButton {
                                        label: "↓"
                                        available: sectionRow.sectionIndex >= 0
                                            && sectionRow.sectionIndex < root.order.length - 1
                                        textSize: 10
                                        onClicked: root.moveRequested(sectionRow.sectionId, 1)
                                    }
                                }
                            }
                        }
                    }
                }

                ListScrollBar {
                    id: layoutScrollBar
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    flickable: layoutFlick
                    z: 10
                }
            }
        }
    }
}
