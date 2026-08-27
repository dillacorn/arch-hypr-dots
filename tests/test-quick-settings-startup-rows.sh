#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"

python3 - "$QUICK_SETTINGS" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
start_marker = "    function visibleQuickSettingsSectionOrder() {"
end_marker = "\n    function quickSettingsSectionRow(sectionId) {"

try:
    start = text.index(start_marker)
    end = text.index(end_marker, start)
except ValueError as exc:
    raise SystemExit(f"FAIL: Quick Settings section-order function could not be isolated: {exc}")

body = text[start:end]
if "BarState.defaultQuickSettingsSectionOrder" not in body:
    raise SystemExit(
        "FAIL: empty Quick Settings layout draft has no stock-order fallback; "
        "startup sections can all resolve to GridLayout row 0"
    )
if "return layoutOrderDraft.filter" in body:
    raise SystemExit(
        "FAIL: startup section order still reads the empty layoutOrderDraft directly"
    )

print("PASS: Quick Settings uses the stock section order until the per-monitor layout draft is loaded.")
PY
