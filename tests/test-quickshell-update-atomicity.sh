#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"

# Protect the live shell from seeing a partially updated managed QML tree.
python3 - "$RUNTIME" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
helper_start = text.find('stop_quickshell_update_shell() {')
if helper_start < 0:
    raise SystemExit('FAIL: session-aware Quickshell update stop helper is missing')
helper_end = text.find('\n}\n', helper_start)
if helper_end < 0:
    raise SystemExit('FAIL: could not parse Quickshell update stop helper')
helper = text[helper_start:helper_end]
if 'command -v hyprctl >/dev/null 2>&1 || return 0' not in helper:
    raise SystemExit('FAIL: headless updates do not bypass Quickshell process shutdown')
if '[[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0' not in helper:
    raise SystemExit('FAIL: non-Hyprland updates do not bypass Quickshell process shutdown')
if 'stop_quickshell_update_instances' not in helper:
    raise SystemExit('FAIL: live Hyprland updates do not stop Quickshell instances')

start = text.find('ensure_quickshell_update_prerequisites')
if start < 0:
    raise SystemExit('FAIL: could not locate the Quickshell update prerequisite stage')
snapshot_index = text.find('snapshot_quickshell_update_legacy_paths', start)
if snapshot_index < 0:
    raise SystemExit('FAIL: could not locate the Quickshell legacy snapshot stage')
apply_index = text.find('apply_plan "$plan_file"', snapshot_index)
if apply_index < 0:
    raise SystemExit('FAIL: could not locate apply_plan in the Quickshell update path')
stop_index = text.find('stop_quickshell_update_shell', snapshot_index, apply_index)
if stop_index < 0:
    raise SystemExit('FAIL: live Quickshell is not stopped before managed files are mutated')
start_index = text.find('start_quickshell_update_shell', apply_index)
if start_index < 0:
    raise SystemExit('FAIL: Quickshell is not restarted after the managed update')

print('PASS: live Hyprland updates stop Quickshell before mutation while headless updates remain valid.')
PY
