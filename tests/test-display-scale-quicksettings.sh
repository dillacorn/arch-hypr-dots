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
  'display scale presets are not the approved 100/125/150/200 percent choices'
contains "$BAR_SETTINGS" '"bash", root.displayScaleScript, "set", root.monitorName' \
  'display scale action is not pinned to the current Quick Settings display'
contains "$BAR_SETTINGS" 'function displayScaleValid(value)' \
  'display scale presets are not checked against the current monitor resolution'
contains "$BAR_SETTINGS" '"bash", root.displayScaleScript, "status", root.monitorName' \
  'Bar Appearance does not refresh the current display scale'
contains "$SCALE_SCRIPT" 'hyprctl reload' \
  'display scale persistence does not reload Hyprland'
contains "$SCALE_SCRIPT" 'hyprctl configerrors' \
  'display scale persistence does not validate the reloaded Hyprland config'
contains "$SCALE_SCRIPT" '1|1.25|1.5|2)' \
  'display scale helper does not restrict writes to the approved presets'

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
    bash "$SCALE_SCRIPT" "$@"
}

status_json="$(run_scale status DP-1)"
jq -e '.scale == 1' <<<"$status_json" >/dev/null \
  || fail 'display scale status did not return the live scale'
jq -e '.width == 1920 and .height == 1080' <<<"$status_json" >/dev/null \
  || fail 'display scale status did not return the current monitor dimensions'

# Selecting the live scale is a no-op: do not rewrite or reload Hyprland.
cp "$TMP/hyprland.lua" "$TMP/before-noop.lua"
: >"$TMP/hyprctl.log"
run_scale set DP-1 1 >/dev/null
cmp -s "$TMP/hyprland.lua" "$TMP/before-noop.lua" \
  || fail 'unchanged display scale rewrote hyprland.lua'
if grep -Fqx 'reload' "$TMP/hyprctl.log"; then
  fail 'unchanged display scale unnecessarily reloaded Hyprland'
fi

# Existing explicit monitor: change only its scale and preserve the rest of the rule.
run_scale set DP-1 1.25
contains "$TMP/hyprland.lua" 'output = "DP-1", mode = "1920x1080@144", position = "0x0", scale = 1.25, vrr = 1' \
  'explicit monitor scale was not persisted without disturbing its other fields'
contains "$TMP/hyprland.lua" 'output = "DP-2"' \
  'changing the focused display removed another display rule'

# Missing explicit monitor: clone the fallback rule and change only output + scale.
run_scale set DP-3 1.5
contains "$TMP/hyprland.lua" 'output = "DP-3", mode = "preferred", position = "auto", scale = 1.5, vrr = 0' \
  'display without an explicit rule did not receive a safe clone of the fallback rule'

# Unsupported presets must be rejected without changing the config.
cp "$TMP/hyprland.lua" "$TMP/before-invalid.lua"
if run_scale set DP-1 1.33 >/dev/null 2>&1; then
  fail 'unsupported display scale 1.33 was accepted'
fi
cmp -s "$TMP/hyprland.lua" "$TMP/before-invalid.lua" \
  || fail 'invalid display scale modified hyprland.lua'

# Presets that would create fractional logical pixels must be rejected.
if run_scale set DP-2 1.5 >/dev/null 2>&1; then
  fail 'resolution-incompatible display scale was accepted'
fi
cmp -s "$TMP/hyprland.lua" "$TMP/before-invalid.lua" \
  || fail 'resolution-incompatible display scale modified hyprland.lua'

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
  if [[ $rel == .config/* ]]; then
    source_file="${ROOT}/config/${rel#.config/}"
  else
    source_file="${ROOT}/${rel}"
  fi
  digest="$(sha256sum "$source_file" | awk '{print $1}')"
  if ! grep -Fq -- "$digest"$'\t'"$rel" "$HISTORY"; then
    printf 'MISSING_HISTORY_HASH: %s\t%s\n' "$digest" "$rel" >&2
    missing_history=1
  fi
done
[[ $missing_history -eq 0 ]] \
  || fail 'managed history is missing current display-scale stock hashes'

printf '%s\n' 'PASS: Quick Settings display scale is focused-display-only, persistent, validated, and rollback-safe.'
