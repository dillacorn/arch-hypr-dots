#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_SCRIPT="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
FLYOUT_SETTINGS="${ROOT}/config/quickshell/awtarchy/FlyoutSettings.qml"
LAYOUT_EDITOR="${ROOT}/config/quickshell/awtarchy/QuickSettingsLayoutEditor.qml"
HISTORY="${ROOT}/local/share/awtarchy/quickshell-managed-history.sha256"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "$3"; }

DEFAULT_ORDER='["brightness","output-volume","power-mode","bar","display-effects","submap","wallpaper","awtarchy","smtty","scheduler","numlock","title-bars"]'
CUSTOM_ORDER='["bar","brightness","power-mode","output-volume","display-effects","submap","wallpaper","awtarchy","title-bars","numlock","scheduler","smtty"]'
HIDDEN='["scheduler","smtty"]'

[[ -f $LAYOUT_EDITOR ]] || fail 'Quick Settings layout editor component is missing'
contains "$BAR_STATE" 'quick_settings_layouts: {}' \
  'BarState does not own persisted per-monitor Quick Settings layouts'
contains "$BAR_STATE" 'function quickSettingsLayoutFor(name)' \
  'BarState does not expose normalized per-monitor Quick Settings layout state'
contains "$QUICK_SETTINGS" 'function quickSettingsSectionRow(sectionId)' \
  'Quick Settings sections do not derive rows from the per-monitor layout'
contains "$QUICK_SETTINGS" 'function quickSettingsSectionVisible(sectionId)' \
  'Quick Settings sections do not derive visibility from the per-monitor layout'
contains "$QUICK_SETTINGS" '"save-quick-settings-layout"' \
  'Quick Settings Save does not persist the current layout draft'
contains "$QUICK_SETTINGS" '"copy-quick-settings-layout"' \
  'Copy to Displays does not include the current Quick Settings layout draft'
contains "$QUICK_SETTINGS" '"reset-quick-settings-layout"' \
  'Reset Quick Settings does not restore the stock layout'
contains "$FLYOUT_SETTINGS" 'signal layoutEditorRequested()' \
  'Quick Settings flyout settings do not expose the layout editor action'
contains "$FLYOUT_SETTINGS" 'label: "Customize Layout…"' \
  'Quick Settings flyout settings do not expose Customize Layout'
contains "$LAYOUT_EDITOR" 'signal moveRequested(string sectionId, int delta)' \
  'layout editor does not expose section reordering'
contains "$LAYOUT_EDITOR" 'signal visibilityRequested(string sectionId, bool visible)' \
  'layout editor does not expose per-section visibility controls'

for section in \
  brightness output-volume power-mode bar display-effects submap \
  wallpaper awtarchy smtty scheduler numlock title-bars
do
  contains "$QUICK_SETTINGS" "quickSettingsSectionRow(\"${section}\")" \
    "Quick Settings section ${section} is not wired to dynamic row ordering"
  contains "$QUICK_SETTINGS" "quickSettingsSectionVisible(\"${section}\")" \
    "Quick Settings section ${section} is not wired to per-monitor visibility"
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/cache/awtarchy" "$TMP/home"
STATE_FILE="$TMP/cache/awtarchy/quickshell-state.json"

cat >"$STATE_FILE" <<'JSON'
{
  "enabled": true,
  "monitors": {"DP-1": {"position": "bottom"}},
  "quick_settings_views": {"DP-1": {"width": 900, "height": 800, "saved": true, "save_version": 2}},
  "unrelated": {"preserve": "yes"}
}
JSON

run_state() {
  env \
    HOME="$TMP/home" \
    XDG_CACHE_HOME="$TMP/cache" \
    HYPR_QUICKSHELL_SCRIPT="$TMP/missing-quickshell.sh" \
    bash "$STATE_SCRIPT" "$@"
}

run_state save-quick-settings-layout DP-1 "$CUSTOM_ORDER" "$HIDDEN"

jq -e --argjson order "$CUSTOM_ORDER" --argjson hidden "$HIDDEN" '
  .quick_settings_layouts["DP-1"].order == $order
  and .quick_settings_layouts["DP-1"].hidden == $hidden
  and .quick_settings_layouts["DP-1"].save_version == 1
  and .unrelated.preserve == "yes"
  and .monitors["DP-1"].position == "bottom"
' "$STATE_FILE" >/dev/null \
  || fail 'valid per-monitor layout was not persisted without disturbing unrelated state'

run_state copy-quick-settings-layout "$CUSTOM_ORDER" "$HIDDEN" DP-2 DP-3
jq -e '
  .quick_settings_layouts["DP-2"] == .quick_settings_layouts["DP-1"]
  and .quick_settings_layouts["DP-3"] == .quick_settings_layouts["DP-1"]
' "$STATE_FILE" >/dev/null \
  || fail 'Quick Settings layout draft was not copied identically to target displays'

cp "$STATE_FILE" "$TMP/before-invalid.json"
for invalid_order in \
  '["brightness","brightness","power-mode","bar","display-effects","submap","wallpaper","awtarchy","smtty","scheduler","numlock","title-bars"]' \
  '["brightness","output-volume","power-mode","bar","display-effects","submap","wallpaper","awtarchy","smtty","scheduler","numlock","unknown"]'
do
  if run_state save-quick-settings-layout DP-1 "$invalid_order" '[]' >/dev/null 2>&1; then
    fail 'invalid Quick Settings section order was accepted'
  fi
done

if run_state save-quick-settings-layout DP-1 "$DEFAULT_ORDER" "$DEFAULT_ORDER" >/dev/null 2>&1; then
  fail 'layout that hides every Quick Settings section was accepted'
fi
cmp -s "$STATE_FILE" "$TMP/before-invalid.json" \
  || fail 'rejected Quick Settings layout modified persistent state'

run_state reset-quick-settings-layout DP-1
jq -e '
  (.quick_settings_layouts["DP-1"] | not)
  and .quick_settings_layouts["DP-2"] != null
  and .unrelated.preserve == "yes"
' "$STATE_FILE" >/dev/null \
  || fail 'reset did not remove only the requested display layout'

# Managed history must recognize every stock file changed by this feature.
missing_history=0
for rel in \
  .config/hypr/scripts/quickshell_application_state.sh \
  .config/quickshell/awtarchy/BarState.qml \
  .config/quickshell/awtarchy/FlyoutSettings.qml \
  .config/quickshell/awtarchy/QuickSettings.qml \
  .config/quickshell/awtarchy/QuickSettingsLayoutEditor.qml
do
  source_file="${ROOT}/config/${rel#.config/}"
  digest="$(sha256sum "$source_file" | awk '{print $1}')"
  if ! grep -Fq -- "$digest"$'\t'"$rel" "$HISTORY"; then
    printf 'MISSING_HISTORY_HASH: %s\t%s\n' "$digest" "$rel" >&2
    missing_history=1
  fi
done
[[ $missing_history -eq 0 ]] \
  || fail 'managed history is missing current Quick Settings layout stock hashes'

printf '%s\n' 'PASS: Quick Settings layout customization is per-display, reorderable, hideable, copyable, resettable, and updater-safe.'
