#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_REF="${TARGET_REF:?TARGET_REF is required}"
ARTIFACT_DIR="${ARTIFACT_DIR:-/artifacts}"
SAFE_TARGET="${TARGET_REF//\//_}"
OUT="${ARTIFACT_DIR}/${SAFE_TARGET}"
mkdir -p "$OUT"

pacman -Syu --noconfirm --needed \
    hyprland quickshell jq python dbus mesa mesa-utils \
    cage xorg-server-xvfb xorg-xwayland wayland-utils \
    wl-clipboard cliphist grim foot \
    xdg-utils util-linux procps-ng libnotify qt6-wayland ttf-dejavu \
    >"$OUT/pacman.log" 2>&1

id tester >/dev/null 2>&1 || useradd -m -u 1000 tester
install -d -m 0700 -o tester -g tester /run/user/1000
install -d -o tester -g tester /home/tester/.config /home/tester/.cache
rm -rf /home/tester/.config/hypr /home/tester/.config/quickshell
cp -a /repo/config/hypr /home/tester/.config/hypr
cp -a /repo/config/quickshell /home/tester/.config/quickshell
chown -R tester:tester /home/tester/.config /home/tester/.cache
find /home/tester/.config/hypr/scripts -type f -name '*.sh' -exec chmod u+x {} +

cat > /tmp/cage-runtime-session.sh <<'SESSION'
#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_REF="${TARGET_REF:?}"
OUT="${OUT:?}"
export HOME=/home/tester
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_RUNTIME_DIR=/run/user/1000
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export HYPRLAND_NO_SD_VARS=1
export HYPRLAND_NO_RT=1
export LIBGL_ALWAYS_SOFTWARE=1
export WLR_RENDERER_ALLOW_SOFTWARE=1
export AQ_NO_KMS_REQUIREMENT=1
export AQ_NO_MODIFIERS=1
export AQ_TRACE=1
export QT_QPA_PLATFORM=wayland

XVFB_LOG="$OUT/xvfb.log"
CAGE_LOG="$OUT/cage.log"
HYPR_LOG="$OUT/hyprland.log"
QS_LOG="$OUT/quickshell-manager.log"
SOCKET_FILE="$XDG_RUNTIME_DIR/awtarchy-cage-socket-name"
: >"$XVFB_LOG"
: >"$CAGE_LOG"
: >"$HYPR_LOG"
: >"$QS_LOG"
rm -f -- "$SOCKET_FILE"

XVFB_PID=""
CAGE_PID=""
HYPR_PID=""
cleanup() {
    qs -c awtarchy ipc call control quit >/dev/null 2>&1 || true
    if [[ -n "$HYPR_PID" ]]; then
        kill "$HYPR_PID" >/dev/null 2>&1 || true
        wait "$HYPR_PID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$CAGE_PID" ]]; then
        kill "$CAGE_PID" >/dev/null 2>&1 || true
        wait "$CAGE_PID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$XVFB_PID" ]]; then
        kill "$XVFB_PID" >/dev/null 2>&1 || true
        wait "$XVFB_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

export DISPLAY=:99
unset WAYLAND_DISPLAY
Xvfb "$DISPLAY" -screen 0 1920x1080x24 -nolisten tcp >"$XVFB_LOG" 2>&1 &
XVFB_PID=$!
for _ in $(seq 1 120); do
    [[ -S /tmp/.X11-unix/X99 ]] && break
    if ! kill -0 "$XVFB_PID" 2>/dev/null; then
        printf '%s\n' 'Xvfb exited before creating its X11 socket.' >&2
        cat "$XVFB_LOG" >&2
        exit 1
    fi
    sleep 0.1
done
[[ -S /tmp/.X11-unix/X99 ]] || {
    printf '%s\n' 'Timed out waiting for Xvfb.' >&2
    cat "$XVFB_LOG" >&2
    exit 1
}

