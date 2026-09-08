#!/usr/bin/env bash
set -euo pipefail

# TDD regression for the Quick Settings header Awtarchy Tips shortcut.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"

python3 - "$QML" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
start = text.index('id: headerBar')
end = text.index('id: closeButton', start)
header = text[start:end]

refresh = header.index('label: root.statusLoading ? "…" : "↻"')
try:
    tips = header.index('label: "?"')
except ValueError:
    raise SystemExit('FAIL: Quick Settings header is missing the Awtarchy Tips ? button')
save = header.index('label: ""')

if not refresh < tips < save:
    raise SystemExit('FAIL: Awtarchy Tips ? button is not between Refresh and Save')

next_button = header.find('SettingsButton {', tips + 1)
tips_block = header[tips: next_button if next_button >= 0 else len(header)]
if 'onClicked: root.openAwtarchyTips()' not in tips_block:
    raise SystemExit('FAIL: Awtarchy Tips ? button does not call openAwtarchyTips()')

required = [
    'function openAwtarchyTips()',
    '"--class", "awtarchy-tips-tui"',
    'configHome + "/hypr/scripts/awtarchy-tips-tui.sh", "--tui"',
]
for needle in required:
    if needle not in text:
        raise SystemExit(f'FAIL: missing existing Awtarchy Tips launcher contract: {needle}')

print('PASS: Quick Settings Awtarchy Tips header button')
PY
