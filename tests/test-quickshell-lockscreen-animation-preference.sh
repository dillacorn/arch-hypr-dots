#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
SHELL_QML="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
SURFACE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

reject_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

# The existing Quickshell state owner persists one global lockscreen formation
# preference. Missing state uses stock Split; only these six values are
# accepted so malformed state cannot turn into arbitrary QML behavior.
require_text "$APP_STATE" 'set-lockscreen-animation)' \
    'application state helper does not expose set-lockscreen-animation'
require_text "$APP_STATE" 'LOCKSCREEN_ANIMATIONS_JSON=' \
    'application state helper does not own the lockscreen animation allow-list'

mkdir -p "$TMP/cache/awtarchy" "$TMP/home" "$TMP/config"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true}' \
    >"$TMP/cache/awtarchy/quickshell-state.json"

for preference in random swarm edges center split off; do
    XDG_CACHE_HOME="$TMP/cache" \
    XDG_CONFIG_HOME="$TMP/config" \
    HOME="$TMP/home" \
        bash "$APP_STATE" set-lockscreen-animation "$preference"
    jq -e --arg expected "$preference" \
        '.lockscreen_animation == $expected' \
        "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
        || fail "application state did not persist lockscreen animation ${preference}"
done

if XDG_CACHE_HOME="$TMP/cache" \
    XDG_CONFIG_HOME="$TMP/config" \
    HOME="$TMP/home" \
        bash "$APP_STATE" set-lockscreen-animation invalid >/dev/null 2>&1; then
    fail 'application state accepted an invalid lockscreen animation preference'
fi

# Quick Settings exposes the preference inside the existing Awtarchy card,
# beside Awtarchy Tips, rather than adding another reorderable top-level card.
require_text "$BAR_STATE" 'readonly property var lockscreenAnimationPresets:' \
    'BarState does not expose the lockscreen animation choices'
require_text "$BAR_STATE" 'function lockscreenAnimationPreference()' \
    'BarState does not normalize the saved lockscreen animation preference'
for preference in random swarm edges center split off; do
    require_text "$BAR_STATE" "key: \"${preference}\"" \
        "BarState is missing the ${preference} lockscreen animation choice"
done
require_text "$BAR_STATE" 'lockscreen_animation: "split"' \
    'BarState stock lockscreen animation is not Split'
require_text "$BAR_STATE" 'const value = String(data().lockscreen_animation || "split");' \
    'BarState missing lockscreen animation does not normalize to Split'
require_text "$BAR_STATE" 'return "split";' \
    'BarState invalid lockscreen animation does not normalize to Split'
require_text "$QUICK_SETTINGS" 'text: "Lockscreen Animation"' \
    'Awtarchy Quick Settings card has no Lockscreen Animation control'
require_text "$QUICK_SETTINGS" 'model: BarState.lockscreenAnimationPresets' \
    'Lockscreen Animation control does not use the canonical preference list'
require_text "$QUICK_SETTINGS" '"set-lockscreen-animation", String(modelData.key)' \
    'Lockscreen Animation control does not persist the selected choice'

# The dedicated lock process reads the shared state itself at startup. It must
# fall back to stock Split when the file/value is unavailable, malformed, or
# unknown, and choose one random family once per lock only when Random is used.
require_text "$SHELL_QML" 'blockLoading: true' \
    'lock shell does not synchronously read animation preference before surfaces start'
require_text "$SHELL_QML" 'property string lockAnimationPreference: "split"' \
    'lock shell default animation preference is not Split'
require_text "$SHELL_QML" 'return allowedAnimationPreferences.indexOf(key) >= 0 ? key : "split";' \
    'lock shell does not normalize unknown animation preferences back to Split'
require_text "$SHELL_QML" 'lockAnimationPreference = "split";' \
    'lock shell does not fall back to Split when state is missing or malformed'
require_text "$SHELL_QML" 'catch (error) {' \
    'lock shell does not guard malformed animation preference state'
require_text "$SHELL_QML" 'property int randomFormationMode: Math.floor(Math.random() * 4)' \
    'lock shell does not choose one random family per lock'
require_text "$SHELL_QML" 'animationPreference: root.lockAnimationPreference' \
    'lock surfaces do not receive the saved animation preference'
require_text "$SHELL_QML" 'randomFormationMode: root.randomFormationMode' \
    'lock surfaces do not share the per-lock random family'

require_text "$SURFACE_QML" 'required property string animationPreference' \
    'lock surface does not receive the animation preference'
require_text "$SURFACE_QML" 'required property int randomFormationMode' \
    'lock surface does not receive the shared random family'
require_text "$SURFACE_QML" 'animationPreference === "swarm"' \
    'lock surface does not map the Swarm preference'
require_text "$SURFACE_QML" 'animationPreference === "edges"' \
    'lock surface does not map the Edges preference'
require_text "$SURFACE_QML" 'animationPreference === "center"' \
    'lock surface does not map the Center preference'
require_text "$SURFACE_QML" 'animationPreference === "split"' \
    'lock surface does not map the Split preference'
require_text "$SURFACE_QML" 'root.animationPreference === "off" ? 1 : 0' \
    'Off does not immediately render the completed wordmark'
require_text "$SURFACE_QML" 'root.animationPreference !== "off"' \
    'Off does not suppress particle formation animation'

# Formation Off is deliberately not an effects master switch. Audio and mouse
# interactions have their own persisted controls and must continue to function
# independently when the entrance animation is disabled.
require_text "$SURFACE_QML" 'readonly property bool pointerEffectsEnabled: root.mouseInteractive && root.pointerActive' \
    'pointer effects are not controlled independently from formation animation'
require_text "$SURFACE_QML" 'readonly property bool audioEffectsEnabled: root.audioReactive && root.audioLevel > root.audioSilenceThreshold' \
    'audio effects are not controlled independently from formation animation'
require_text "$SHELL_QML" 'enabled: root.lockAudioReactive' \
    'audio analyzer is not controlled solely by the Audio Reactive preference'
reject_text "$SURFACE_QML" 'readonly property bool interactiveEffectsEnabled: root.animationPreference !== "off"' \
    'formation Off still suppresses independent pointer/audio effects'
reject_text "$SHELL_QML" 'enabled: root.lockAudioReactive && root.lockAnimationPreference !== "off"' \
    'formation Off still suppresses the independent audio analyzer'

require_text "$SURFACE_QML" 'readonly property int formationDelay: Math.floor(Math.random() * 301)' \
    'lockscreen formation delay is not capped at the faster 300ms range'
require_text "$SURFACE_QML" 'readonly property int formationDuration: 1700' \
    'lockscreen formation base duration is not the faster 1700ms value'
require_text "$SURFACE_QML" '+ Math.floor(Math.random() * 351)' \
    'lockscreen formation duration variance is not capped at 350ms'

printf 'PASS: lockscreen animation preference contracts\n'
