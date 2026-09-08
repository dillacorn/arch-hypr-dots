#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SURFACE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"

python3 - "$SURFACE_QML" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
marker = "    MouseArea {"
if marker not in text:
    raise SystemExit("FAIL: lockscreen has no full-surface MouseArea")

block = text.split(marker, 1)[1].split("\n    Rectangle {", 1)[0]
if "anchors.fill: parent" not in block:
    raise SystemExit("FAIL: lockscreen pointer area no longer covers the full surface")
if "cursorShape: Qt.BlankCursor" not in block:
    raise SystemExit("FAIL: lockscreen full-surface pointer area does not hide the cursor")

print("PASS: lockscreen hides the pointer cursor across the full locked surface.")
PY
