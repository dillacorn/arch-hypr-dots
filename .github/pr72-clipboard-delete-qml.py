#!/usr/bin/env python3
from hashlib import sha256
from pathlib import Path

qml_path = Path("config/quickshell/awtarchy/ClipboardMenu.qml")
history_path = Path("local/share/awtarchy/quickshell-managed-history.sha256")
backend_path = Path("config/hypr/scripts/quickshell_clipboard.sh")

qml = qml_path.read_text()


def replace_once(old: str, new: str, description: str) -> None:
    global qml
    count = qml.count(old)
    if count != 1:
        raise SystemExit(f"{description}: expected exactly one match, found {count}")
    qml = qml.replace(old, new, 1)


replace_once(
'''    function choose(entry) {
        if (!entry)
            return;
        selectProcess.exec([backend, "select", String(entry.index)]);
        close();
    }
''',
'''    function choose(entry) {
        if (!entry)
            return;
        selectProcess.exec([backend, "select", String(entry.index)]);
        close();
    }

    function clipboardWindowVisible() {
        return clipboardWindow.visible;
    }

    function deleteEntry(entry) {
        if (!entry || deleteProcess.running)
            return;
        deleteProcess.exec([backend, "delete", String(entry.index)]);
    }
''',
"could not locate clipboard choose function",
)

replace_once(
'''    Process { id: selectProcess }
''',
'''    Process { id: selectProcess }

    Process {
        id: deleteProcess
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && root.clipboardWindowVisible()) {
                root.beginListLoad();
                Qt.callLater(() => search.forceActiveFocus());
            }
        }
    }
''',
"could not locate clipboard select process",
)

replace_once(
'''                            : ((rowMouse.containsMouse || viewMouse.containsMouse)
                                ? Theme.subtleHover : Theme.popupBackground)''',
'''                            : ((rowMouse.containsMouse || viewMouse.containsMouse
                                    || deleteMouse.containsMouse)
                                ? Theme.subtleHover : Theme.popupBackground)''',
"could not locate clipboard row hover state",
)

old_margin = '''                            anchors.rightMargin: (clipboardScrollBar.visible ? 20 : 10)
                                + (viewButton.visible ? 36 : 0)'''
new_margin = '''                            anchors.rightMargin: (clipboardScrollBar.visible ? 20 : 10)
                                + (deleteButton.visible ? 36 : 0)
                                + (viewButton.visible ? 36 : 0)'''
count = qml.count(old_margin)
if count != 2:
    raise SystemExit(f"clipboard row right-margin guards: expected 2 matches, found {count}")
qml = qml.replace(old_margin, new_margin)

replace_once(
'''                            visible: Boolean(row.modelData)
                                && row.modelData.binary === false
                                && (rowMouse.containsMouse || viewMouse.containsMouse)''',
'''                            visible: Boolean(row.modelData)
                                && row.modelData.binary === false
                                && (rowMouse.containsMouse || viewMouse.containsMouse
                                    || deleteMouse.containsMouse)''',
"could not locate clipboard view-button visibility",
)

replace_once(
'''                            anchors.rightMargin: clipboardScrollBar.visible ? 18 : 7
                            anchors.verticalCenter: parent.verticalCenter''',
'''                            anchors.rightMargin: (clipboardScrollBar.visible ? 18 : 7) + 36
                            anchors.verticalCenter: parent.verticalCenter''',
"could not relocate clipboard view button",
)

replace_once(
'''                            MouseArea {
                                id: viewMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    root.openDetail(row.modelData);
                                    mouse.accepted = true;
                                }
                            }
                        }
                    }

                    ListScrollBar {''',
'''                            MouseArea {
                                id: viewMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    root.openDetail(row.modelData);
                                    mouse.accepted = true;
                                }
                            }
                        }

                        Rectangle {
                            id: deleteButton
                            visible: Boolean(row.modelData)
                                && (rowMouse.containsMouse || viewMouse.containsMouse
                                    || deleteMouse.containsMouse)
                            width: 28
                            height: 28
                            anchors.right: parent.right
                            anchors.rightMargin: clipboardScrollBar.visible ? 18 : 7
                            anchors.verticalCenter: parent.verticalCenter
                            color: deleteMouse.containsMouse ? Theme.urgent : Theme.active
                            border.width: 1
                            border.color: deleteMouse.containsMouse ? Theme.urgent : Theme.focus
                            z: 21

                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Math.max(11,
                                    Math.round(14 * root.effectiveIconScale / 100))
                            }

                            MouseArea {
                                id: deleteMouse
                                anchors.fill: parent
                                enabled: !deleteProcess.running
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: mouse => {
                                    root.deleteEntry(row.modelData);
                                    mouse.accepted = true;
                                }
                            }
                        }
                    }

                    ListScrollBar {''',
"could not insert clipboard delete button",
)

qml_path.write_text(qml)

required = [
    'function deleteEntry(entry)',
    'deleteProcess.exec([backend, "delete", String(entry.index)]);',
    'id: deleteProcess',
    'if (exitCode === 0 && root.clipboardWindowVisible())',
    'id: deleteButton',
    'root.deleteEntry(row.modelData);',
]
for marker in required:
    if marker not in qml:
        raise SystemExit(f"missing post-patch marker: {marker}")

history = history_path.read_text()
managed = [
    (backend_path, ".config/hypr/scripts/quickshell_clipboard.sh"),
    (qml_path, ".config/quickshell/awtarchy/ClipboardMenu.qml"),
]
lines = []
for source, installed in managed:
    digest = sha256(source.read_bytes()).hexdigest()
    line = f"{digest}\t{installed}"
    if line not in history:
        lines.append(line)

if lines:
    if not history.endswith("\n"):
        history += "\n"
    history += "# 2026-08-27 per-item Clipboard History deletion.\n"
    history += "\n".join(lines) + "\n"
    history_path.write_text(history)
