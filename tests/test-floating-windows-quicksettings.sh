#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/config/hypr/scripts/quickshell_floating_windows.sh"
CARD="${ROOT}/config/quickshell/awtarchy/FloatingWindowsCard.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
HYPR_LUA="${ROOT}/config/hypr/hyprland.lua"
HISTORY="${ROOT}/local/share/awtarchy/quickshell-managed-history.sha256"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "$3"; }
absent() { ! grep -Fq -- "$2" "$1" || fail "$3"; }

[[ -x "$HELPER" ]] || fail 'floating windows helper is missing or not executable'
[[ -f "$CARD" ]] || fail 'Floating Windows Quick Settings card is missing'

# Stock Awtarchy remains tiled. The preference is opt-in and only changes the
# default map-time treatment of newly opened normal windows.
contains "$HYPR_LUA" 'local awtarchy_floating_windows = false -- AWTARCHY_FLOATING_WINDOWS' \
  'Floating Windows is not disabled by default in hyprland.lua'
contains "$HYPR_LUA" 'if awtarchy_floating_windows then' \
  'hyprland.lua does not conditionally apply the Floating Windows preference'
contains "$HYPR_LUA" 'hl.window_rule({ match = { class = ".*" }, float = true })' \
  'hyprland.lua lacks the catch-all native floating rule'

# The global float rule must not undermine Awtarchy's fullscreen game workflow.
# Keep games tiled underneath fullscreen, and keep later Steam force-tile rules.
global_float_line="$(grep -nF 'hl.window_rule({ match = { class = ".*" }, float = true })' "$HYPR_LUA" | head -n1 | cut -d: -f1)"
game_tile_line="$(grep -nF 'hl.window_rule({ match = { class = games }, tile = true })' "$HYPR_LUA" | head -n1 | cut -d: -f1)"
game_fullscreen_line="$(grep -nF 'hl.window_rule({ match = { class = games }, fullscreen = true })' "$HYPR_LUA" | head -n1 | cut -d: -f1)"
steam_tile_line="$(grep -nF 'title = "^(Steam)$" }, tile = true })' "$HYPR_LUA" | head -n1 | cut -d: -f1)"
[[ -n "$global_float_line" && -n "$game_tile_line" && -n "$game_fullscreen_line" && -n "$steam_tile_line" ]] \
  || fail 'could not locate Floating Windows precedence anchors'
[[ "$global_float_line" -lt "$game_tile_line" && "$game_tile_line" -lt "$game_fullscreen_line" \
    && "$global_float_line" -lt "$steam_tile_line" ]] \
  || fail 'global Floating Windows rule must preserve later game/force-tile rules'

# Manual per-window control remains available with or without the preference.
contains "$HYPR_LUA" '{ "SUPER + F", hl.dsp.window.float({ action = "toggle" }) },' \
  'existing SUPER+F per-window floating toggle changed or disappeared'

# The native window-behavior control belongs directly beside the existing title
# bar control and must not introduce another plugin or privileged workflow.
contains "$QUICK_SETTINGS" 'TitleBarsCard {' \
  'existing Title Bars card disappeared'
contains "$QUICK_SETTINGS" 'FloatingWindowsCard {' \
  'Quick Settings does not contain the Floating Windows card'
title_line="$(grep -nF 'TitleBarsCard {' "$QUICK_SETTINGS" | head -n1 | cut -d: -f1)"
floating_line="$(grep -nF 'FloatingWindowsCard {' "$QUICK_SETTINGS" | head -n1 | cut -d: -f1)"
[[ -n "$title_line" && -n "$floating_line" && "$floating_line" -gt "$title_line" ]] \
  || fail 'Floating Windows card is not adjacent after Title Bars'
contains "$CARD" 'text: "Window Behavior"' \
  'Floating Windows card is not identified as native window behavior'
contains "$CARD" 'text: "Floating Windows"' \
  'Floating Windows card is missing its user-facing label'
contains "$CARD" 'New windows open floating by default.' \
  'Floating Windows card does not explain enabled behavior'
contains "$CARD" 'Existing windows keep their current state.' \
  'Floating Windows card does not explain map-time behavior'
absent "$CARD" 'hyprpm' 'Floating Windows incorrectly depends on HyprPM'
absent "$CARD" 'sudo' 'Floating Windows incorrectly requires sudo'

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
TEST_LUA="${TMP}/hyprland.lua"
FAKE_HYPRCTL="${TMP}/hyprctl"
HYPRCTL_LOG="${TMP}/hyprctl.log"
CONFIGERROR_COUNT="${TMP}/configerrors.count"
cp -- "$HYPR_LUA" "$TEST_LUA"
: >"$HYPRCTL_LOG"
printf '0\n' >"$CONFIGERROR_COUNT"

