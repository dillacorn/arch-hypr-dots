#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCALE_SCRIPT="${ROOT}/config/hypr/scripts/quickshell_display_scale.sh"
BAR_SETTINGS="${ROOT}/config/quickshell/awtarchy/BarSettingsSection.qml"
HISTORY="${ROOT}/local/share/awtarchy/quickshell-managed-history.sha256"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "$3"; }

[[ -f $SCALE_SCRIPT ]] || fail 'display scale helper is missing'
contains "$BAR_SETTINGS" 'text: "Display scale"' \
  'Bar Appearance does not expose a display scale row'
contains "$BAR_SETTINGS" 'readonly property var displayScalePresets: [1, 1.25, 1.5, 2]' \
  'display scale presets changed unexpectedly'
contains "$BAR_SETTINGS" 'function displayScaleLabel(value)' \
  'display scale presets are not presented as Hyprland scale factors'
contains "$BAR_SETTINGS" 'label: root.displayScaleLabel(Number(modelData))' \
  'display scale preset buttons do not show literal scale factors'
contains "$BAR_SETTINGS" 'label: "Custom"' \
  'display scale row has no Custom control'
contains "$BAR_SETTINGS" 'property bool customScaleOpen: false' \
  'custom display scale editor has no explicit open state'
contains "$BAR_SETTINGS" 'property string customScaleText:' \
  'custom display scale editor has no editable value'
contains "$BAR_SETTINGS" 'function applyCustomDisplayScale()' \
  'custom display scale editor has no apply path'
contains "$BAR_SETTINGS" 'TextInput {' \
  'custom display scale editor has no numeric input'
contains "$BAR_SETTINGS" 'label: "Apply"' \
  'custom display scale editor has no explicit Apply control'
contains "$BAR_SETTINGS" '"bash", root.displayScaleScript, "set", root.monitorName' \
  'display scale action is not pinned to the current Quick Settings display'
contains "$BAR_SETTINGS" 'function displayScaleValid(value)' \
  'display scale choices are not checked against the current monitor resolution'
contains "$BAR_SETTINGS" 'scale < 1 || scale > 4' \
  'custom display scale UI does not enforce the approved 1.0-4.0 safety range'
contains "$BAR_SETTINGS" '"bash", root.displayScaleScript, "status", root.monitorName' \
  'Bar Appearance does not refresh the current display scale'
contains "$BAR_SETTINGS" '|| Math.abs(displayScale - scale) < 0.001)' \
  'the active display scale is not ignored before invoking the persistence helper'
contains "$SCALE_SCRIPT" 'hyprctl reload' \
  'display scale persistence does not reload Hyprland'
contains "$SCALE_SCRIPT" 'hyprctl configerrors' \
  'display scale persistence does not validate the reloaded Hyprland config'
if grep -Fq '1|1.25|1.5|2)' "$SCALE_SCRIPT"; then
  fail 'display scale helper is still restricted to the original preset whitelist'
fi
contains "$SCALE_SCRIPT" "Decimal" \
  'display scale helper does not use exact decimal validation for custom scales'
contains "$SCALE_SCRIPT" 'Decimal("1")' \
  'display scale helper does not enforce the minimum custom scale'
contains "$SCALE_SCRIPT" 'Decimal("4")' \
  'display scale helper does not enforce the maximum custom scale'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat >"$TMP/bin/hyprctl" <<'EOF_HYPRCTL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${HYPRCTL_LOG:?}"
case "$*" in
  '-j monitors'|'monitors -j')
    dp1_scale="${HYPRCTL_DP1_SCALE:-1.0}"
    cat <<JSON
[
  {"name":"DP-1","focused":true,"disabled":false,"width":1920,"height":1080,"scale":${dp1_scale}},
  {"name":"DP-2","focused":false,"disabled":false,"width":2560,"height":1440,"scale":1.25},
  {"name":"DP-3","focused":false,"disabled":false,"width":1920,"height":1080,"scale":1.0}
]
JSON
    ;;
  'reload')
    [[ ${HYPRCTL_RELOAD_FAIL:-0} != 1 ]]
    ;;
  'configerrors')
    if [[ ${HYPRCTL_CONFIG_ERROR:-0} == 1 ]] && grep -Fqx 'reload' "${HYPRCTL_LOG:?}"; then
      printf '%s\n' 'mock config error'
    fi
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
: >"$TMP/hyprctl.log"

run_scale() {
  env \
    PATH="$TMP/bin:$PATH" \
    HYPRLAND_LUA="$TMP/hyprland.lua" \
    HYPRCTL_LOG="$TMP/hyprctl.log" \
    HYPRCTL_DP1_SCALE="${HYPRCTL_DP1_SCALE:-1.0}" \
    bash "$SCALE_SCRIPT" "$@"
}

status_json="$(run_scale status DP-1)"
jq -e '.scale == 1' <<<"$status_json" >/dev/null \
  || fail 'display scale status did not return the live scale'
jq -e '.width == 1920 and .height == 1080' <<<"$status_json" >/dev/null \
  || fail 'display scale status did not return the current monitor dimensions'

# Persisted target already matches, but live state drifted: reload the persisted rule without rewriting it.
cp "$TMP/hyprland.lua" "$TMP/before-drift-reconcile.lua"
: >"$TMP/hyprctl.log"
HYPRCTL_DP1_SCALE=1.25 run_scale set DP-1 1 >/dev/null
cmp -s "$TMP/hyprland.lua" "$TMP/before-drift-reconcile.lua" \
  || fail 'reconciling live display scale drift rewrote an already-correct hyprland.lua'
