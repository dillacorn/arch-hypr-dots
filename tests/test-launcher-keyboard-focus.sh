#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="${ROOT}/config/quickshell/awtarchy/Launcher.qml"
POSITIONER="${ROOT}/config/hypr/scripts/quickshell_launcher_position.sh"
HYPRLAND="${ROOT}/config/hypr/hyprland.lua"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_source() {
  local file="$1" expected="$2" description="$3"
  grep -Fq -- "$expected" "$file" || fail "$description"
}

# Give the search item QML focus, then start Hyprland's focus-grab protocol
# with only the launcher surface. This produces keyboard entry without a
# compositor focus dispatcher or any pointer operation. Bar surfaces may join
# only after the launcher has been the sole initial keyboard target.
require_source "$LAUNCHER" 'search.forceActiveFocus();' \
  'launcher search field is not assigned active QML focus'
require_source "$LAUNCHER" 'property bool launcherFocusGrabExpanded: false' \
  'launcher does not track staged focus-grab expansion'
require_source "$LAUNCHER" 'windows: root.launcherFocusGrabExpanded' \
  'launcher does not stage its focus-grab whitelist'
require_source "$LAUNCHER" '            : [launcherWindow]' \
  'launcher is not the sole initial focus-grab surface'
require_source "$LAUNCHER" 'root.launcherFocusGrabExpanded = true;' \
  'launcher never expands its focus-grab whitelist after activation'

# Application results and keyboard navigation must keep the same top-to-bottom
# direction regardless of whether the bar itself is attached to the top or
# bottom edge. The bottom layout may move the search/settings row, but it must
# not reverse the application model or arrow-key direction.
require_source "$LAUNCHER" 'verticalLayoutDirection: GridView.TopToBottom' \
  'launcher application results are not always laid out top-to-bottom'
require_source "$LAUNCHER" 'Layout.row: root.bottomEdgeLayout ? 2 : 0' \
  'bottom launcher search/settings row placement changed'
require_source "$LAUNCHER" 'Layout.row: root.bottomEdgeLayout ? 0 : 2' \
  'bottom launcher application-list placement changed'
require_source "$LAUNCHER" 'Math.max(0, appList.currentIndex) + appList.columnCount);' \
  'Down-key launcher navigation does not move forward through results'
require_source "$LAUNCHER" 'Math.max(0, appList.currentIndex) - appList.columnCount);' \
  'Up-key launcher navigation does not move backward through results'

for forbidden in \
  'verticalLayoutDirection: root.bottomEdgeLayout' \
  'const downIndex = root.bottomEdgeLayout' \
  'const upIndex = root.bottomEdgeLayout' \
  'hl.dsp.focus(' \
  'dispatch focuswindow' \
  'dispatch movecursor' \
  'hl.dsp.cursor' \
  'requestActivate' \
  'warpCursor' \
  'setCursorPosition'
do
  if grep -Fq -- "$forbidden" "$LAUNCHER" "$POSITIONER"; then
    fail "launcher keyboard/result path contains forbidden operation: ${forbidden}"
  fi
done

