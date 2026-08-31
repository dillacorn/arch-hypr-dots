#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="${ROOT}/config/hypr/scripts/quickshell.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
BAR_QML="${ROOT}/config/quickshell/awtarchy/Bar.qml"
BAR_SETTINGS="${ROOT}/config/quickshell/awtarchy/BarSettingsSection.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

not_contains() {
    if grep -Fq -- "$2" "$1"; then
        fail "$3"
    fi
}

# Transparency is a per-display bar appearance setting. Existing installs and
# newly discovered monitors remain fully opaque until the user changes it.
contains "$MANAGER" 'bar_transparency:0' \
    'quickshell state normalization does not default bar transparency to 0%'
for command in gettransparency settransparency; do
    contains "$MANAGER" "$command" \
        "quickshell manager is missing ${command}"
done
contains "$BAR_STATE" 'function barTransparencyFor(name)' \
    'BarState has no per-display bar transparency resolver'
contains "$BAR_STATE" 'property var liveBarTransparencies: ({})' \
    'BarState has no in-process transparency preview state'
contains "$BAR_STATE" 'function setLiveBarTransparency(name, value)' \
    'BarState cannot preview transparency without persistent writes'
contains "$BAR_STATE" 'function clearLiveBarTransparency(name)' \
    'BarState cannot clear a completed transparency preview'
contains "$BAR_STATE" 'const override = liveBarTransparencies[name];' \
    'Bar transparency rendering does not prefer the live drag preview'
contains "$BAR_QML" 'surfaceFormat.opaque: false' \
    'Bar window does not request an alpha-capable surface format at creation time'
contains "$BAR_QML" 'BarState.barTransparencyFor(monitorName)' \
    'Bar background does not consume the per-display transparency setting'
contains "$BAR_QML" 'Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b' \
    'Bar transparency is not isolated to the background color'
contains "$BAR_SETTINGS" 'text: "Transparency"' \
    'Bar Appearance has no transparency adjustment row'
contains "$BAR_SETTINGS" '"settransparency"' \
    'Bar Appearance does not persist transparency changes'
contains "$BAR_SETTINGS" 'function previewTransparencyPercent(value)' \
    'Bar Appearance has no non-persistent transparency drag preview'
contains "$BAR_SETTINGS" 'BarState.setLiveBarTransparency(target, next)' \
    'Transparency drag preview is not applied directly to the live bar state'
contains "$BAR_SETTINGS" 'visible: root.barTransparencyHoverPercent >= 0' \
    'Transparency slider does not show a floating percentage on hover'
contains "$BAR_SETTINGS" 'parent.width * root.barTransparencyHoverPercent / 100 - width / 2' \
    'Transparency hover percentage is not positioned over the pointer location'
contains "$BAR_SETTINGS" 'if (pressed)' \
    'Transparency slider does not distinguish hover movement from held left-click dragging'
contains "$BAR_SETTINGS" 'onReleased: root.commitTransparencyDrag()' \
    'Transparency slider does not persist the final value when a drag is released'
contains "$BAR_SETTINGS" 'onCanceled: root.cancelTransparencyDrag()' \
    'Transparency slider does not clear a canceled live preview'
not_contains "$BAR_SETTINGS" 'text: root.barTransparencyHoverPercent >= 0' \
    'Transparency row still renders a permanent percentage at the right edge'

# Exercise the real manager state path with only qs/hyprctl stubbed. This proves
# transparency stays per-monitor, accepts the full 0-100 range, and preserves
# unrelated shell state.
FAKE_BIN="${TMP}/bin"
CACHE_HOME="${TMP}/cache"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
mkdir -p "$FAKE_BIN" "$(dirname -- "$STATE_FILE")" "$TMP/home"

cat >"${FAKE_BIN}/qs" <<'SH'
#!/usr/bin/env bash
:
SH
chmod +x "${FAKE_BIN}/qs"

cat >"${FAKE_BIN}/hyprctl" <<'SH'
#!/usr/bin/env bash
if [[ ${1:-} == monitors && ${2:-} == -j ]]; then
    printf '%s\n' '[{"name":"DP-1","focused":true},{"name":"DP-2","focused":false}]'
elif [[ ${1:-} == activeworkspace && ${2:-} == -j ]]; then
    printf '%s\n' '{"monitor":"DP-1"}'
fi
SH
chmod +x "${FAKE_BIN}/hyprctl"

cat >"$STATE_FILE" <<'JSON'
{
  "enabled": true,
  "monitors": {
    "DP-1": {"position":"bottom","bar_size":32},
    "DP-2": {"position":"top"}
  },
  "unrelated": {"preserve":"yes"}
}
JSON

run_manager() {
    env PATH="${FAKE_BIN}:$PATH" HOME="$TMP/home" XDG_CACHE_HOME="$CACHE_HOME" \
        XDG_DATA_HOME="$TMP/data" bash "$MANAGER" "$@"
}

[[ $(run_manager gettransparency DP-1) == 0 ]] \
    || fail 'existing monitor state did not normalize to 0% transparency'
[[ $(run_manager gettransparency DP-2) == 0 ]] \
    || fail 'second monitor did not normalize to 0% transparency'

run_manager settransparency DP-1 35
run_manager settransparency DP-2 100
[[ $(run_manager gettransparency DP-1) == 35 ]] \
    || fail '35% transparency did not persist on DP-1'
[[ $(run_manager gettransparency DP-2) == 100 ]] \
    || fail '100% transparency did not persist on DP-2'

run_manager settransparency-focused 20
[[ $(run_manager gettransparency-focused) == 20 ]] \
    || fail 'focused-monitor transparency command did not target DP-1'
[[ $(run_manager gettransparency DP-2) == 100 ]] \
    || fail 'focused-monitor transparency write changed DP-2'

if run_manager settransparency DP-1 101 >/dev/null 2>&1; then
    fail 'transparency accepted a value above 100%'
fi
if run_manager settransparency DP-1 -1 >/dev/null 2>&1; then
    fail 'transparency accepted a negative value'
fi
[[ $(run_manager gettransparency DP-1) == 20 ]] \
    || fail 'invalid transparency input changed DP-1 state'

jq -e '
    .monitors["DP-1"].position == "bottom"
    and .monitors["DP-1"].bar_size == 32
    and .monitors["DP-2"].position == "top"
    and .unrelated.preserve == "yes"
' "$STATE_FILE" >/dev/null || fail 'transparency writes changed unrelated state'

printf '%s\n' 'PASS: bar transparency supports per-display persistence, live drag preview, and pointer-position feedback.'
