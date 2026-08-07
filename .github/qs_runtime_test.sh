#!/usr/bin/env bash
set -Eeuo pipefail

pacman -Syu --noconfirm --needed \
  bash coreutils findutils grep sed gawk jq python shellcheck dbus git \
  quickshell qt6-declarative hyprland grim ttf-noto-nerd upower

export HOME=/root
export XDG_RUNTIME_DIR=/tmp/awtarchy-qs-runtime
rm -rf "$XDG_RUNTIME_DIR"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

printf '%s\n' '=== package versions ==='
pacman -Q quickshell hyprland qt6-declarative upower jq shellcheck
qs --version

printf '%s\n' '=== source validation ==='
bash -n awtarchy-install.sh
bash -n local/share/awtarchy/awtarchy-runtime.sh
while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(find config/hypr/scripts -maxdepth 1 -type f -name '*.sh' -print0)
for theme in config/hypr/themes/*; do
  bash -n "$theme"
done
shellcheck -S error -x -e SC1091 config/hypr/scripts/*.sh
git diff --check

printf '%s\n' '=== production config staging ==='
mkdir -p "$HOME/.config/quickshell" "$HOME/.config/hypr"
rm -rf "$HOME/.config/quickshell/awtarchy" "$HOME/.config/hypr/scripts"
cp -a config/quickshell/awtarchy "$HOME/.config/quickshell/awtarchy"
cp -a config/hypr/scripts "$HOME/.config/hypr/scripts"
chmod +x "$HOME/.config/hypr/scripts"/*.sh
mkdir -p "$HOME/.cache/awtarchy"
printf '{"enabled":true,"monitors":{}}\n' > "$HOME/.cache/awtarchy/quickshell-state.json"
printf '0\n' > "$HOME/.cache/awtarchy/quickshell-dnd"

mapfile -t DBUS_INFO < <(dbus-daemon --session --fork --print-address=1 --print-pid=1)
export DBUS_SESSION_BUS_ADDRESS="${DBUS_INFO[0]}"
DBUS_PID="${DBUS_INFO[1]}"

cat > /tmp/awtarchy-ci-hyprland.lua <<'LUA'
hl.config({
    ecosystem = {
        no_update_news = true,
        enforce_permissions = false,
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },
})
LUA

cleanup() {
  kill "${QS_PID:-}" "${HYPR_PID:-}" "$DBUS_PID" 2>/dev/null || true
}
trap cleanup EXIT

printf '%s\n' '=== starting headless Hyprland ==='
HYPRLAND_NO_RT=1 \
HYPRLAND_NO_SD_NOTIFY=1 \
HYPRLAND_NO_SD_VARS=1 \
AQ_NO_KMS_REQUIREMENT=1 \
XDG_CURRENT_DESKTOP=Hyprland \
XDG_SESSION_TYPE=wayland \
Hyprland --config /tmp/awtarchy-ci-hyprland.lua >/tmp/hyprland.log 2>&1 &
HYPR_PID=$!

HIS=''
for _ in $(seq 1 200); do
  HIS_DIR="$(find "$XDG_RUNTIME_DIR/hypr" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1 || true)"
  if [[ -n "$HIS_DIR" && -S "$HIS_DIR/.socket.sock" ]]; then
    HIS="$(basename "$HIS_DIR")"
    break
  fi
  kill -0 "$HYPR_PID" 2>/dev/null || break
  sleep 0.05
done

if [[ -z "$HIS" ]]; then
  printf '%s\n' 'Hyprland failed before IPC:' >&2
  cat /tmp/hyprland.log >&2
  exit 1
fi

export HYPRLAND_INSTANCE_SIGNATURE="$HIS"
WAYLAND_SOCKET="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' | head -n1 || true)"
if [[ -z "$WAYLAND_SOCKET" ]]; then
  printf '%s\n' 'Hyprland has no Wayland socket:' >&2
  cat /tmp/hyprland.log >&2
  exit 1
fi
export WAYLAND_DISPLAY="$(basename "$WAYLAND_SOCKET")"
export QT_QPA_PLATFORM=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland

hyprctl monitors -j | tee /tmp/monitors.json
jq -e 'length >= 1' /tmp/monitors.json >/dev/null
hyprctl configerrors | tee /tmp/configerrors.txt

printf '%s\n' '=== starting production Quickshell config ==='
qs -vv --no-color -c awtarchy >/tmp/quickshell.log 2>&1 &
QS_PID=$!

PING=''
for _ in $(seq 1 200); do
  PING="$(qs -c awtarchy ipc call control ping 2>/dev/null || true)"
  [[ "$PING" == 'ok' ]] && break
  kill -0 "$QS_PID" 2>/dev/null || break
  sleep 0.05
done

printf 'control ping: %s\n' "${PING:-<none>}"
if [[ "$PING" != 'ok' ]]; then
  cat /tmp/quickshell.log >&2 || true
  exit 1
fi

printf '%s\n' '=== exercising Quickshell IPC ==='
qs -c awtarchy ipc call launcher open
qs -c awtarchy ipc call launcher close
qs -c awtarchy ipc call powermenu open
qs -c awtarchy ipc call powermenu close
qs -c awtarchy ipc call clipboard open
qs -c awtarchy ipc call clipboard close
qs -c awtarchy ipc call themes open
qs -c awtarchy ipc call themes close
qs -c awtarchy ipc call notifications dndEnabled

hyprctl layers -j | tee /tmp/layers.json
OUTPUT="$(jq -r '.[0].name // empty' /tmp/monitors.json)"
if [[ -n "$OUTPUT" ]]; then
  grim -o "$OUTPUT" /tmp/quickshell.png
  test -s /tmp/quickshell.png
  file /tmp/quickshell.png
fi

qs -c awtarchy ipc call control quit >/dev/null 2>&1 || true
wait "$QS_PID" || true
QS_PID=''

printf '%s\n' 'Quickshell runtime smoke test passed.'