# Mouse mode is intentionally pointer-only. Bare keyboard binds inside this
# submap steal characters, Escape, or Return from focused applications such as
# the Quickshell launcher, so only mouse buttons and modified submap toggles may
# remain there.
mouse_block="$(awk '
  /hl\.define_submap\("mouse", function\(\)/ { in_mouse = 1 }
  in_mouse { print }
  in_mouse && /VIRTUAL MACHINE SUBMAP/ { exit }
' "$HYPRLAND")"

[[ -n "$mouse_block" ]] || fail 'mouse submap block was not found in hyprland.lua'

for forbidden in \
  'for _, bind in ipairs(resize_keys) do' \
  'hl.bind("Escape",' \
  'hl.bind("Return",'
do
  if grep -Fq -- "$forbidden" <<<"$mouse_block"; then
    fail "mouse submap still consumes normal keyboard input: ${forbidden}"
  fi
done

for required in \
  'hl.bind("mouse:272", hl.dsp.window.drag(), { mouse = true })' \
  'hl.bind("mouse:273", hl.dsp.window.resize(), { mouse = true })' \
  'hl.bind("mouse:274", hl.dsp.window.float({ action = "toggle" }), {})' \
  'hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd(mouse_off), {})' \
  'hl.bind("SUPER + ALT + N", hl.dsp.exec_cmd(noalt_on), {})' \
  'hl.bind("SUPER + ALT + V", hl.dsp.exec_cmd(vm_on), {})'
do
  grep -Fq -- "$required" <<<"$mouse_block" \
    || fail "mouse submap lost required pointer/toggle behavior: ${required}"
done

# v3.4.2 is already published with the old mouse block. The maintenance runtime
# refreshes from main before a stable config update, so it must repair the
# generated v3.4.2 target before baseline comparison/three-way merging. That lets
# `awtarchy update` apply only this fix while preserving unrelated hyprland.lua
# edits.
require_source "$RUNTIME" 'repair_v342_mouse_submap_target()' \
  'runtime is missing the v3.4.2 mouse-submap post-release repair'
require_source "$RUNTIME" '[[ "$tag" == "v3.4.2" ]] || return 0' \
  'v3.4.2 mouse-submap repair is not scoped to the published release'
require_source "$RUNTIME" 'repair_v342_mouse_submap_target "$target_home" "$tag"' \
  'runtime does not apply the v3.4.2 repair to the generated target'
require_source "$RUNTIME" 'git merge-file -p -- "$local_file" "$baseline_file" "$target_file" >"$out"' \
  'preserve mode no longer three-way merges local Hyprland edits against the repaired target'
require_source "$RUNTIME" 'if attempt_merge "$local_file" "$baseline_file" "$target_file" "$rel" "$merge_tmp"; then' \
  'Hyprland BOTH changes no longer use the preserve-mode three-way merge path'

prepare_line="$(grep -nF 'prepare_quickshell_update_target "$target_home"' "$RUNTIME" | head -n1 | cut -d: -f1)"
repair_line="$(grep -nF 'repair_v342_mouse_submap_target "$target_home" "$tag"' "$RUNTIME" | head -n1 | cut -d: -f1)"
baseline_line="$(grep -nF 'bootstrap_previous_baseline "$active_theme"' "$RUNTIME" | head -n1 | cut -d: -f1)"

[[ "$prepare_line" =~ ^[0-9]+$ && "$repair_line" =~ ^[0-9]+$ && "$baseline_line" =~ ^[0-9]+$ ]] \
  || fail 'could not locate updater target-repair ordering'
(( prepare_line < repair_line && repair_line < baseline_line )) \
  || fail 'v3.4.2 target repair must run after target preparation and before baseline comparison'

# Exercise the same three-way merge used by preserve mode. Build an old v3.4.2
# baseline from the repaired source, add a user-only edit outside the mouse block,
# then merge the repaired target. Both the user edit and post-release fix must
# survive without conflict.
merge_tmpdir="$(mktemp -d)"
trap 'rm -rf -- "$merge_tmpdir"' EXIT
baseline_copy="${merge_tmpdir}/baseline.lua"
local_copy="${merge_tmpdir}/local.lua"
merged_copy="${merge_tmpdir}/merged.lua"

python3 - "$HYPRLAND" "$baseline_copy" "$local_copy" <<'PY'
from pathlib import Path
import sys

target_path, baseline_path, local_path = map(Path, sys.argv[1:])
text = target_path.read_text(encoding="utf-8")
start = text.index('hl.define_submap("mouse", function()')
end = text.index('\nend)', start) + len('\nend)')
fixed = text[start:end]

pointer_header = '''    -- Pointer-only window controls. Keep normal keyboard input available to
    -- focused applications while mouse mode is active.
'''
resize_block = '''    -- Resize (MOUSE-left/right / hold)
    for _, bind in ipairs(resize_keys) do
        hl.bind(bind[1], hl.dsp.window.resize({ x = bind[2], y = bind[3], relative = true }), { repeating = true })
    end

'''
float_bind = '    hl.bind("mouse:274", hl.dsp.window.float({ action = "toggle" }), {})\n'
old_exits = '''    hl.bind("Escape", hl.dsp.exec_cmd(mouse_off), {})
    hl.bind("Return", hl.dsp.exec_cmd(mouse_off), {})
'''

if pointer_header not in fixed or float_bind not in fixed:
    raise SystemExit("repaired mouse block does not match expected test anchor")
old = fixed.replace(pointer_header, resize_block, 1)
old = old.replace(float_bind, float_bind + old_exits, 1)
baseline = text[:start] + old + text[end:]
marker_anchor = '-- github.com/dillacorn/awtarchy/tree/main/config/hypr\n'
if marker_anchor not in baseline:
    raise SystemExit("user-edit marker anchor missing")
local = baseline.replace(marker_anchor, marker_anchor + '-- USER-PRESERVE-MARKER\n', 1)

baseline_path.write_text(baseline, encoding="utf-8")
local_path.write_text(local, encoding="utf-8")
PY

if ! git merge-file -p -- "$local_copy" "$baseline_copy" "$HYPRLAND" >"$merged_copy"; then
  fail 'v3.4.2 post-release repair conflicts with an unrelated hyprland.lua user edit'
fi

grep -Fq -- '-- USER-PRESERVE-MARKER' "$merged_copy" \
  || fail 'three-way merge dropped an unrelated hyprland.lua user edit'
merged_mouse_block="$(awk '
  /hl\.define_submap\("mouse", function\(\)/ { in_mouse = 1 }
  in_mouse { print }
  in_mouse && /VIRTUAL MACHINE SUBMAP/ { exit }
' "$merged_copy")"
for forbidden in \
  'for _, bind in ipairs(resize_keys) do' \
  'hl.bind("Escape",' \
  'hl.bind("Return",'
do
  if grep -Fq -- "$forbidden" <<<"$merged_mouse_block"; then
    fail "three-way merge retained obsolete mouse-submap keyboard bind: ${forbidden}"
  fi
done

printf '%s\n' 'Launcher keyboard focus, result-direction, mouse-submap, and v3.4.2 preserve-merge regression tests passed.'
