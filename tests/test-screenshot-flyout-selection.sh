#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/config/hypr/scripts/screenshot_area.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "$3"; }

contains "$SCRIPT" 'suspend_flyout_outside_click()' \
  'screenshot capture does not suspend Awtarchy flyout outside-click dismissal'
contains "$SCRIPT" 'restore_flyout_outside_click()' \
  'screenshot capture does not restore Awtarchy flyout outside-click dismissal'
contains "$SCRIPT" 'awtarchy_flyout_outside_click_bind_v1:remove()' \
  'screenshot capture does not remove the conflicting compositor mouse bind'
contains "$SCRIPT" 'quickshell_runtime_rules.sh' \
  'screenshot capture cannot restore the normal Quickshell runtime rules'
contains "$SCRIPT" 'log_event "flyout-outside-click-suspended"' \
  'screenshot diagnostics do not record outside-click suspension'
contains "$SCRIPT" 'log_event "flyout-outside-click-restored"' \
  'screenshot diagnostics do not record outside-click restoration'

suspend_line="$(grep -nF 'suspend_flyout_outside_click' "$SCRIPT" | tail -n1 | cut -d: -f1)"
slurp_line="$(grep -nF 'slurp -b ' "$SCRIPT" | head -n1 | cut -d: -f1)"
restore_line="$(grep -nF 'restore_flyout_outside_click' "$SCRIPT" | tail -n1 | cut -d: -f1)"

[[ -n "$suspend_line" && -n "$slurp_line" && "$suspend_line" -lt "$slurp_line" ]] \
  || fail 'outside-click dismissal is not suspended before slurp starts'
[[ -n "$restore_line" && -n "$slurp_line" && "$restore_line" -gt "$slurp_line" ]] \
  || fail 'outside-click dismissal is not restored after slurp finishes'

cleanup_start="$(grep -nF 'cleanup() {' "$SCRIPT" | head -n1 | cut -d: -f1)"
cleanup_end="$(( cleanup_start + 15 ))"
sed -n "${cleanup_start},${cleanup_end}p" "$SCRIPT" \
  | grep -Fq 'restore_flyout_outside_click' \
  || fail 'cleanup does not restore outside-click dismissal after cancellation/error'

printf '%s\n' 'PASS: screenshot selection suppresses flyout outside-click dismissal only while slurp owns the pointer.'
