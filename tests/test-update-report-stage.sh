#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="${ROOT}/local/bin/awtarchy"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

expected='if ! AWTARCHY_REPORT_FAILURE_STAGE=restart_after_update bash "$manager" restart; then'
legacy='if ! bash "$manager" restart; then'

bash -n "$LAUNCHER"
grep -Fq -- "$expected" "$LAUNCHER" \
    || fail 'post-update Quickshell restart does not set restart_after_update reporting stage'
! grep -Fq -- "$legacy" "$LAUNCHER" \
    || fail 'post-update Quickshell restart still uses the generic restart reporting stage'

printf 'update reporting stage regression test passed\n'