# WAYLAND_DISPLAY is deliberately unset for Cage so wlroots selects its X11
# backend from DISPLAY. Cage then publishes the server socket name to its child.
# Do not depend on Cage's newer -x option: the Arch package available to CI may
# lag the upstream CLI, so XWayland is installed and allowed to initialize.
env -u WAYLAND_DISPLAY \
    DISPLAY="$DISPLAY" \
    LIBGL_ALWAYS_SOFTWARE=1 \
    WLR_RENDERER_ALLOW_SOFTWARE=1 \
    cage -D -- sh -c \
        'printf "%s\n" "$WAYLAND_DISPLAY" >"$XDG_RUNTIME_DIR/awtarchy-cage-socket-name"; exec sleep 300' \
        >"$CAGE_LOG" 2>&1 &
CAGE_PID=$!

CAGE_SOCKET=""
for _ in $(seq 1 160); do
    if [[ -s "$SOCKET_FILE" ]]; then
        CAGE_SOCKET="$(cat "$SOCKET_FILE")"
        [[ -S "$XDG_RUNTIME_DIR/$CAGE_SOCKET" ]] && break
    fi
    if ! kill -0 "$CAGE_PID" 2>/dev/null; then
        printf '%s\n' 'Cage exited before publishing its Wayland socket.' >&2
        cat "$CAGE_LOG" >&2
        exit 1
    fi
    sleep 0.1
done
[[ -n "$CAGE_SOCKET" && -S "$XDG_RUNTIME_DIR/$CAGE_SOCKET" ]] || {
    printf '%s\n' 'Timed out waiting for Cage Wayland socket.' >&2
    cat "$CAGE_LOG" >&2
    exit 1
}

WAYLAND_DISPLAY="$CAGE_SOCKET" wayland-info >"$OUT/outer-wayland-info.txt" 2>&1 || {
    printf '%s\n' 'wayland-info could not inspect Cage.' >&2
    cat "$OUT/outer-wayland-info.txt" >&2
    exit 1
}

for required in wl_shm wl_seat xdg_wm_base zwp_linux_dmabuf_v1; do
    if ! grep -Fq -- "$required" "$OUT/outer-wayland-info.txt"; then
        printf 'Outer Cage compositor is missing required Wayland global: %s\n' "$required" >&2
        cat "$OUT/outer-wayland-info.txt" >&2
        exit 1
    fi
done

seat_version="$(sed -n "s/.*interface: 'wl_seat'.*version:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$OUT/outer-wayland-info.txt" | head -n1)"
xdg_version="$(sed -n "s/.*interface: 'xdg_wm_base'.*version:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$OUT/outer-wayland-info.txt" | head -n1)"
printf 'cage-socket=%s\nwl-seat-version=%s\nxdg-wm-base-version=%s\n' \
    "$CAGE_SOCKET" "$seat_version" "$xdg_version" >"$OUT/backend-mode.txt"

export WAYLAND_DISPLAY="$CAGE_SOCKET"
unset AQ_DRM_DEVICES
{
    printf '%s\n' '=== environment before Hyprland ==='
    printf 'DISPLAY=%s\n' "$DISPLAY"
    printf 'WAYLAND_DISPLAY=%s\n' "$WAYLAND_DISPLAY"
    printf 'LIBGL_ALWAYS_SOFTWARE=%s\n' "$LIBGL_ALWAYS_SOFTWARE"
    printf '%s\n' '=== eglinfo ==='
    eglinfo -B 2>&1 || true
} >"$OUT/render-environment.txt"

Hyprland --config "$HOME/.config/hypr/hyprland.lua" >"$HYPR_LOG" 2>&1 &
HYPR_PID=$!

LOCK=""
for _ in $(seq 1 180); do
    LOCK="$(find "$XDG_RUNTIME_DIR/hypr" -mindepth 2 -maxdepth 2 -name hyprland.lock -print -quit 2>/dev/null || true)"
    [[ -n "$LOCK" ]] && break
    if ! kill -0 "$HYPR_PID" 2>/dev/null; then
        printf '%s\n' 'Hyprland exited before creating a runtime lock.' >&2
        cat "$HYPR_LOG" >&2
        printf '%s\n' '=== Cage ===' >&2
        cat "$CAGE_LOG" >&2
        exit 1
    fi
    sleep 0.1
done
[[ -n "$LOCK" ]] || {
    printf '%s\n' 'Timed out waiting for Hyprland runtime lock.' >&2
    cat "$HYPR_LOG" >&2
    exit 1
}