cat >"$FAKE_HYPRCTL" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${FAKE_HYPRCTL_LOG:?}"
case "${1:-}" in
  configerrors)
    count="$(cat "${FAKE_CONFIGERROR_COUNT:?}")"
    count=$((count + 1))
    printf '%s\n' "$count" >"${FAKE_CONFIGERROR_COUNT}"
    if [[ -n ${FAKE_PRE_CONFIG_ERRORS:-} ]]; then
      printf '%s\n' "$FAKE_PRE_CONFIG_ERRORS"
    elif [[ -n ${FAKE_POST_CONFIG_ERRORS:-} && $count -ge 2 ]]; then
      printf '%s\n' "$FAKE_POST_CONFIG_ERRORS"
    fi
    ;;
  reload)
    [[ ${FAKE_RELOAD_FAIL:-0} != 1 ]] || exit 1
    ;;
esac
FAKE
chmod +x "$FAKE_HYPRCTL"

run_helper() {
  HYPRLAND_LUA="$TEST_LUA" \
  HYPRCTL="$FAKE_HYPRCTL" \
  FAKE_HYPRCTL_LOG="$HYPRCTL_LOG" \
  FAKE_CONFIGERROR_COUNT="$CONFIGERROR_COUNT" \
  "$HELPER" "$@"
}

[[ "$(run_helper status)" == "disabled" ]] \
  || fail 'stock Floating Windows status is not disabled'

# Existing Awtarchy users normally update in preserve mode, so their customized
# hyprland.lua can predate this feature. The card must still report Disabled and
# Enable must safely bootstrap only the small feature block without requiring a
# clean-slate overwrite of the user's configuration.
LEGACY_LUA="${TMP}/legacy-hyprland.lua"
python3 - "$HYPR_LUA" "$LEGACY_LUA" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
source = source.replace(
    'local awtarchy_floating_windows = false -- AWTARCHY_FLOATING_WINDOWS\n\n',
    '',
    1,
)
source = source.replace(
    'if awtarchy_floating_windows then\n'
    '    hl.window_rule({ match = { class = ".*" }, float = true })\n'
    '    hl.window_rule({ match = { class = games }, tile = true })\n'
    'end\n',
    '',
    1,
)
Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY
LEGACY_BEFORE="${TMP}/legacy-before.lua"
cp -- "$LEGACY_LUA" "$LEGACY_BEFORE"

run_legacy_helper() {
  HYPRLAND_LUA="$LEGACY_LUA" \
  HYPRCTL="$FAKE_HYPRCTL" \
  FAKE_HYPRCTL_LOG="$HYPRCTL_LOG" \
  FAKE_CONFIGERROR_COUNT="$CONFIGERROR_COUNT" \
  "$HELPER" "$@"
}

[[ "$(run_legacy_helper status)" == "disabled" ]] \
  || fail 'preserved pre-feature hyprland.lua is not treated as disabled'
[[ "$(run_legacy_helper set off)" == "disabled" ]] \
  || fail 'disabling an unbootstrapped preserved config did not remain disabled'
cmp -s "$LEGACY_LUA" "$LEGACY_BEFORE" \
  || fail 'disabling an unbootstrapped preserved config modified hyprland.lua'

printf '0\n' >"$CONFIGERROR_COUNT"
[[ "$(run_legacy_helper set on)" == "enabled" ]] \
  || fail 'enabling Floating Windows did not bootstrap a preserved pre-feature config'
contains "$LEGACY_LUA" 'local awtarchy_floating_windows = true -- AWTARCHY_FLOATING_WINDOWS' \
  'preserve-mode bootstrap did not persist the enabled marker'
contains "$LEGACY_LUA" 'hl.window_rule({ match = { class = ".*" }, float = true })' \
  'preserve-mode bootstrap did not add the native float rule'
contains "$LEGACY_LUA" 'hl.window_rule({ match = { class = games }, tile = true })' \
  'preserve-mode bootstrap did not preserve the game tiling override'

LEGACY_NORMALIZED="${TMP}/legacy-normalized.lua"
python3 - "$LEGACY_LUA" "$LEGACY_NORMALIZED" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
source = source.replace(
    'local awtarchy_floating_windows = true -- AWTARCHY_FLOATING_WINDOWS\n\n',
    '',
    1,
)
source = source.replace(
    '\nif awtarchy_floating_windows then\n'
    '    hl.window_rule({ match = { class = ".*" }, float = true })\n'
    '    hl.window_rule({ match = { class = games }, tile = true })\n'
    'end\n',
    '',
    1,
)
Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY
cmp -s "$LEGACY_NORMALIZED" "$LEGACY_BEFORE" \
  || fail 'preserve-mode bootstrap changed unrelated hyprland.lua content'

