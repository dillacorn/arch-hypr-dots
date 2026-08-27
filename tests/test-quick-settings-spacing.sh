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

# Invisible QML layout children can still be auto-placed, so the compatibility
# instance must live completely outside the visible settingsColumn GridLayout.
settings_column = re.search(
    r"GridLayout \{\n\s*id: settingsColumn\n",
    text,
)
if settings_column is None:
    raise SystemExit("FAIL: Quick Settings settingsColumn GridLayout is missing")

block_start = settings_column.start()
brace_start = text.find("{", block_start)
if brace_start < 0:
    raise SystemExit("FAIL: could not locate settingsColumn opening brace")

depth = 0
block_end = None
for index in range(brace_start, len(text)):
    char = text[index]
    if char == "{":
        depth += 1
    elif char == "}":
        depth -= 1
        if depth == 0:
            block_end = index + 1
            break

if block_end is None:
    raise SystemExit("FAIL: could not locate settingsColumn closing brace")

settings_column_text = text[block_start:block_end]
if re.search(r"\bPowerModeCard\s*\{", settings_column_text):
    raise SystemExit(
        "FAIL: inert PowerModeCard compatibility instance still participates in settingsColumn GridLayout"
    )

expected = [
    "brightness",
    "output-volume",
    "bar",
    "display-effects",
    "submap",
    "wallpaper",
    "awtarchy",
    "smtty",
    "scheduler",
    "numlock",
    "title-bars",
]
row_sections = re.findall(
    r'Layout\.row:\s*root\.quickSettingsSectionRow\("([^"]+)"\)',
    settings_column_text,
)
visible_sections = re.findall(
    r'visible:\s*root\.quickSettingsSectionVisible\("([^"]+)"\)',
    settings_column_text,
)

if row_sections != expected:
    raise SystemExit(
        f"FAIL: Quick Settings dynamic section rows are not the expected contiguous real-section sequence: {row_sections}"
    )
if visible_sections != expected:
    raise SystemExit(
        f"FAIL: Quick Settings visibility bindings do not match the real-section sequence: {visible_sections}"
    )

if 'FlyoutEdgeLayout.sectionRow(bottomEdgeLayout, index, visibleOrder.length)' not in text:
    raise SystemExit("FAIL: dynamic Quick Settings rows no longer compact visible sections for top/bottom layout")

print("PASS: Quick Settings keeps the inert Power Mode compatibility host outside the grid and dynamically packs the 11 real sections without a dead gap.")
PY
