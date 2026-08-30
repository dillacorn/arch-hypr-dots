#!/usr/bin/env python3
from pathlib import Path
import hashlib

QUICK = Path("config/quickshell/awtarchy/QuickSettings.qml")
HISTORY = Path("local/share/awtarchy/quickshell-managed-history.sha256")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


quick = QUICK.read_text()

quick = replace_once(
    quick,
    '''    onSettingsModePanelHeightChanged: {
        if (settingsOpen)
            Qt.callLater(() => resizeForSettingsMode());
    }
''',
    '''    onSettingsModePanelHeightChanged: {
        if (settingsOpen)
            Qt.callLater(() => resizeForSettingsMode());
    }
    onPlacementChanged: {
        if (!quickSettingsWindow.visible || openPreparing)
            return;
        Qt.callLater(() => {
            if (root.settingsOpen)
                root.resizeForSettingsMode();
            else
                root.positionWindow();
        });
    }
''',
    "placement follow handler",
)

quick = replace_once(
    quick,
    '''        minimumSize: Qt.size(root.minimumPanelWidth, root.minimumPanelHeight)
''',
    '''        minimumSize: Qt.size(root.minimumPanelWidth,
            root.settingsOpen ? root.minimumSettingsPanelHeight : root.minimumPanelHeight)
''',
    "dynamic floating minimum",
)

quick = replace_once(
    quick,
    '''                        onLayoutEditorRequested: root.layoutEditorOpen = true
''',
    '''                        onLayoutEditorRequested: {
                            settingsPanel.resetCopySelection();
                            root.layoutEditorOpen = true;
                        }
''',
    "layout editor transient reset",
)

QUICK.write_text(quick)

digest = hashlib.sha256(QUICK.read_bytes()).hexdigest()
entry = f"{digest}\t.config/quickshell/awtarchy/QuickSettings.qml"
history = HISTORY.read_text()
if entry not in history.splitlines():
    if history and not history.endswith("\n"):
        history += "\n"
    history += entry + "\n"
    HISTORY.write_text(history)
