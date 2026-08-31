#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"

python3 - "$QML" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = 'model: ["top", "bottom", "left", "right"]'
index = text.find(needle)
if index < 0:
    raise SystemExit('FAIL: bar position model was not found')

flow_index = text.rfind('Flow {', 0, index)
row_index = text.rfind('RowLayout {', 0, index)
if row_index < 0 or row_index < flow_index:
    raise SystemExit('FAIL: bar position controls are still inside a wrapping Flow')

print('PASS: bar position controls use a non-wrapping horizontal RowLayout.')
PY
