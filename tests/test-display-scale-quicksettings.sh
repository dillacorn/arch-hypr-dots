#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${ROOT}/config/hypr/scripts/hypr_quicksettings.sh"
BAR_SETTINGS="${ROOT}/config/quickshell/awtarchy/BarSettingsSection.qml"
FLYOUT_SETTINGS="${ROOT}/config/quickshell/awtarchy/FlyoutSettings.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
HISTORY="${ROOT}/local/share/awtarchy/quickshell-managed-history.sha256"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "$3"; }

contains "$BAR_SETTINGS" 'text: "Display scale"' \
  'Bar Appearance does not expose a display scale row'
contains "$BAR_SETTINGS" 'readonly property var displayScalePresets: [1, 1.25, 1.5, 2]' \
  'display scale presets are not the approved 100/125/150/200 percent choices'
contains "$BAR_SETTINGS" '"--action", "display-scale", root.monitorName' \
  'display scale action is not pinned to the current Quick Settings display'
contains "$BAR_SETTINGS" 'function displayScaleValid(value)' \
  'display scale presets are not checked against the current monitor resolution'
contains "$FLYOUT_SETTINGS" 'property real displayScale: 1' \
  'Flyout Settings does not receive the live display scale'
contains "$FLYOUT_SETTINGS" 'displayScale: root.displayScale' \
  'Bar Appearance does not receive the live display scale'
contains "$QUICK_SETTINGS" 'function activeMonitorStatus()' \
  'Quick Settings does not resolve live status for its active display'
contains "$QUICK_SETTINGS" 'displayScale: Number(root.activeMonitorStatus().scale || 1)' \
  'Quick Settings does not pass the focused display scale into Bar Appearance'
contains "$BACKEND" 'display-scale)' \
  'Quick Settings backend does not expose a display-scale action'
contains "$BACKEND" 'scale:((.scale // 1) | tonumber)' \
  'Quick Settings status does not report each monitor scale'
contains "$BACKEND" 'hyprctl reload' \
  'display scale persistence does not reload Hyprland'
contains "$BACKEND" 'hyprctl configerrors' \
  'display scale persistence does not validate the reloaded Hyprland config'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat >"$TMP/bin/hyprctl" <<'EOF_HYPRCTL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${HYPRCTL_LOG:?}"
case "$*" in
  '-j monitors'|'monitors -j')
    cat <<'JSON'
[
  {"name":"DP-1","focused":true,"disabled":false,"width":1920,"height":1080,"scale":1.0},
  {"name":"DP-2","focused":false,"disabled":false,"width":2560,"height":1440,"scale":1.25},
  {"name":"DP-3","focused":false,"disabled":false,"width":1920,"height":1080,"scale":1.0}
]
JSON
    ;;
  'reload')
    [[ ${HYPRCTL_RELOAD_FAIL:-0} != 1 ]]
    ;;
  'configerrors')
    [[ ${HYPRCTL_CONFIG_ERROR:-0} != 1 ]] || printf '%s\n' 'mock config error'
    ;;
  *)
    exit 0
    ;;
esac
EOF_HYPRCTL
chmod +x "$TMP/bin/hyprctl"

cat >"$TMP/hyprland.lua" <<'EOF_LUA'
-- monitor defaults
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1, vrr = 0 })
hl.monitor({ output = "DP-1", mode = "1920x1080@144", position = "0x0", scale = 1, vrr = 1 })
hl.monitor({
    output = "DP-2",
    mode = "2560x1440@165",
    position = "1920x0",
    scale = 1.25,
    vrr = 0,
})
EOF_LUA
cp "$TMP/hyprland.lua" "$TMP/original.lua"
: >"$TMP/hyprctl.log"

run_backend() {
  env \
    PATH="$TMP/bin:$PATH" \
    HYPRLAND_LUA="$TMP/hyprland.lua" \
    HYPRCTL_LOG="$TMP/hyprctl.log" \
    "$@" \
    "$BACKEND"
}

# Existing explicit monitor: change only its scale and preserve the rest of the rule.
env PATH="$TMP/bin:$PATH" HYPRLAND_LUA="$TMP/hyprland.lua" HYPRCTL_LOG="$TMP/hyprctl.log" \
  "$BACKEND" --action display-scale DP-1 1.25
