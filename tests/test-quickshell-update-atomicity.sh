#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"

python3 - "$RUNTIME" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

start = text.find('ensure_quickshell_update_prerequisites\n  snapshot_quickshell_update_legacy_paths')
if start < 0:
    raise SystemExit('FAIL: could not locate the Quickshell update mutation section')

apply_index = text.find('apply_plan "$plan_file"', start)
if apply_index < 0:
    raise SystemExit('FAIL: could not locate apply_plan in the Quickshell update path')

stop_index = text.find('stop_quickshell_update_instances', start, apply_index)
if stop_index < 0:
    raise SystemExit('FAIL: live Quickshell is not stopped before managed files are mutated')

start_index = text.find('start_quickshell_update_shell', apply_index)
if start_index < 0:
    raise SystemExit('FAIL: Quickshell is not restarted after the managed update')

print('PASS: Quickshell is stopped before managed-file mutation and restarted afterward.')
PY