before_enable="${TMP}/before-enable.lua"
cp -- "$TEST_LUA" "$before_enable"
[[ "$(run_helper set on)" == "enabled" ]] \
  || fail 'enabling Floating Windows did not report enabled'
contains "$TEST_LUA" 'local awtarchy_floating_windows = true -- AWTARCHY_FLOATING_WINDOWS' \
  'enabling Floating Windows did not persist the true marker'
# A fresh helper process must recover the enabled state from hyprland.lua rather
# than relying on transient Quickshell/session state. This is what preserves the
# user's preference across relogins and reboots.
[[ "$(run_helper status)" == "enabled" ]] \
  || fail 'enabled Floating Windows state was not recovered from persisted hyprland.lua'
normalized="${TMP}/normalized.lua"
sed 's/local awtarchy_floating_windows = true -- AWTARCHY_FLOATING_WINDOWS/local awtarchy_floating_windows = false -- AWTARCHY_FLOATING_WINDOWS/' \
  "$TEST_LUA" >"$normalized"
cmp -s "$normalized" "$before_enable" \
  || fail 'enabling Floating Windows changed unrelated hyprland.lua content'
contains "$HYPRCTL_LOG" 'reload' 'enabling Floating Windows did not reload Hyprland'

[[ "$(run_helper set off)" == "disabled" ]] \
  || fail 'disabling Floating Windows did not report disabled'
cmp -s "$TEST_LUA" "$before_enable" \
  || fail 'disabling Floating Windows did not restore the exact stock config content'

if run_helper set banana >/dev/null 2>&1; then
  fail 'invalid Floating Windows state was accepted'
fi

# Existing Hyprland errors block writes.
pre_error_before="${TMP}/pre-error-before.lua"
cp -- "$TEST_LUA" "$pre_error_before"
printf '0\n' >"$CONFIGERROR_COUNT"
if FAKE_PRE_CONFIG_ERRORS='existing config error' run_helper set on >/dev/null 2>&1; then
  fail 'Floating Windows changed config despite pre-existing Hyprland errors'
fi
cmp -s "$TEST_LUA" "$pre_error_before" \
  || fail 'pre-existing config error path modified hyprland.lua'

# Failed reload restores the exact prior file.
printf '0\n' >"$CONFIGERROR_COUNT"
if FAKE_RELOAD_FAIL=1 run_helper set on >/dev/null 2>&1; then
  fail 'Floating Windows reported success after Hyprland reload failed'
fi
cmp -s "$TEST_LUA" "$pre_error_before" \
  || fail 'reload failure did not restore the exact prior hyprland.lua'

# A new config error after reload also restores and reloads the prior config.
printf '0\n' >"$CONFIGERROR_COUNT"
: >"$HYPRCTL_LOG"
if FAKE_POST_CONFIG_ERRORS='new config error' run_helper set on >/dev/null 2>&1; then
  fail 'Floating Windows reported success after post-reload config validation failed'
fi
cmp -s "$TEST_LUA" "$pre_error_before" \
  || fail 'post-reload config error did not restore the exact prior hyprland.lua'
reload_count="$(grep -c '^reload$' "$HYPRCTL_LOG" || true)"
[[ "$reload_count" -ge 2 ]] \
  || fail 'rollback did not reload the restored Hyprland configuration'

# Quickshell-era stock files must remain recognizable to the updater.
missing_history=0
for rel in \
  .config/hypr/scripts/quickshell_floating_windows.sh \
  .config/quickshell/awtarchy/FloatingWindowsCard.qml \
  .config/quickshell/awtarchy/QuickSettings.qml
do
  source_file="${ROOT}/config/${rel#.config/}"
  digest="$(sha256sum "$source_file" | awk '{print $1}')"
  if ! grep -Fq -- "$digest"$'\t'"$rel" "$HISTORY"; then
    printf 'MISSING_MANAGED_HASH %s\t%s\n' "$digest" "$rel" >&2
    missing_history=1
  fi
done
(( missing_history == 0 )) || fail 'managed history is missing current Floating Windows stock hashes'

printf '%s\n' 'PASS: Floating Windows is opt-in, persistent, native, preserve-mode compatible, and rollback-safe.'
