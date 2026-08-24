#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="${ROOT}/local/bin/awtarchy"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
REPORT_HELPER="${ROOT}/config/hypr/scripts/awtarchy_report_failure.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

launcher_expected="if ! AWTARCHY_REPORT_FAILURE_STAGE=restart_after_update bash \"\$manager\" restart; then"
launcher_legacy="if ! bash \"\$manager\" restart; then"
launcher_pending="bash \"\$report_helper\" prompt-pending"
runtime_restart="AWTARCHY_REPORT_SUPPRESS_QUICKSHELL=1 run_target bash \"\$manager\" restart 9>&-"
runtime_start="AWTARCHY_REPORT_SUPPRESS_QUICKSHELL=1 run_target bash \"\$manager\" start 9>&-"

bash -n "$LAUNCHER"
bash -n "$RUNTIME"
bash -n "$REPORT_HELPER"

grep -Fq -- "$launcher_expected" "$LAUNCHER" \
    || fail 'post-update UI reconciliation does not set restart_after_update reporting stage'
! grep -Fq -- "$launcher_legacy" "$LAUNCHER" \
    || fail 'post-update UI reconciliation still uses the generic restart reporting stage'

grep -Fq -- "$launcher_pending" "$LAUNCHER" \
    || fail 'interactive maintenance menu does not surface queued failure reports'
grep -Fq -- 'prompt-pending)' "$REPORT_HELPER" \
    || fail 'report helper is missing the quiet maintenance-menu pending prompt mode'

grep -Fq -- "$runtime_restart" "$RUNTIME" \
    || fail 'updater validation restart does not suppress intermediate generic reports'
[[ "$(grep -Fc -- "$runtime_start" "$RUNTIME")" -ge 2 ]] \
    || fail 'updater fallback/rollback starts do not suppress intermediate generic reports'

python3 - "$RUNTIME" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")

required = [
    'report_quickshell_update_failure() {',
    'capture quickshell restart_after_update quickshell_not_ready',
    'AWTARCHY_REPORT_CONFIG_VERSION_OVERRIDE="$source_label"',
]
for needle in required:
    if needle not in text:
        raise SystemExit(f"FAIL: updater runtime is missing reporting invariant: {needle}")

failure_block = '''if ! start_quickshell_update_shell; then
    rollback_quickshell_update
    report_quickshell_update_failure "$source_label" "$target_home"
    die "Quickshell did not start successfully. User files were rolled back."
  fi'''
if failure_block not in text:
    raise SystemExit(
        "FAIL: exhausted updater recovery must roll back before emitting one final failure report"
    )
PY

printf 'update reporting stage regression test passed\n'