[[ "$(grep -Fxc 'reload' "$TMP/hyprctl.log")" -eq 1 ]] \
  || fail 'persisted display scale was not reapplied exactly once after live-state drift'

# Existing explicit monitor: change only its scale and preserve the rest of the rule.
run_scale set DP-1 1.25 >/dev/null
contains "$TMP/hyprland.lua" 'output = "DP-1", mode = "1920x1080@144", position = "0x0", scale = 1.25, vrr = 1' \
  'explicit monitor scale was not persisted without disturbing its other fields'
contains "$TMP/hyprland.lua" 'output = "DP-2"' \
  'changing the focused display removed another display rule'

# Custom scale: 1920x1080 / 1.2 = 1600x900, so this must be accepted and persisted.
run_scale set DP-1 1.2 >/dev/null
contains "$TMP/hyprland.lua" 'output = "DP-1", mode = "1920x1080@144", position = "0x0", scale = 1.2, vrr = 1' \
  'valid custom display scale 1.2 was not persisted'

# Missing explicit monitor: clone the fallback rule and change only output + scale.
run_scale set DP-3 1.5 >/dev/null
contains "$TMP/hyprland.lua" 'output = "DP-3", mode = "preferred", position = "auto", scale = 1.5, vrr = 0' \
  'display without an explicit rule did not receive a safe clone of the fallback rule'

cp "$TMP/hyprland.lua" "$TMP/before-invalid.lua"

# Values below the safety range must be rejected without changing the config.
if run_scale set DP-1 0.8 >/dev/null 2>&1; then
  fail 'display scale below 1.0 was accepted'
fi
cmp -s "$TMP/hyprland.lua" "$TMP/before-invalid.lua" \
  || fail 'below-range display scale modified hyprland.lua'

# Values above the safety range must be rejected without changing the config.
if run_scale set DP-1 4.1 >/dev/null 2>&1; then
  fail 'display scale above 4.0 was accepted'
fi
cmp -s "$TMP/hyprland.lua" "$TMP/before-invalid.lua" \
  || fail 'above-range display scale modified hyprland.lua'

# Non-numeric input must be rejected without changing the config.
if run_scale set DP-1 nope >/dev/null 2>&1; then
  fail 'non-numeric display scale was accepted'
fi
cmp -s "$TMP/hyprland.lua" "$TMP/before-invalid.lua" \
  || fail 'non-numeric display scale modified hyprland.lua'

# Numerically valid scales that create fractional logical pixels must be rejected.
if run_scale set DP-1 1.4 >/dev/null 2>&1; then
  fail 'resolution-incompatible custom display scale was accepted'
fi
cmp -s "$TMP/hyprland.lua" "$TMP/before-invalid.lua" \
  || fail 'resolution-incompatible custom display scale modified hyprland.lua'

# A preset can also be incompatible with a monitor resolution and must still be rejected.
if run_scale set DP-2 1.5 >/dev/null 2>&1; then
  fail 'resolution-incompatible preset display scale was accepted'
fi
cmp -s "$TMP/hyprland.lua" "$TMP/before-invalid.lua" \
  || fail 'resolution-incompatible preset display scale modified hyprland.lua'

# Reload failure must restore the exact pre-change config and attempt a rollback reload.
cp "$TMP/hyprland.lua" "$TMP/before-failure.lua"
: >"$TMP/hyprctl.log"
if HYPRCTL_RELOAD_FAIL=1 run_scale set DP-1 1 >/dev/null 2>&1; then
  fail 'display scale action succeeded even though Hyprland reload failed'
fi
cmp -s "$TMP/hyprland.lua" "$TMP/before-failure.lua" \
  || fail 'Hyprland reload failure did not restore the original config'
[[ "$(grep -Fxc 'reload' "$TMP/hyprctl.log")" -ge 2 ]] \
  || fail 'rollback path did not attempt to reload the restored config'

# A post-reload config error must also roll back the persisted file.
cp "$TMP/hyprland.lua" "$TMP/before-configerror.lua"
: >"$TMP/hyprctl.log"
if HYPRCTL_CONFIG_ERROR=1 run_scale set DP-1 1 >/dev/null 2>&1; then
  fail 'display scale action succeeded despite Hyprland config errors'
fi
cmp -s "$TMP/hyprland.lua" "$TMP/before-configerror.lua" \
  || fail 'Hyprland config error did not restore the original config'

# Managed history must track the current stock files touched by this feature.
missing_history=0
for rel in \
  .config/hypr/scripts/quickshell_display_scale.sh \
  .config/quickshell/awtarchy/BarSettingsSection.qml
do
  source_file="${ROOT}/config/${rel#.config/}"
  digest="$(sha256sum "$source_file" | awk '{print $1}')"
  if ! grep -Fq -- "$digest"$'\t'"$rel" "$HISTORY"; then
    printf 'MISSING_HISTORY_HASH: %s\t%s\n' "$digest" "$rel" >&2
    missing_history=1
  fi
done
[[ $missing_history -eq 0 ]] \
  || fail 'managed history is missing current display-scale stock hashes'

# Runtime retest remains visual: numeric labels, Custom editor, and focused-monitor UX.
printf '%s\n' 'PASS: Quick Settings display scale supports safe presets and custom focused-display scaling with rollback protection.'
