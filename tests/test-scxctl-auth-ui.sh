#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
BACKEND="${ROOT}/config/hypr/scripts/hypr_quicksettings.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

grep -Fq 'function authorizeScheduler()' "$QML" \
  || fail 'Quick Settings has no sched-ext authorization launcher'
grep -Fq 'label: "Authorize"' "$QML" \
  || fail 'Quick Settings has no explicit Authorize button'
grep -Fq 'terminalLauncher, "--class", "awtarchy-scxctl-auth", "--hold", "--",' "$QML" \
  || fail 'sched-ext authorization is not opened in a held terminal'
grep -Fq 'backend, "--authorize-scheduler"' "$QML" \
  || fail 'Authorize button does not call the backend authorization entrypoint'
grep -Fq '&& Boolean(root.schedulerStatus.authorized)' "$QML" \
  || fail 'Start/Switch is not gated on completed authorization'

grep -Fq 'machine_scheduler_authorize()' "$BACKEND" \
  || fail 'backend has no scheduler authorization function'
grep -Fq 'ensure_scxctl_nopasswd_rule' "$BACKEND" \
  || fail 'backend authorization does not use the existing restricted sudoers setup'
grep -Fq -- '--authorize-scheduler)' "$BACKEND" \
  || fail 'backend has no terminal authorization entrypoint'
grep -Fq 'qs -c awtarchy ipc call quicksettings refresh' "$BACKEND" \
  || fail 'successful authorization does not refresh Quick Settings'

printf '%s\n' 'PASS: Quick Settings provides an interactive restricted scxctl authorization path.'
