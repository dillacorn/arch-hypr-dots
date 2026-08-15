#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
BACKEND="${ROOT}/config/hypr/scripts/hypr_quicksettings.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || fail "$message"
}

assert_not_contains() {
  local file="$1" needle="$2" message="$3"
  ! grep -Fq -- "$needle" "$file" || fail "$message"
}

assert_contains "$QML" 'property bool schedulerAuthOpen: false' \
  'Quick Settings has no inline sched-ext authorization state'
assert_contains "$QML" 'id: schedulerAuthRunner' \
  'Quick Settings has no tracked sched-ext authorization process'
assert_contains "$QML" 'stdinEnabled: true' \
  'sched-ext authorization process does not accept password input on stdin'
assert_contains "$QML" 'backend, "--authorize-scheduler-stdin"' \
  'inline authorization does not call the stdin-only backend entrypoint'
assert_contains "$QML" 'schedulerAuthRunner.write(root.schedulerAuthPendingPassword + "\\n");' \
  'Quick Settings does not write the password directly to backend stdin'
assert_contains "$QML" 'echoMode: TextInput.Password' \
  'sched-ext password input is not masked'
assert_contains "$QML" 'schedulerPasswordInput.text = "";' \
  'sched-ext password input is not cleared after submission'
assert_contains "$QML" 'label: "Authorize"' \
  'Quick Settings has no explicit Authorize action'
assert_contains "$QML" '&& Boolean(root.schedulerStatus.authorized)' \
  'Start/Switch is not gated on completed authorization'

assert_not_contains "$QML" 'awtarchy-scxctl-auth' \
  'Quick Settings still launches a terminal for sched-ext authorization'
assert_not_contains "$QML" 'terminalLauncher, "--class", "awtarchy-scxctl-auth"' \
  'sched-ext authorization still depends on the terminal launcher'

assert_contains "$BACKEND" 'machine_scheduler_authorize_stdin()' \
  'backend has no stdin-only scheduler authorization function'
assert_contains "$BACKEND" 'ensure_scxctl_nopasswd_rule stdin 1' \
  'backend does not force repair the restricted sudoers rule during explicit authorization'
assert_contains "$BACKEND" -- '--authorize-scheduler-stdin)' \
  'backend has no stdin-only authorization entrypoint'
assert_not_contains "$BACKEND" -- '--authorize-scheduler)' \
  'obsolete terminal authorization entrypoint is still exposed'

printf '%s\n' 'PASS: Quick Settings provides masked inline sched-ext authorization over process stdin.'
