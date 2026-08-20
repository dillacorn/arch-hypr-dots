from pathlib import Path
import re

root = Path.cwd()
base = root / "config/quickshell/awtarchy"


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# Remove the failed central singleton-child lookup/fade implementation.
path = base / "shell.qml"
text = path.read_text()
text = replace_once(
    text,
    '    readonly property int managedFlyoutFadeDuration: 140\n',
    '',
    'shell fade duration',
)
text, count = re.subn(
    r'\n    function managedFlyoutWindow\(surface\) \{.*?'
    r'\n    function closeActiveFloatingSurface\(\) \{',
    '\n    function closeActiveFloatingSurface() {',
    text,
    count=1,
    flags=re.S,
)
if count != 1:
    raise RuntimeError('shell managed flyout function block not found')
text, count = re.subn(
    r'\n    NumberAnimation \{\n        id: clipboardFlyoutFade.*?'
    r'\n    Connections \{\n        target: Hyprland',
    '\n    Connections {\n        target: Hyprland',
    text,
    count=1,
    flags=re.S,
)
if count != 1:
    raise RuntimeError('shell central flyout animation block not found')
path.write_text(text)

# Preserve the shared Super+A animation state, remove only the failed lookup revision.
path = base / "FlyoutManager.qml"
text = path.read_text()
text = replace_once(
    text,
    '    property int windowLookupRevision: 0\n',
    '',
    'FlyoutManager windowLookupRevision',
)
text, count = re.subn(
    r'        // shell\.qml\'s Connections targets discover singleton-owned windows by\n'
    r'        // title\. Their first evaluation can happen before those windows finish\n'
    r'        // constructing, so make the lookup depend on a revision bumped by\n'
    r'        // claim\(\) before each flyout is shown\.\n'
    r'        const dependency = windowLookupRevision;\n\n',
    '',
    text,
    count=1,
)
if count != 1:
    raise RuntimeError('FlyoutManager title lookup dependency block not found')
text, count = re.subn(
    r'        // Refresh shell\.qml\'s managed-window bindings while every singleton is\n'
    r'        // fully constructed, but before the requested flyout becomes visible\.\n'
    r'        windowLookupRevision\+\+;\n\n',
    '',
    text,
    count=1,
)
if count != 1:
    raise RuntimeError('FlyoutManager claim revision block not found')
path.write_text(text)


def patch_flyout(filename, window_id, close_name, finish_open_name):
    path = base / filename
    text = path.read_text()

    state_anchor = '    property bool openPreparing: false\n'
    state_block = (
        state_anchor
        + '    property bool panelPresented: false\n'
        + '    property bool closeFadePending: false\n'
        + '    readonly property int panelFadeDuration: 140\n'
    )
    text = replace_once(text, state_anchor, state_block, f'{filename} fade state')

    marker = f'    function {finish_open_name}() {{'
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f'{filename}: {finish_open_name} not found')
    next_function = text.find('\n    function ', start + len(marker))
    if next_function < 0:
        raise RuntimeError(f'{filename}: cannot bound {finish_open_name}')
    section = text[start:next_function]
    old = (
        '        openPreparing = false;\n'
        f'        {window_id}.visible = true;\n'
    )
    new = (
        '        openPreparing = false;\n'
        '        closeFadeTimer.stop();\n'
        '        closeFadePending = false;\n'
        '        if (!wasVisible)\n'
        '            panelPresented = false;\n'
        f'        {window_id}.visible = true;\n'
        '        if (!wasVisible)\n'
        '            Qt.callLater(() => root.panelPresented = true);\n'
        '        else\n'
        '            panelPresented = true;\n'
    )
    if section.count(old) != 1:
        raise RuntimeError(f'{filename}: open transition not found')
    section = section.replace(old, new, 1)
    text = text[:start] + section + text[next_function:]

    complete_name = 'completeCloseCenter' if close_name == 'closeCenter' else 'completeClose'
    close_signature = f'    function {close_name}() {{\n'
    wrapper = (
        f'    function {close_name}() {{\n'
        '        openPreparing = false;\n'
        '        if (prepareProcess.running)\n'
        '            prepareProcess.running = false;\n'
        '        if (closeFadePending)\n'
        '            return;\n'
        f'        if ({window_id}.visible\n'
        '            && FlyoutManager.animationsEnabled\n'
        '            && panelPresented) {\n'
        '            closeFadePending = true;\n'
        '            panelPresented = false;\n'
        '            closeFadeTimer.restart();\n'
        '            return;\n'
        '        }\n'
        f'        {complete_name}();\n'
        '    }\n\n'
        f'    function {complete_name}() {{\n'
        '        closeFadeTimer.stop();\n'
        '        closeFadePending = false;\n'
        '        panelPresented = false;\n'
    )
    text = replace_once(text, close_signature, wrapper, f'{filename} close wrapper')

    window_anchor = f'    FloatingWindow {{\n        id: {window_id}\n'
    timer = (
        '    Timer {\n'
        '        id: closeFadeTimer\n'
        '        interval: root.panelFadeDuration + 10\n'
        '        repeat: false\n'
        f'        onTriggered: root.{complete_name}()\n'
        '    }\n\n'
        + window_anchor
    )
    text = replace_once(text, window_anchor, timer, f'{filename} close fade timer')

    panel_anchor = '        Rectangle {\n            id: panel\n'
    panel = (
        '        Rectangle {\n'
        '            id: panel\n'
        '            opacity: root.panelPresented ? 1 : 0\n\n'
        '            Behavior on opacity {\n'
        '                enabled: FlyoutManager.animationsEnabled\n'
        '                NumberAnimation {\n'
        '                    duration: root.panelFadeDuration\n'
        '                    easing.type: Easing.OutCubic\n'
        '                }\n'
        '            }\n'
    )
    text = replace_once(text, panel_anchor, panel, f'{filename} panel fade')
    path.write_text(text)


