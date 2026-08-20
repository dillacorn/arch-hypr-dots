from pathlib import Path
import argparse
import re

root = Path.cwd()
qml = root / "config/quickshell/awtarchy"
test_path = root / "tests/test-flyout-toggle-debounce.sh"

FLYOUTS = [
    ("QuickSettings.qml", "quickSettingsWindow", "close", "completeClose"),
    ("NetworkMenu.qml", "networkWindow", "close", "completeClose"),
    ("BluetoothMenu.qml", "bluetoothWindow", "close", "completeClose"),
    ("ClipboardMenu.qml", "clipboardWindow", "close", "completeClose"),
    ("Notifications.qml", "centerWindow", "closeCenter", "completeCloseCenter"),
]


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def patch_test():
    text = test_path.read_text()
    old = '''  require_source "$path" 'property bool closeFadePending: false' \\
    "${flyout} is missing delayed close state"
'''
    text = replace_once(text, old, '', 'remove delayed-close assertion')

    old = '''  require_source "$path" 'id: closeFadeTimer' \\
    "${flyout} is missing the delayed unmap timer"
  require_source "$path" 'interval: root.panelFadeDuration + 10' \\
    "${flyout} does not stay mapped through the fade"
  require_source "$path" 'closeFadeTimer.restart();' \\
    "${flyout} close path does not start the fade timer"
  require_source "$path" 'Qt.callLater(() => root.panelPresented = true);' \\
    "${flyout} open path does not present the panel after mapping"
'''
    new = '''  if grep -Fq -- 'closeFadePending' "$path"; then
    fail "${flyout} still keeps a transparent mapped window alive during close"
  fi
  if grep -Fq -- 'closeFadeTimer' "$path"; then
    fail "${flyout} still delays unmapping after the panel fades"
  fi
  if grep -Fq -- 'Qt.callLater(() => root.panelPresented = true);' "$path"; then
    fail "${flyout} still maps a transparent panel before starting the fade"
  fi
  case "$flyout" in
    QuickSettings.qml) window_id='quickSettingsWindow' ;;
    NetworkMenu.qml) window_id='networkWindow' ;;
    BluetoothMenu.qml) window_id='bluetoothWindow' ;;
    ClipboardMenu.qml) window_id='clipboardWindow' ;;
    Notifications.qml) window_id='centerWindow' ;;
  esac
  presented_line="$(grep -nF -- 'panelPresented = true;' "$path" | head -n1 | cut -d: -f1)"
  visible_line="$(grep -nF -- "${window_id}.visible = true;" "$path" | head -n1 | cut -d: -f1)"
  [[ -n "$presented_line" && -n "$visible_line" && "$presented_line" -lt "$visible_line" ]] \\
    || fail "${flyout} does not start panel presentation before mapping the window"
'''
    text = replace_once(text, old, new, 'replace transparent-window lifecycle assertions')
    text = text.replace(
        'Flyout toggle debounce and panel fade regression test passed.',
        'Flyout toggle debounce, fade, and blur lifecycle regression test passed.'
    )
    test_path.write_text(text)


def patch_flyout(filename, window_id, close_name, complete_name):
    path = qml / filename
    text = path.read_text()

    text = replace_once(
        text,
        '    property bool closeFadePending: false\n',
        '',
        f'{filename} delayed-close state',
    )

    old_open = (
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
    new_open = (
        '        openPreparing = false;\n'
        '        panelPresented = true;\n'
        f'        {window_id}.visible = true;\n'
    )
    text = replace_once(text, old_open, new_open, f'{filename} open lifecycle')

    wrapper_pattern = re.compile(
        rf'    function {re.escape(close_name)}\(\) \{{\n'
        r'        openPreparing = false;\n'
        r'        if \(prepareProcess\.running\)\n'
        r'            prepareProcess\.running = false;\n'
        r'        if \(closeFadePending\)\n'
        r'            return;\n'
        rf'        if \({re.escape(window_id)}\.visible\n'
        r'            && FlyoutManager\.animationsEnabled\n'
        r'            && panelPresented\) \{\n'
        r'            closeFadePending = true;\n'
        r'            panelPresented = false;\n'
        r'            closeFadeTimer\.restart\(\);\n'
        r'            return;\n'
        r'        \}\n'
        rf'        {re.escape(complete_name)}\(\);\n'
        r'    \}\n\n'
        rf'    function {re.escape(complete_name)}\(\) \{{\n'
        r'        closeFadeTimer\.stop\(\);\n'
        r'        closeFadePending = false;\n'
        r'        panelPresented = false;\n'
    )
    text, count = wrapper_pattern.subn(f'    function {close_name}() {{\n', text, count=1)
    if count != 1:
        raise RuntimeError(f'{filename}: delayed close wrapper not found')

    marker = f'    function {close_name}() {{'
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f'{filename}: close function missing after rewrite')
    end = text.find('\n    function ', start + len(marker))
    if end < 0:
        raise RuntimeError(f'{filename}: cannot bound close function')
    section = text[start:end]
    old_hide = f'        {window_id}.visible = false;\n'
    new_hide = old_hide + '        panelPresented = false;\n'
    if section.count(old_hide) != 1:
        raise RuntimeError(f'{filename}: expected one close-time window hide, found {section.count(old_hide)}')
    section = section.replace(old_hide, new_hide, 1)
    text = text[:start] + section + text[end:]

    timer_pattern = re.compile(
        r'\n    Timer \{\n'
        r'        id: closeFadeTimer\n'
        r'        interval: root\.panelFadeDuration \+ 10\n'
        r'        repeat: false\n'
        rf'        onTriggered: root\.{re.escape(complete_name)}\(\)\n'
        r'    \}\n'
    )
    text, count = timer_pattern.subn('\n', text, count=1)
    if count != 1:
        raise RuntimeError(f'{filename}: close fade timer not found')

    if 'closeFadePending' in text or 'closeFadeTimer' in text:
        raise RuntimeError(f'{filename}: delayed transparent-window lifecycle remains')
    if 'Qt.callLater(() => root.panelPresented = true);' in text:
        raise RuntimeError(f'{filename}: transparent-first open lifecycle remains')

    path.write_text(text)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--test-only', action='store_true')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if args.test_only == args.apply:
        parser.error('choose exactly one of --test-only or --apply')

    if args.test_only:
        patch_test()
        return

    for spec in FLYOUTS:
        patch_flyout(*spec)


if __name__ == '__main__':
    main()
