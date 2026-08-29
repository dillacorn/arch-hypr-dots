#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BAR="${ROOT}/config/quickshell/awtarchy/Bar.qml"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"

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

printf '%s\n' 'Workspace focus highlight regression test passed.'
