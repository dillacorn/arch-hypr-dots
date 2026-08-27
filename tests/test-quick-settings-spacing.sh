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

if "PowerModeCard {" in text:
    raise SystemExit("FAIL: Quick Settings still reserves a dead PowerModeCard layout row")

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

print("PASS: Quick Settings section rows are contiguous with one standard gap between cards.")
PY
