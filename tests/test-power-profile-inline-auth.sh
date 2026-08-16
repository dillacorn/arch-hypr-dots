#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML="${ROOT}/config/quickshell/awtarchy/PowerModeCard.qml"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"

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

[[ -f "$HELPER" ]] || fail 'trusted Power Mode helper is missing'
[[ $(head -n1 -- "$HELPER") == '#!/usr/bin/bash' ]] \
  || fail 'Power Mode helper does not use fixed /usr/bin/bash interpreter'

assert_contains "$QML" 'property bool setupAuthOpen: false' \
  'Power Mode card has no inline authorization state'
assert_contains "$QML" 'id: setupAuthRunner' \
  'Power Mode card has no tracked authorization process'
assert_contains "$QML" 'stdinEnabled: true' \
  'Power Mode authorization process does not accept password on stdin'
assert_contains "$QML" 'echoMode: TextInput.Password' \
  'Power Mode password input is not masked'
assert_contains "$QML" 'setupPasswordInput.text = "";' \
  'Power Mode password field is not cleared after submission'
assert_contains "$QML" '"/usr/bin/sudo", "-S", "-p", ""' \
  'Power Mode authorization does not use fixed sudo stdin arguments'
assert_contains "$QML" '"/usr/local/libexec/awtarchy/power-profile-helper"' \
  'Power Mode authorization does not invoke the trusted root-owned helper'
assert_contains "$QML" 'root.conflictDetected ? "resolve-tlp-conflict" : "setup"' \
  'Power Mode authorization does not restrict setup to fixed helper actions'

assert_not_contains "$QML" 'terminalLauncher' \
  'Power Mode card still depends on a terminal launcher'
assert_not_contains "$QML" 'setupScript' \
  'Power Mode card still executes the user-writable setup script'
assert_not_contains "$QML" 'awtarchy-power-mode-setup' \
  'Power Mode card still opens the terminal setup window'
assert_not_contains "$QML" 'setupTerminal' \
  'Power Mode card still contains the terminal setup process'

assert_contains "$HELPER" '[[ $# -eq 1 ]]' \
  'Power Mode helper does not reject extra arguments'
assert_contains "$HELPER" 'setup|resolve-tlp-conflict)' \
  'Power Mode helper does not restrict actions to the fixed allowlist'
assert_contains "$HELPER" '/usr/bin/pacman' \
  'Power Mode helper does not use the fixed pacman path'
assert_contains "$HELPER" '/usr/bin/systemctl' \
  'Power Mode helper does not use the fixed systemctl path'
assert_contains "$HELPER" 'grep -Fx -- "$1"' \
  'Power Mode helper does not use exact package-name matching'
assert_not_contains "$HELPER" 'eval ' \
  'Power Mode helper contains eval'
assert_not_contains "$HELPER" 'bash -c' \
  'Power Mode helper contains arbitrary bash -c execution'
assert_not_contains "$HELPER" 'sh -c' \
  'Power Mode helper contains arbitrary sh -c execution'

if "$HELPER" setup extra >/dev/null 2>&1; then
  fail 'Power Mode helper accepted extra arguments'
fi
if "$HELPER" arbitrary-action >/dev/null 2>&1; then
  fail 'Power Mode helper accepted an unknown action'
fi

printf '%s\n' 'PASS: Power Mode uses masked inline authorization through a restricted root-owned helper.'
