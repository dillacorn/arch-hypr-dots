#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QUICK_SETTINGS="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
FLYOUT_SETTINGS="$ROOT/config/quickshell/awtarchy/FlyoutSettings.qml"
BAR_SETTINGS="$ROOT/config/quickshell/awtarchy/BarSettingsSection.qml"
MANAGER="$ROOT/config/hypr/scripts/quickshell.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

fakebin="$TMP/bin"
cache_home="$TMP/cache"
mkdir -p "$fakebin" "$cache_home/awtarchy"

cat >"$fakebin/qs" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$fakebin/hyprctl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == 'monitors -j' || "$*" == '-j monitors' ]]; then
    printf '%s\n' '[{"name":"DP-1"},{"name":"DP-2"}]'
    exit 0
fi
exit 1
EOF
chmod +x "$fakebin/qs" "$fakebin/hyprctl"

cat >"$cache_home/awtarchy/quickshell-state.json" <<'EOF'
{
  "enabled": true,
  "monitors": {
    "DP-1": {
      "position": "bottom",
      "enabled": true,
      "bar_size": 42,
      "icon_scale": 125,
      "text_scale": 110,
      "bar_transparency": 35,
      "show_tasks": false,
      "theme_task_icons": true,
      "theme_tray_icons": true,
      "show_cpu": false,
      "show_temp": true,
      "show_memory": false,
      "last_horizontal": "bottom",
      "last_vertical": "left",
      "display_scale": 1.25
    },
    "DP-2": {
      "position": "top",
      "enabled": false,
      "bar_size": 30,
      "icon_scale": 90,
      "text_scale": 95,
      "bar_transparency": 5,
      "show_tasks": true,
      "theme_task_icons": false,
      "theme_tray_icons": false,
      "show_cpu": true,
      "show_temp": false,
      "show_memory": true,
      "last_horizontal": "top",
      "last_vertical": "right",
      "display_scale": 2
    }
  }
}
EOF

HOME="$TMP/home" \
XDG_CACHE_HOME="$cache_home" \
PATH="$fakebin:/usr/bin:/bin" \
    bash "$MANAGER" copy-bar-settings DP-1 DP-2 >/dev/null

state="$cache_home/awtarchy/quickshell-state.json"
jq -e '
    .monitors["DP-2"] as $target
    | .monitors["DP-1"] as $source
    | ($target.position == $source.position)
      and ($target.bar_size == $source.bar_size)
      and ($target.icon_scale == $source.icon_scale)
      and ($target.text_scale == $source.text_scale)
      and ($target.bar_transparency == $source.bar_transparency)
      and ($target.show_tasks == $source.show_tasks)
      and ($target.theme_task_icons == $source.theme_task_icons)
      and ($target.theme_tray_icons == $source.theme_tray_icons)
      and ($target.show_cpu == $source.show_cpu)
      and ($target.show_temp == $source.show_temp)
      and ($target.show_memory == $source.show_memory)
      and ($target.last_horizontal == $source.last_horizontal)
      and ($target.last_vertical == $source.last_vertical)
' "$state" >/dev/null || fail 'copy-bar-settings did not copy the bar state controlled by Bar Settings'

jq -e '.monitors["DP-2"].enabled == false' "$state" >/dev/null \
    || fail 'copy-bar-settings unexpectedly copied bar enabled state'
jq -e '.monitors["DP-2"].display_scale == 2' "$state" >/dev/null \
    || fail 'copy-bar-settings unexpectedly copied display scale'

contains "$QUICK_SETTINGS" 'visible: !root.settingsOpen' \
    'normal Quick Settings content is not hidden while settings mode is open'
contains "$FLYOUT_SETTINGS" 'text: root.surfaceLabel === "Quick Settings" ? "Copy Quick Settings…" : "Copy to Displays…"' \
    'generic Quick Settings copy action is not clearly scoped'
contains "$BAR_SETTINGS" 'label: "Copy Bar Settings…"' \
    'Bar Settings has no dedicated copy action'
contains "$BAR_SETTINGS" 'copy-bar-settings' \
    'Bar Settings copy action is not persisted through the existing manager'
contains "$MANAGER" 'copy-bar-settings)' \
    'quickshell manager has no copy-bar-settings command'

printf '%s\n' 'PASS: Quick Settings settings mode is isolated and copy actions have explicit scopes.'
