#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BAR_QML="${ROOT}/config/quickshell/awtarchy/Bar.qml"
BAR_SETTINGS="${ROOT}/config/quickshell/awtarchy/BarSettingsSection.qml"
MODULE_SCRIPT="${ROOT}/config/hypr/scripts/quickshell_bar_modules.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

absent() {
    ! grep -Fq -- "$2" "$1" || fail "$3"
}

contains "$BAR_QML" 'function isAwtarchyFlyout(toplevel)' \
    'Bar has no focused filter for Awtarchy flyout windows'
for title in \
    'Awtarchy Clipboard History' \
    'Awtarchy Notification Center' \
    'Awtarchy Quick Settings' \
    'Awtarchy Network' \
    'Awtarchy Bluetooth' \
    'Awtarchy Battery'
do
    contains "$BAR_QML" "\"${title}\"" \
        "Bar flyout filter is missing ${title}"
done
contains "$BAR_QML" 'if (isAwtarchyFlyout(toplevel))' \
    'Awtarchy flyouts are not rejected before task rendering'

# Running application and tray icons intentionally keep their native colors.
absent "$BAR_QML" 'import QtQuick.Effects' \
    'Bar unexpectedly imports Qt Quick effects for application icon tinting'
absent "$BAR_QML" 'MultiEffect {' \
    'Running application icons are still being theme-tinted'
contains "$BAR_QML" 'source: bar.appIcon(task.modelData)' \
    'Running application icons no longer use their native application icon'
contains "$BAR_QML" 'source: trayItem.modelData.icon' \
    'System tray icons no longer use their native applet icon'

contains "$BAR_QML" 'function barModuleVisible(name, module)' \
    'Bar has no per-display module visibility resolver'
[[ $(grep -Fc 'visible: bar.barModuleVisible(bar.monitorName, "cpu")' "$BAR_QML") -eq 2 ]] \
    || fail 'CPU visibility is not applied to horizontal and vertical bars'
[[ $(grep -Fc 'visible: bar.barModuleVisible(bar.monitorName, "temperature")' "$BAR_QML") -eq 2 ]] \
    || fail 'temperature visibility is not applied to horizontal and vertical bars'
[[ $(grep -Fc 'visible: bar.barModuleVisible(bar.monitorName, "memory")' "$BAR_QML") -eq 2 ]] \
    || fail 'RAM visibility is not applied to horizontal and vertical bars'

contains "$BAR_SETTINGS" 'function rawModuleVisible(name, module)' \
    'Bar settings cannot read per-display module visibility'
contains "$BAR_SETTINGS" 'function toggleModuleVisibility(module, label)' \
    'Bar settings cannot toggle individual status modules'
contains "$BAR_SETTINGS" 'moduleVisibilityText("cpu", "CPU")' \
    'Bar settings do not expose the CPU visibility toggle'
contains "$BAR_SETTINGS" 'moduleVisibilityText("temperature", "Temp")' \
    'Bar settings do not expose the temperature visibility toggle'
contains "$BAR_SETTINGS" 'moduleVisibilityText("memory", "RAM")' \
    'Bar settings do not expose the RAM visibility toggle'
contains "$BAR_SETTINGS" '["bash", barModuleScript, "reset", target]' \
    'Reset Bar Appearance does not restore stock module visibility'

[[ -f "$MODULE_SCRIPT" ]] || fail 'bar module visibility writer is missing'
bash -n "$MODULE_SCRIPT"
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$MODULE_SCRIPT"
fi

CACHE_HOME="${TMP}/cache"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
mkdir -p "$(dirname -- "$STATE_FILE")"
cat >"$STATE_FILE" <<'JSON'
{
  "enabled": true,
  "monitors": {
    "DP-1": {
      "position": "bottom",
      "bar_size": 32,
      "icon_scale": 110,
      "text_scale": 105
    },
    "DP-2": {
      "position": "top"
    }
  },
  "unrelated": {
    "preserve": "yes"
  }
}
JSON

run_modules() {
    env XDG_CACHE_HOME="$CACHE_HOME" HOME="$TMP/home" \
        bash "$MODULE_SCRIPT" "$@"
}

run_modules set DP-1 cpu false
run_modules set DP-1 temperature false
run_modules set DP-1 memory false
jq -e '
    .monitors["DP-1"].modules.cpu == false
    and .monitors["DP-1"].modules.temperature == false
    and .monitors["DP-1"].modules.memory == false
    and .monitors["DP-1"].position == "bottom"
    and .monitors["DP-1"].bar_size == 32
    and .monitors["DP-1"].icon_scale == 110
    and .monitors["DP-1"].text_scale == 105
    and .monitors["DP-2"].position == "top"
    and .unrelated.preserve == "yes"
' "$STATE_FILE" >/dev/null || fail 'module toggles changed unrelated shell state'

cp -- "$STATE_FILE" "$TMP/before-invalid.json"
if run_modules set DP-1 gpu false >/dev/null 2>&1; then
    fail 'unknown bar module was accepted'
fi
cmp -s "$STATE_FILE" "$TMP/before-invalid.json" \
    || fail 'invalid module changed shell state'
if run_modules set DP-1 cpu maybe >/dev/null 2>&1; then
    fail 'invalid module visibility value was accepted'
fi
cmp -s "$STATE_FILE" "$TMP/before-invalid.json" \
    || fail 'invalid visibility value changed shell state'

run_modules reset DP-1
jq -e '
    (.monitors["DP-1"].modules | not)
    and .monitors["DP-1"].position == "bottom"
    and .monitors["DP-1"].bar_size == 32
    and .unrelated.preserve == "yes"
' "$STATE_FILE" >/dev/null || fail 'module reset changed unrelated monitor state'

printf '%s\n' 'PASS: Awtarchy flyouts stay out of the task strip, native icon colors are preserved, and CPU/temp/RAM visibility is per-display and state-safe.'
