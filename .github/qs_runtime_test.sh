#!/usr/bin/env bash
set -Eeuo pipefail

pacman -Syu --noconfirm --needed \
  bash coreutils findutils grep sed gawk jq python shellcheck dbus libcap \
  quickshell qt6-declarative hyprland grim sway ttf-noto-nerd upower

export HOME=/root
export XDG_RUNTIME_DIR=/tmp/awtarchy-qs-runtime
rm -rf "$XDG_RUNTIME_DIR"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

printf '%s\n' '=== package versions ==='
pacman -Q quickshell hyprland qt6-declarative sway upower jq shellcheck
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
  kill "${QS_PID:-}" "${HYPR_PID:-}" "${SWAY_PID:-}" "$DBUS_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Arch Sway carries session/tty file capabilities that Docker refuses to execute
# under its default capability bounding set. They are not needed for headless.
setcap -r "$(command -v sway)" 2>/dev/null || true

printf '%s\n' '=== starting outer headless Sway ==='
printf '%s\n' \
  'output * mode 1920x1080' \
  'seat * hide_cursor 1000' > /tmp/awtarchy-ci-sway.conf
WLR_BACKENDS=headless \
WLR_RENDERER=pixman \
WLR_LIBINPUT_NO_DEVICES=1 \
sway -c /tmp/awtarchy-ci-sway.conf -d >/tmp/sway.log 2>&1 &
SWAY_PID=$!

OUTER_WAYLAND=''
for _ in $(seq 1 200); do
  OUTER_WAYLAND="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' | head -n1 || true)"
  [[ -n "$OUTER_WAYLAND" ]] && break
  kill -0 "$SWAY_PID" 2>/dev/null || break
  sleep 0.05
done
if [[ -z "$OUTER_WAYLAND" ]]; then
  printf '%s\n' 'Outer Sway failed:' >&2
  cat /tmp/sway.log >&2
  exit 1
fi
OUTER_DISPLAY="$(basename "$OUTER_WAYLAND")"
printf 'outer WAYLAND_DISPLAY=%s\n' "$OUTER_DISPLAY"

printf '%s\n' '=== starting nested Hyprland ==='
HYPRLAND_NO_RT=1 \
HYPRLAND_NO_SD_NOTIFY=1 \
HYPRLAND_NO_SD_VARS=1 \
WAYLAND_DISPLAY="$OUTER_DISPLAY" \
XDG_CURRENT_DESKTOP=Hyprland \
XDG_SESSION_TYPE=wayland \
Hyprland --i-am-really-stupid --config /tmp/awtarchy-ci-hyprland.lua >/tmp/hyprland.log 2>&1 &
HYPR_PID=$!

HIS=''
for _ in $(seq 1 240); do
  HIS_DIR="$(find "$XDG_RUNTIME_DIR/hypr" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1 || true)"
  if [[ -n "$HIS_DIR" && -S "$HIS_DIR/.socket.sock" ]]; then
    HIS="$(basename "$HIS_DIR")"
    break
  fi
  kill -0 "$HYPR_PID" 2>/dev/null || break
  sleep 0.05
done

if [[ -z "$HIS" ]]; then
  printf '%s\n' 'Nested Hyprland failed before IPC:' >&2
  cat /tmp/hyprland.log >&2
  exit 1
fi

export HYPRLAND_INSTANCE_SIGNATURE="$HIS"
# Pick the newest Wayland socket, which belongs to nested Hyprland rather than
# the already-running outer Sway compositor.
NESTED_WAYLAND="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2- || true)"
if [[ -z "$NESTED_WAYLAND" ]]; then
  printf '%s\n' 'Nested Hyprland has no Wayland socket:' >&2
  cat /tmp/hyprland.log >&2
  exit 1
fi
export WAYLAND_DISPLAY="$(basename "$NESTED_WAYLAND")"
export QT_QPA_PLATFORM=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland

printf 'nested HIS=%s WAYLAND_DISPLAY=%s\n' "$HYPRLAND_INSTANCE_SIGNATURE" "$WAYLAND_DISPLAY"
hyprctl monitors -j | tee /tmp/monitors.json
jq -e 'length >= 1' /tmp/monitors.json >/dev/null
hyprctl configerrors | tee /tmp/configerrors.txt

printf '%s\n' '=== starting production Quickshell config ==='
qs -vv --no-color -c awtarchy >/tmp/quickshell.log 2>&1 &
QS_PID=$!

PING=''
for _ in $(seq 1 240); do
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
