#!/usr/bin/env bash
# shellcheck disable=SC2016,SC1090
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BAR="${ROOT}/config/quickshell/awtarchy/Bar.qml"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

focused_expr='normalBackground: modelData.urgent ? Theme.urgent : (modelData.focused ? Theme.subtleActive : "transparent")'
active_expr='normalBackground: modelData.urgent ? Theme.urgent : (modelData.active ? Theme.subtleActive : "transparent")'

[[ $(grep -Fc -- "$focused_expr" "$BAR") -eq 2 ]] \
  || fail 'horizontal and vertical workspace entries must highlight only the globally focused workspace'

if grep -Fq -- "$active_expr" "$BAR"; then
  fail 'workspace entries still use per-monitor active state for the focus highlight'
fi

grep -Fq 'repair_v342_workspace_focus_target()' "$RUNTIME" \
  || fail 'runtime is missing the v3.4.2 workspace-focus post-release target repair'
grep -Fq '[[ "$tag" == "v3.4.2" ]] || return 0' "$RUNTIME" \
  || fail 'v3.4.2 workspace-focus repair is not scoped to the published release'
grep -Fq '.config/quickshell/awtarchy/Bar.qml' "$RUNTIME" \
  || fail 'v3.4.2 workspace-focus repair does not target Bar.qml'
grep -Fq 'repair_v342_workspace_focus_target "$target_home" "$tag"' "$RUNTIME" \
  || fail 'runtime does not apply the v3.4.2 workspace-focus repair to the generated target'

prepare_line="$(grep -nF 'prepare_quickshell_update_target "$target_home"' "$RUNTIME" | head -n1 | cut -d: -f1)"
repair_line="$(grep -nF 'repair_v342_workspace_focus_target "$target_home" "$tag"' "$RUNTIME" | head -n1 | cut -d: -f1)"
baseline_line="$(grep -nF 'bootstrap_previous_baseline "$active_theme"' "$RUNTIME" | head -n1 | cut -d: -f1)"

[[ "$prepare_line" =~ ^[0-9]+$ && "$repair_line" =~ ^[0-9]+$ && "$baseline_line" =~ ^[0-9]+$ ]] \
  || fail 'could not locate workspace-focus target-repair ordering'
(( prepare_line < repair_line && repair_line < baseline_line )) \
  || fail 'v3.4.2 workspace-focus target repair must run before baseline comparison'

functions_file="${TMP}/workspace-focus-repair.sh"
awk '
  /^repair_v342_workspace_focus_target\(\) \{/ { capture=1 }
  capture { print }
  capture && /^}$/ { exit }
' "$RUNTIME" >"$functions_file"
grep -Fq 'repair_v342_workspace_focus_target()' "$functions_file" \
  || fail 'could not extract the real workspace-focus repair function'

die() {
  printf 'TEST DIE: %s\n' "$*" >&2
  return 1
}
log() { :; }
source "$functions_file"

v342_home="${TMP}/v342"
v341_home="${TMP}/v341"
mkdir -p \
  "${v342_home}/.config/quickshell/awtarchy" \
  "${v341_home}/.config/quickshell/awtarchy"
printf '%s\n%s\n' "$active_expr" "$active_expr" \
  >"${v342_home}/.config/quickshell/awtarchy/Bar.qml"
printf '%s\n%s\n' "$active_expr" "$active_expr" \
  >"${v341_home}/.config/quickshell/awtarchy/Bar.qml"

repair_v342_workspace_focus_target "$v342_home" v3.4.2
v342_bar="${v342_home}/.config/quickshell/awtarchy/Bar.qml"
[[ $(grep -Fc -- "$focused_expr" "$v342_bar") -eq 2 ]] \
  || fail 'real v3.4.2 repair did not convert both workspace highlights to focused state'
if grep -Fq -- "$active_expr" "$v342_bar"; then
  fail 'real v3.4.2 repair left a per-monitor active workspace highlight behind'
fi

repair_v342_workspace_focus_target "$v342_home" v3.4.2
[[ $(grep -Fc -- "$focused_expr" "$v342_bar") -eq 2 ]] \
  || fail 'v3.4.2 workspace-focus repair is not idempotent'

repair_v342_workspace_focus_target "$v341_home" v3.4.1
v341_bar="${v341_home}/.config/quickshell/awtarchy/Bar.qml"
[[ $(grep -Fc -- "$active_expr" "$v341_bar") -eq 2 ]] \
  || fail 'workspace-focus post-release repair changed a non-v3.4.2 target'
if grep -Fq -- "$focused_expr" "$v341_bar"; then
  fail 'workspace-focus post-release repair leaked into another release tag'
fi

printf '%s\n' 'Workspace focus highlight regression test passed.'
