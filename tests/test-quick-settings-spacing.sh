#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"

python3 - "$QML" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

compat = re.search(
    r"\n\s*PowerModeCard \{\n(?P<body>.*?)\n\s*\}\n",
    text,
    re.DOTALL,
)
if compat is None:
    raise SystemExit("FAIL: inert Quick Settings PowerModeCard compatibility instance is missing")
if "Layout.row:" in compat.group("body"):
    raise SystemExit("FAIL: inert PowerModeCard compatibility instance still reserves a GridLayout row")
if "presentationEnabled: true" in compat.group("body"):
    raise SystemExit("FAIL: Quick Settings PowerModeCard compatibility instance can render")

rows = [
    (int(index), int(count))
    for index, count in re.findall(
        r"Layout\.row:\s*FlyoutEdgeLayout\.sectionRow\(root\.bottomEdgeLayout,\s*(\d+),\s*(\d+)\)",
        text,
    )
]

if not rows:
    raise SystemExit("FAIL: no Quick Settings section rows were found")

counts = {count for _, count in rows}
if counts != {11}:
    raise SystemExit(f"FAIL: Quick Settings section row counts are not normalized to 11: {sorted(counts)}")

indices = sorted(index for index, _ in rows)
if indices != list(range(11)):
    raise SystemExit(f"FAIL: Quick Settings section rows are not contiguous: {indices}")

print("PASS: Quick Settings keeps its inert Power Mode compatibility host without reserving an extra section gap.")
PY
