#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="${ROOT}/config/quickshell/awtarchy/Launcher.qml"
HELPER="${ROOT}/config/hypr/scripts/quickshell_launcher_usage.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_source() {
  local file="$1" expected="$2" description="$3"
  grep -Fq -- "$expected" "$file" || fail "$description"
}

[[ -x "$HELPER" ]] || fail 'launcher usage helper is missing or not executable'
command -v jq >/dev/null 2>&1 || fail 'jq is required for launcher usage test'

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"

"$HELPER" record org.mozilla.firefox.desktop
"$HELPER" record org.alacritty.Alacritty.desktop
"$HELPER" record org.mozilla.firefox.desktop

STATE="${XDG_CACHE_HOME}/awtarchy/launcher-usage.json"
[[ -s "$STATE" ]] || fail 'launcher usage state was not created'
jq -e '.version == 1' "$STATE" >/dev/null || fail 'launcher usage state version is invalid'
jq -e '.launches["org.mozilla.firefox.desktop"] == 2' "$STATE" >/dev/null \
  || fail 'Firefox launch count was not incremented to 2'
jq -e '.launches["org.alacritty.Alacritty.desktop"] == 1' "$STATE" >/dev/null \
  || fail 'Alacritty launch count was not recorded as 1'

"$HELPER" record org.alacritty.Alacritty.desktop
jq -e '.launches["org.alacritty.Alacritty.desktop"] == 2' "$STATE" >/dev/null \
  || fail 'Alacritty launch count was not incremented to 2'

printf '%s\n' '{not-json' >"$STATE"
"$HELPER" record org.keepassxc.KeePassXC.desktop
jq -e '.launches["org.keepassxc.KeePassXC.desktop"] == 1' "$STATE" >/dev/null \
  || fail 'corrupt launcher usage state did not recover safely'

require_source "$LAUNCHER" 'readonly property string launcherUsagePath:' \
  'launcher does not define the usage cache path'
require_source "$LAUNCHER" 'function launchCount(entry)' \
  'launcher does not expose launch counts for ranking'
require_source "$LAUNCHER" 'const aCount = launchCount(a.entry);' \
  'launcher sort does not read the first application launch count'
require_source "$LAUNCHER" 'const bCount = launchCount(b.entry);' \
  'launcher sort does not read the second application launch count'
require_source "$LAUNCHER" 'if (aCount !== bCount)' \
  'launcher sort does not prioritize launch frequency after fuzzy score'
require_source "$LAUNCHER" 'usageRecorder.exec(["bash", usageScript, "record", entryId]);' \
  'launcher does not record successful launcher selections'

printf '%s\n' 'Launcher usage ranking regression test passed.'