export HYPRLAND_INSTANCE_SIGNATURE="$(basename "$(dirname "$LOCK")")"
export WAYLAND_DISPLAY="$(sed -n '2p' "$LOCK")"
printf '%s\n' "$HYPRLAND_INSTANCE_SIGNATURE" >"$OUT/hyprland-instance.txt"
printf '%s\n' "$WAYLAND_DISPLAY" >"$OUT/hyprland-wayland-display.txt"

for _ in $(seq 1 120); do
    if hyprctl -j monitors >"$OUT/monitors.json" 2>/dev/null && \
        jq -e 'length > 0' "$OUT/monitors.json" >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done
jq -e 'length > 0' "$OUT/monitors.json" >/dev/null || {
    printf '%s\n' 'Hyprland started but never exposed a monitor.' >&2
    cat "$HYPR_LOG" >&2
    exit 1
}

hyprctl configerrors >"$OUT/configerrors-initial.txt"
[[ ! -s "$OUT/configerrors-initial.txt" ]] || {
    printf '%s\n' 'Hyprland reported configuration errors:' >&2
    cat "$OUT/configerrors-initial.txt" >&2
    exit 1
}

"$HOME/.config/hypr/scripts/quickshell.sh" start >"$QS_LOG" 2>&1 || {
    cat "$QS_LOG" >&2
    [[ -f "$HOME/.cache/awtarchy/quickshell.log" ]] && cat "$HOME/.cache/awtarchy/quickshell.log" >&2
    exit 1
}

QS_READY=0
for _ in $(seq 1 180); do
    if qs -c awtarchy ipc call control ping >/dev/null 2>&1; then
        QS_READY=1
        break
    fi
    sleep 0.1
done
(( QS_READY == 1 )) || {
    printf '%s\n' 'Quickshell did not become IPC-ready.' >&2
    [[ -f "$HOME/.cache/awtarchy/quickshell.log" ]] && cat "$HOME/.cache/awtarchy/quickshell.log" >&2
    exit 1
}

qs -c awtarchy list --json >"$OUT/quickshell-instances.json"
hyprctl -j layers >"$OUT/layers-before.json"
"$HOME/.config/hypr/scripts/quickshell_quick_settings_toggle.sh"
sleep 1
qs -c awtarchy ipc call control ping >/dev/null
hyprctl -j layers >"$OUT/layers-quicksettings.json"

jq -e '[.. | objects | select((.namespace? // "") | contains("awtarchy"))] | length > 0' \
    "$OUT/layers-quicksettings.json" >/dev/null 2>&1 || true

grim "$OUT/quicksettings.png" >/dev/null 2>&1 || true
"$HOME/.config/hypr/scripts/quickshell_quick_settings_toggle.sh"

if [[ -f "$HOME/.cache/awtarchy/quickshell.log" ]]; then
    cp "$HOME/.cache/awtarchy/quickshell.log" "$OUT/quickshell.log"
    if grep -Eiq 'QQmlApplicationEngine failed|QQmlComponent: Component is not ready|Type .* unavailable|module .* is not installed|SyntaxError:|ReferenceError:' "$OUT/quickshell.log"; then
        printf '%s\n' 'Quickshell log contains a QML/runtime loader error.' >&2
        grep -Ein 'QQmlApplicationEngine failed|QQmlComponent: Component is not ready|Type .* unavailable|module .* is not installed|SyntaxError:|ReferenceError:' "$OUT/quickshell.log" >&2 || true
        exit 1
    fi
fi

hyprctl configerrors >"$OUT/configerrors-final.txt"
[[ ! -s "$OUT/configerrors-final.txt" ]]
qs -c awtarchy ipc call control ping >/dev/null
printf 'PASS: Xvfb -> Cage -> Hyprland -> Quickshell runtime proof for %s\n' "$TARGET_REF"
SESSION
chmod 0755 /tmp/cage-runtime-session.sh
chown tester:tester /tmp/cage-runtime-session.sh "$OUT"

runuser -u tester -- env \
    TARGET_REF="$TARGET_REF" \
    OUT="$OUT" \
    dbus-run-session -- /tmp/cage-runtime-session.sh
