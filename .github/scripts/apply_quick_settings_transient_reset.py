#!/usr/bin/env python3
from pathlib import Path
import hashlib

QUICK = Path("config/quickshell/awtarchy/QuickSettings.qml")
FLYOUT = Path("config/quickshell/awtarchy/FlyoutSettings.qml")
DISPLAY_SCALE = Path("config/quickshell/awtarchy/DisplayScaleSettings.qml")
HISTORY = Path("local/share/awtarchy/quickshell-managed-history.sha256")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


quick = QUICK.read_text()
old_reset = "settingsPanel.resetCopySelection();"
count = quick.count(old_reset)
if count != 4:
    raise SystemExit(f"settings panel reset contract: expected four matches, found {count}")
quick = quick.replace(old_reset, "settingsPanel.resetTransientState();")
quick = replace_once(
    quick,
    '''        brightnessHoverPercent = -1;
''',
    '''        brightnessHoverPercent = -1;
        outputVolumeHoverPercent = -1;
''',
    "hover transient reset",
)
QUICK.write_text(quick)

flyout = FLYOUT.read_text()
flyout = replace_once(
    flyout,
    '''    function resetCopySelection() {
        copyTargets = ({});
        copySelectionRevision++;
        copyOpen = false;
    }
''',
    '''    function resetCopySelection() {
        copyTargets = ({});
        copySelectionRevision++;
        copyOpen = false;
    }

    function resetTransientState() {
        resetCopySelection();
        displayScaleSection.resetTransientState();
    }
''',
    "flyout transient reset",
)
FLYOUT.write_text(flyout)

display = DISPLAY_SCALE.read_text()
display = replace_once(
    display,
    '''    function toggleCustomDisplayScale() {
        customScaleOpen = !customScaleOpen;
        if (customScaleOpen)
            customScaleText = displayScaleLabel(displayScale);
    }
''',
    '''    function toggleCustomDisplayScale() {
        customScaleOpen = !customScaleOpen;
        if (customScaleOpen)
            customScaleText = displayScaleLabel(displayScale);
    }

    function resetTransientState() {
        customScaleOpen = false;
        customScaleText = displayScaleLabel(displayScale);
        message = "";
        displayScaleError = "";
    }
''',
    "display scale transient reset",
)
DISPLAY_SCALE.write_text(display)

history = HISTORY.read_text()
for path, managed in (
    (QUICK, ".config/quickshell/awtarchy/QuickSettings.qml"),
    (FLYOUT, ".config/quickshell/awtarchy/FlyoutSettings.qml"),
    (DISPLAY_SCALE, ".config/quickshell/awtarchy/DisplayScaleSettings.qml"),
):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    entry = f"{digest}\t{managed}"
    if entry not in history.splitlines():
        if history and not history.endswith("\n"):
            history += "\n"
        history += entry + "\n"
HISTORY.write_text(history)