contains "$TMP/hyprland.lua" 'output = "DP-1", mode = "1920x1080@144", position = "0x0", scale = 1.25, vrr = 1' \
  'explicit monitor scale was not persisted without disturbing its other fields'
contains "$TMP/hyprland.lua" 'output = "DP-2"' \
  'changing the focused display removed another display rule'
contains "$TMP/hyprland.lua" 'scale = 1.25,' \
  'multiline monitor rule was unexpectedly rewritten while changing another display'

# Missing explicit monitor: clone the fallback rule and change only output + scale.
env PATH="$TMP/bin:$PATH" HYPRLAND_LUA="$TMP/hyprland.lua" HYPRCTL_LOG="$TMP/hyprctl.log" \
  "$BACKEND" --action display-scale DP-3 1.5
contains "$TMP/hyprland.lua" 'output = "DP-3", mode = "preferred", position = "auto", scale = 1.5, vrr = 0' \
  'display without an explicit rule did not receive a safe clone of the fallback rule'

# Unsupported presets must be rejected without changing the config.
cp "$TMP/hyprland.lua" "$TMP/before-invalid.lua"
if env PATH="$TMP/bin:$PATH" HYPRLAND_LUA="$TMP/hyprland.lua" HYPRCTL_LOG="$TMP/hyprctl.log" \
    "$BACKEND" --action display-scale DP-1 1.33 >/dev/null 2>&1; then
  fail 'unsupported display scale 1.33 was accepted'
fi
cmp -s "$TMP/hyprland.lua" "$TMP/before-invalid.lua" \
  || fail 'invalid display scale modified hyprland.lua'

# Reload failure must restore the exact pre-change config and attempt a rollback reload.
cp "$TMP/hyprland.lua" "$TMP/before-failure.lua"
: >"$TMP/hyprctl.log"
if env PATH="$TMP/bin:$PATH" HYPRLAND_LUA="$TMP/hyprland.lua" HYPRCTL_LOG="$TMP/hyprctl.log" HYPRCTL_RELOAD_FAIL=1 \
    "$BACKEND" --action display-scale DP-1 1 >/dev/null 2>&1; then
  fail 'display scale action succeeded even though Hyprland reload failed'
fi
cmp -s "$TMP/hyprland.lua" "$TMP/before-failure.lua" \
  || fail 'Hyprland reload failure did not restore the original config'
[[ "$(grep -Fxc 'reload' "$TMP/hyprctl.log")" -ge 2 ]] \
  || fail 'rollback path did not attempt to reload the restored config'

# A post-reload config error must also roll back the persisted file.
cp "$TMP/hyprland.lua" "$TMP/before-configerror.lua"
if env PATH="$TMP/bin:$PATH" HYPRLAND_LUA="$TMP/hyprland.lua" HYPRCTL_LOG="$TMP/hyprctl.log" HYPRCTL_CONFIG_ERROR=1 \
    "$BACKEND" --action display-scale DP-1 1 >/dev/null 2>&1; then
  fail 'display scale action succeeded despite Hyprland config errors'
fi
cmp -s "$TMP/hyprland.lua" "$TMP/before-configerror.lua" \
  || fail 'Hyprland config error did not restore the original config'

# Managed history must track the current stock files touched by this feature.
for rel in \
  .config/hypr/scripts/hypr_quicksettings.sh \
  .config/quickshell/awtarchy/BarSettingsSection.qml \
  .config/quickshell/awtarchy/FlyoutSettings.qml \
  .config/quickshell/awtarchy/QuickSettings.qml
do
  source_file="${ROOT}/${rel#.}"
  if [[ $rel == .config/* ]]; then
    source_file="${ROOT}/config/${rel#.config/}"
  fi
  digest="$(sha256sum "$source_file" | awk '{print $1}')"
  grep -Fq -- "$digest"$'\t'"$rel" "$HISTORY" \
    || fail "managed history is missing current display-scale stock hash for $rel"
done

printf '%s\n' 'PASS: Quick Settings display scale is focused-display-only, persistent, validated, and rollback-safe.'
