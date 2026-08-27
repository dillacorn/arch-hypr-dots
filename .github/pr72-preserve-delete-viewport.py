#!/usr/bin/env python3
from pathlib import Path

qml_path = Path("config/quickshell/awtarchy/ClipboardMenu.qml")
text = qml_path.read_text()

old_properties = '''    property int activeThumbnailIndex: -1
    property string activeThumbnailPath: ""
'''
new_properties = '''    property int activeThumbnailIndex: -1
    property string activeThumbnailPath: ""
    property int deletingEntryIndex: -1
    property real deleteViewportY: 0
'''
if text.count(old_properties) != 1:
    raise SystemExit("expected exactly one clipboard delete-state property insertion point")
text = text.replace(old_properties, new_properties, 1)

old_delete = '''    function deleteEntry(entry) {
        if (!entry || deleteProcess.running)
            return;
        deleteProcess.exec([backend, "delete", String(entry.index)]);
    }
'''
new_delete = '''    function deleteEntry(entry) {
        if (!entry || deleteProcess.running)
            return;
        deletingEntryIndex = entry.index;
        deleteViewportY = clipboardList.contentY;
        deleteProcess.exec([backend, "delete", String(entry.index)]);
    }

    function finishDelete(exitCode) {
        const deletedIndex = deletingEntryIndex;
        const savedY = deleteViewportY;
        deletingEntryIndex = -1;
        deleteViewportY = 0;

        if (exitCode !== 0 || !clipboardWindowVisible() || deletedIndex < 0)
            return;

        entries = ClipboardLoadState.removeRecord(entries, deletedIndex);
        thumbnailQueue = thumbnailQueue.filter(index => index !== deletedIndex);
        const nextKnown = Object.assign({}, thumbnailKnown);
        delete nextKnown[String(deletedIndex)];
        thumbnailKnown = nextKnown;

        Qt.callLater(() => {
            const minY = clipboardList.originY;
            const maxY = Math.max(minY,
                minY + clipboardList.contentHeight - clipboardList.height);
            clipboardList.contentY = Math.max(minY, Math.min(maxY, savedY));

            if (clipboardList.count === 0)
                clipboardList.currentIndex = -1;
            else if (clipboardList.currentIndex < 0)
                clipboardList.currentIndex = 0;
            else if (clipboardList.currentIndex >= clipboardList.count)
                clipboardList.currentIndex = clipboardList.count - 1;

            search.forceActiveFocus();
        });
    }
'''
if text.count(old_delete) != 1:
    raise SystemExit("expected exactly one clipboard deleteEntry implementation")
text = text.replace(old_delete, new_delete, 1)

old_process = '''    Process {
        id: deleteProcess
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && root.clipboardWindowVisible()) {
                root.beginListLoad();
                Qt.callLater(() => search.forceActiveFocus());
            }
        }
    }
'''
new_process = '''    Process {
        id: deleteProcess
        onExited: (exitCode, exitStatus) => root.finishDelete(exitCode)
    }
'''
if text.count(old_process) != 1:
    raise SystemExit("expected exactly one clipboard deleteProcess implementation")
text = text.replace(old_process, new_process, 1)

qml_path.write_text(text)
