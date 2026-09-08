#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
THEME_APPLY="${ROOT}/config/hypr/scripts/quickshell_theme_apply.sh"
LOCK_THEME="${ROOT}/config/quickshell/awtarchy-lock/LockTheme.qml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_source() {
  local file="$1" expected="$2" description="$3"
  grep -Fq -- "$expected" "$file" || fail "$description"
}

require_source "$RUNTIME" \
  'active_theme="$(infer_active_theme "$repo_dir" || true)"' \
  'updater no longer resolves the persisted active theme before staging managed files'
require_source "$RUNTIME" \
  'apply_theme_to_target "$repo_dir" "$target_home" "$active_theme"' \
  'updater no longer reapplies the persisted theme to its staged target'
require_source "$RUNTIME" \
  '"lockAccent": f"#{active_border[:6]}",' \
  'updater theme staging omits the native lockscreen accent derived from the active border'

require_source "$THEME_APPLY" \
  'lock_accent="#${active_border:0:6}"' \
  'interactive theme apply no longer derives the lockscreen accent from the active border'
require_source "$THEME_APPLY" \
  '"lockAccent",' \
  'interactive theme apply no longer writes lockAccent to theme.json'
require_source "$LOCK_THEME" \
  'readonly property color lockAccent: value("lockAccent", "#a0a0a0")' \
  'native lockscreen no longer consumes the generated lockAccent theme value'

printf '%s\n' 'PASS: updater stages the persisted theme with the same native lockscreen accent as interactive theme apply.'