patch_flyout('QuickSettings.qml', 'quickSettingsWindow', 'close', 'finishPreparedOpen')
patch_flyout('NetworkMenu.qml', 'networkWindow', 'close', 'finishPreparedOpen')
patch_flyout('BluetoothMenu.qml', 'bluetoothWindow', 'close', 'finishPreparedOpen')
patch_flyout('ClipboardMenu.qml', 'clipboardWindow', 'close', 'finishPreparedOpen')
patch_flyout('Notifications.qml', 'centerWindow', 'closeCenter', 'finishPreparedCenterOpen')

# Replace obsolete central-fade assertions with direct panel assertions.
test_path = root / 'tests/test-flyout-toggle-debounce.sh'
test = test_path.read_text()
start = test.find('require_source "$SHELL"')
end = test.find('require_source "$LAUNCHER"', start)
if start < 0 or end < 0 or end <= start:
    raise RuntimeError('fade regression test block not found')
replacement = '''for flyout in QuickSettings.qml NetworkMenu.qml BluetoothMenu.qml ClipboardMenu.qml Notifications.qml; do
  path="${QML_DIR}/${flyout}"
  require_source "$path" 'property bool panelPresented: false' \\
    "${flyout} is missing local panel presentation state"
  require_source "$path" 'property bool closeFadePending: false' \\
    "${flyout} is missing delayed close state"
  require_source "$path" 'readonly property int panelFadeDuration: 140' \\
    "${flyout} fade duration does not match the launcher"
  require_source "$path" 'opacity: root.panelPresented ? 1 : 0' \\
    "${flyout} panel opacity is not driven locally"
  require_source "$path" 'Behavior on opacity {' \\
    "${flyout} panel is missing an opacity behavior"
  require_source "$path" 'enabled: FlyoutManager.animationsEnabled' \\
    "${flyout} fade does not honor Super+A"
  require_source "$path" 'duration: root.panelFadeDuration' \\
    "${flyout} fade does not use the local duration"
  require_source "$path" 'easing.type: Easing.OutCubic' \\
    "${flyout} fade easing does not match the launcher"
  require_source "$path" 'id: closeFadeTimer' \\
    "${flyout} is missing the delayed unmap timer"
  require_source "$path" 'interval: root.panelFadeDuration + 10' \\
    "${flyout} does not stay mapped through the fade"
  require_source "$path" 'closeFadeTimer.restart();' \\
    "${flyout} close path does not start the fade timer"
  require_source "$path" 'Qt.callLater(() => root.panelPresented = true);' \\
    "${flyout} open path does not present the panel after mapping"
done

if grep -Fq -- 'managedFlyoutWindow(' "$SHELL"; then
  fail 'shell still contains the broken singleton-child window lookup'
fi
if grep -Fq -- 'windowLookupRevision' "$MANAGER"; then
  fail 'flyout manager still contains obsolete window lookup revision state'
fi

'''
test = test[:start] + replacement + test[end:]
test = test.replace(
    'Flyout toggle debounce and fade regression test passed.',
    'Flyout toggle debounce and panel fade regression test passed.',
)
test_path.write_text(test)

shell = (base / 'shell.qml').read_text()
manager = (base / 'FlyoutManager.qml').read_text()
if 'managedFlyoutWindow(' in shell or 'clipboardFlyoutFade' in shell:
    raise RuntimeError('broken central fade code still exists')
if 'windowLookupRevision' in manager:
    raise RuntimeError('obsolete lookup revision still exists')
