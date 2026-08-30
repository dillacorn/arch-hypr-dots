#!/usr/bin/env python3
from pathlib import Path
import hashlib

QML = Path("config/quickshell/awtarchy/QuickSettings.qml")
HISTORY = Path("local/share/awtarchy/quickshell-managed-history.sha256")

text = QML.read_text()

old_close = '''            Rectangle {
                width: 28
                height: 28
                anchors.right: panel.right
                anchors.rightMargin: 6
                anchors.verticalCenter: headerBar.verticalCenter
                color: closeMouse.containsMouse ? Theme.focus : Theme.active
                border.width: 1
                border.color: closeMouse.containsMouse ? Theme.focus : Theme.muted
                radius: 0
                z: 20

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledIcon(15)
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
'''

if text.count(old_close) != 1:
    raise SystemExit(f"expected one old close block, found {text.count(old_close)}")
text = text.replace(old_close, "", 1)

header_tail = '''                        SettingsButton {
                            label: ""
                            active: root.settingsOpen
                            textSize: root.scaledIcon(11)
                            onClicked: root.toggleSettings()
                        }
                    }
                }

                Rectangle {
                    Layout.row: 1
'''

new_header_tail = '''                        SettingsButton {
                            label: ""
                            active: root.settingsOpen
                            textSize: root.scaledIcon(11)
                            onClicked: root.toggleSettings()
                        }
                    }

                    Rectangle {
                        id: closeButton
                        width: 28
                        height: 28
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        color: closeMouse.containsMouse ? Theme.focus : Theme.active
                        border.width: 1
                        border.color: closeMouse.containsMouse ? Theme.focus : Theme.muted
                        radius: 0
                        z: 20

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: root.scaledIcon(15)
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                Rectangle {
                    Layout.row: 1
'''

if text.count(header_tail) != 1:
    raise SystemExit(f"expected one header tail, found {text.count(header_tail)}")
text = text.replace(header_tail, new_header_tail, 1)
QML.write_text(text)

managed = ".config/quickshell/awtarchy/QuickSettings.qml"
digest = hashlib.sha256(QML.read_bytes()).hexdigest()
entry = f"{digest}\t{managed}\n"
history = HISTORY.read_text()
if entry not in history:
    with HISTORY.open("a") as handle:
        handle.write(entry)
