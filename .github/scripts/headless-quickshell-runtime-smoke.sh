#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_REF="${TARGET_REF:?TARGET_REF is required}"
ARTIFACT_DIR="${ARTIFACT_DIR:-/artifacts}"
SAFE_TARGET="${TARGET_REF//\//_}"
OUT="${ARTIFACT_DIR}/${SAFE_TARGET}"
mkdir -p "$OUT"

pacman -Syu --noconfirm --needed \
    hyprland quickshell jq python dbus mesa wl-clipboard cliphist grim foot \
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

cat > /tmp/runtime-session.sh <<'SESSION'
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
export AQ_NO_KMS_REQUIREMENT=1
export AQ_NO_MODIFIERS=1
export LIBGL_ALWAYS_SOFTWARE=1
export WLR_RENDERER_ALLOW_SOFTWARE=1
export QT_QPA_PLATFORM=wayland

HYPR_LOG="$OUT/hyprland.log"
QS_LOG="$OUT/quickshell-manager.log"
: >"$HYPR_LOG"
: >"$QS_LOG"

Hyprland --config "$HOME/.config/hypr/hyprland.lua" >"$HYPR_LOG" 2>&1 &
HYPR_PID=$!
cleanup() {
    qs -c awtarchy ipc call control quit >/dev/null 2>&1 || true
    kill "$HYPR_PID" >/dev/null 2>&1 || true
    wait "$HYPR_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

LOCK=""
for _ in $(seq 1 120); do
    LOCK="$(find "$XDG_RUNTIME_DIR/hypr" -mindepth 2 -maxdepth 2 -name hyprland.lock -print -quit 2>/dev/null || true)"
    [[ -n "$LOCK" ]] && break
    if ! kill -0 "$HYPR_PID" 2>/dev/null; then
        printf '%s\n' 'Hyprland exited before creating a runtime lock.' >&2
        cat "$HYPR_LOG" >&2
        exit 1
    fi
    sleep 0.1
done
[[ -n "$LOCK" ]] || { printf '%s\n' 'Timed out waiting for Hyprland runtime lock.' >&2; cat "$HYPR_LOG" >&2; exit 1; }

export HYPRLAND_INSTANCE_SIGNATURE="$(basename "$(dirname "$LOCK")")"
export WAYLAND_DISPLAY="$(sed -n '2p' "$LOCK")"
printf '%s\n' "$HYPRLAND_INSTANCE_SIGNATURE" >"$OUT/hyprland-instance.txt"
printf '%s\n' "$WAYLAND_DISPLAY" >"$OUT/wayland-display.txt"

hyprctl -j monitors >"$OUT/monitors-initial.json"
hyprctl configerrors >"$OUT/configerrors-initial.txt"
if [[ -s "$OUT/configerrors-initial.txt" ]]; then
    printf '%s\n' 'Hyprland reported config errors at startup:' >&2
    cat "$OUT/configerrors-initial.txt" >&2
    exit 1
fi

"$HOME/.config/hypr/scripts/quickshell.sh" start >"$QS_LOG" 2>&1 || {
    cat "$QS_LOG" >&2
    [[ -f "$HOME/.cache/awtarchy/quickshell.log" ]] && cat "$HOME/.cache/awtarchy/quickshell.log" >&2
    exit 1
}

QS_READY=0
for _ in $(seq 1 120); do
    if qs -c awtarchy ipc call control ping >/dev/null 2>&1; then
        QS_READY=1
        break
    fi
    sleep 0.1
done
if (( QS_READY == 0 )); then
    printf '%s\n' 'Quickshell did not become IPC-ready.' >&2
    [[ -f "$HOME/.cache/awtarchy/quickshell.log" ]] && cat "$HOME/.cache/awtarchy/quickshell.log" >&2
    exit 1
fi

qs -c awtarchy list --json >"$OUT/quickshell-instances.json"
hyprctl -j layers >"$OUT/layers-before.json"

# Open the real Quick Settings surface and verify the shell survives it.
"$HOME/.config/hypr/scripts/quickshell_quick_settings_toggle.sh"
sleep 0.8
qs -c awtarchy ipc call control ping >/dev/null
hyprctl -j layers >"$OUT/layers-quicksettings.json"
grim "$OUT/quicksettings.png"
"$HOME/.config/hypr/scripts/quickshell_quick_settings_toggle.sh"
sleep 0.2

case "$TARGET_REF" in
    feature/progressive-clipboard-loading)
        # Ensure the real clipboard watcher exists even if unrelated CI-only
        # session services prevented the normal Hyprland autostart from doing it.
        if ! pgrep -f 'wl-paste --type text --watch cliphist store' >/dev/null; then
            wl-paste --type text --watch cliphist store >/dev/null 2>&1 &
            sleep 0.2
        fi

        # Drive real Wayland clipboard traffic through cliphist.
        for n in $(seq 1 80); do
            printf 'Awtarchy runtime clipboard item %03d' "$n" | wl-copy
            sleep 0.015
        done
        sleep 0.8
        cliphist list >"$OUT/cliphist-list.txt"
        [[ "$(wc -l <"$OUT/cliphist-list.txt")" -ge 60 ]] || {
            printf '%s\n' 'Expected at least 60 clipboard records.' >&2
            exit 1
        }
        "$HOME/.config/hypr/scripts/quickshell_clipboard_toggle.sh"
        sleep 1
        qs -c awtarchy ipc call control ping >/dev/null
        grim "$OUT/clipboard.png"
        # Rapid close/reopen probes generation/process cleanup under a live compositor.
        for _ in $(seq 1 4); do
            "$HOME/.config/hypr/scripts/quickshell_clipboard_toggle.sh"
            sleep 0.08
            "$HOME/.config/hypr/scripts/quickshell_clipboard_toggle.sh"
            sleep 0.08
        done
        qs -c awtarchy ipc call control ping >/dev/null
        ;;

    feature/focused-display-scale)
        MONITOR="$(hyprctl -j monitors | jq -r '.[0].name')"
        "$HOME/.config/hypr/scripts/quickshell_display_scale.sh" status "$MONITOR" >"$OUT/display-scale-before.json"
        "$HOME/.config/hypr/scripts/quickshell_display_scale.sh" set "$MONITOR" 1.25 >"$OUT/display-scale-set-125.json"
        ACTUAL_SCALE="$(hyprctl -j monitors | jq -r --arg m "$MONITOR" '.[] | select(.name == $m) | .scale')"
        awk -v s="$ACTUAL_SCALE" 'BEGIN { exit !(s > 1.24 && s < 1.26) }' || {
            printf 'Expected live scale 1.25, got %s\n' "$ACTUAL_SCALE" >&2
            exit 1
        }
        "$HOME/.config/hypr/scripts/quickshell_display_scale.sh" set "$MONITOR" 1 >"$OUT/display-scale-set-100.json"
        hyprctl configerrors >"$OUT/configerrors-after-scale.txt"
        [[ ! -s "$OUT/configerrors-after-scale.txt" ]]
        ;;

    feature/quick-settings-layout-customization)
        MONITOR="$(hyprctl -j monitors | jq -r '.[0].name')"
        ORDER='["title-bars","brightness","output-volume","power-mode","bar","display-effects","submap","wallpaper","awtarchy","smtty","scheduler","numlock"]'
        HIDDEN='["smtty"]'
        "$HOME/.config/hypr/scripts/quickshell_application_state.sh" \
            save-quick-settings-layout "$MONITOR" "$ORDER" "$HIDDEN"
        jq -e --arg m "$MONITOR" \
            '.quick_settings_layouts[$m].order[0] == "title-bars" and (.quick_settings_layouts[$m].hidden | index("smtty") != null)' \
            "$HOME/.cache/awtarchy/quickshell-state.json" >/dev/null
        qs -c awtarchy ipc call control ping >/dev/null
        "$HOME/.config/hypr/scripts/quickshell_quick_settings_toggle.sh"
        sleep 0.8
        qs -c awtarchy ipc call control ping >/dev/null
        grim "$OUT/quicksettings-custom-layout.png"
        "$HOME/.config/hypr/scripts/quickshell_quick_settings_toggle.sh"
        ;;

    feature/floating-windows-default)
        helper="$HOME/.config/hypr/scripts/quickshell_floating_windows.sh"
        [[ "$($helper status)" == disabled ]]

        foot --app-id awtarchy-tiled-check --title awtarchy-tiled-check >/dev/null 2>&1 &
        sleep 0.6
        BASE_FLOAT="$(hyprctl -j clients | jq -r '.[] | select(.class == "awtarchy-tiled-check") | .floating' | head -n1)"
        [[ "$BASE_FLOAT" == false ]] || { printf 'Stock window unexpectedly floating: %s\n' "$BASE_FLOAT" >&2; exit 1; }
        pkill -f 'foot.*awtarchy-tiled-check' || true
        sleep 0.2

        [[ "$($helper set on)" == enabled ]]
        foot --app-id awtarchy-floating-check --title awtarchy-floating-check >/dev/null 2>&1 &
        sleep 0.6
        FLOATING="$(hyprctl -j clients | jq -r '.[] | select(.class == "awtarchy-floating-check") | .floating' | head -n1)"
        [[ "$FLOATING" == true ]] || { printf 'Enabled window did not float: %s\n' "$FLOATING" >&2; exit 1; }

        ADDRESS="$(hyprctl -j clients | jq -r '.[] | select(.class == "awtarchy-floating-check") | .address' | head -n1)"
        hyprctl dispatch togglefloating "address:${ADDRESS}" >/dev/null
        sleep 0.2
        MANUAL_TILE="$(hyprctl -j clients | jq -r '.[] | select(.class == "awtarchy-floating-check") | .floating' | head -n1)"
        [[ "$MANUAL_TILE" == false ]] || { printf 'Manual tiling did not override floating default: %s\n' "$MANUAL_TILE" >&2; exit 1; }

        foot --app-id testgame.exe --title testgame.exe >/dev/null 2>&1 &
        sleep 0.6
        GAME_FLOAT="$(hyprctl -j clients | jq -r '.[] | select(.class == "testgame.exe") | .floating' | head -n1)"
        [[ "$GAME_FLOAT" == false ]] || { printf 'Game exception unexpectedly floating: %s\n' "$GAME_FLOAT" >&2; exit 1; }

        hyprctl -j clients >"$OUT/floating-clients.json"
        [[ "$($helper set off)" == disabled ]]
        hyprctl configerrors >"$OUT/configerrors-after-floating.txt"
        [[ ! -s "$OUT/configerrors-after-floating.txt" ]]
        ;;
esac

# Fail on runtime-level QML/config loader errors, while retaining complete logs.
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
printf 'PASS: live headless Hyprland/Quickshell smoke test for %s\n' "$TARGET_REF"
SESSION
chmod 0755 /tmp/runtime-session.sh
chown tester:tester /tmp/runtime-session.sh "$OUT"

runuser -u tester -- env TARGET_REF="$TARGET_REF" OUT="$OUT" \
    dbus-run-session -- /tmp/runtime-session.sh
