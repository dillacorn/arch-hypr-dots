#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# Route-aware default output volume control for the Awtarchy bar.

set -euo pipefail
IFS=$'\n\t'

ACTION="${1:-}"
VALUE="${2:-}"

case "$ACTION" in
  up|down|set) ;;
  *)
    printf 'Usage: %s {up|down|set} PERCENT\n' "${0##*/}" >&2
    exit 2
    ;;
esac

[[ $VALUE =~ ^[0-9]+([.][0-9]+)?$ ]] || {
  printf 'ERROR: invalid volume percentage: %s\n' "$VALUE" >&2
  exit 2
}

for command in wpctl pw-dump pw-cli python3 flock; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'ERROR: required command not found: %s\n' "$command" >&2
    exit 127
  }
done

runtime_root="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/awtarchy-runtime}"
lock_dir="${runtime_root}/awtarchy"
umask 077
mkdir -p -- "$lock_dir"
# Wheel events launch separate helpers, so protect the full read/modify/write.
exec {volume_lock_fd}>"${lock_dir}/quickshell-volume.lock"
flock -x "$volume_lock_fd"

fallback_volume() {
  local limit_ratio
  limit_ratio="$(python3 -c 'import sys; print(max(0.0, min(2.0, float(sys.argv[1]) / 100.0)))' "$VALUE")"
  case "$ACTION" in
    up)
      wpctl set-volume --limit "$limit_ratio" @DEFAULT_AUDIO_SINK@ 5%+
      ;;
    down)
      wpctl set-volume --limit "$limit_ratio" @DEFAULT_AUDIO_SINK@ 5%-
      ;;
    set)
      wpctl set-volume @DEFAULT_AUDIO_SINK@ "${VALUE}%"
      ;;
  esac
}

inspect="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)"
device_id="$(sed -nE 's/^[[:space:]]*\*?[[:space:]]*device\.id[[:space:]]*=[[:space:]]*"?([0-9]+)"?.*/\1/p' <<<"$inspect" | head -n1)"
route_device="$(sed -nE 's/^[[:space:]]*\*?[[:space:]]*card\.profile\.device[[:space:]]*=[[:space:]]*"?([0-9]+)"?.*/\1/p' <<<"$inspect" | head -n1)"

if [[ ! $device_id =~ ^[0-9]+$ || ! $route_device =~ ^[0-9]+$ ]]; then
  fallback_volume
  exit 0
fi

route_dump="$(pw-dump "$device_id" 2>/dev/null || true)"
[[ -n $route_dump ]] || {
  fallback_volume
  exit 0
}

if ! route_result="$(printf '%s\n' "$route_dump" | python3 -c '
import json
import math
import sys

route_device = int(sys.argv[1])
action = sys.argv[2]
value = float(sys.argv[3])

data = json.load(sys.stdin)
obj = data[0] if isinstance(data, list) and data else {}
routes = (((obj.get("info") or {}).get("params") or {}).get("Route") or [])
route = next((r for r in routes if int(r.get("device", -1)) == route_device), None)
if route is None:
    raise SystemExit(2)

props = route.get("props") or {}
volumes = props.get("channelVolumes") or props.get("softVolumes") or []
if not isinstance(volumes, list) or not volumes:
    raise SystemExit(3)

avg_raw = sum(float(v) for v in volumes) / len(volumes)
current = max(avg_raw, 0.0) ** (1.0 / 3.0) * 100.0

if action == "up":
    target = (math.floor(current / 5.0 + 1e-6) + 1.0) * 5.0
    maximum = value
elif action == "down":
    target = (math.ceil(current / 5.0 - 1e-6) - 1.0) * 5.0
    maximum = value
else:
    target = value
    maximum = value

maximum = max(0.0, min(200.0, maximum))
target = max(0.0, min(maximum, target))
raw = (target / 100.0) ** 3
channel_values = ", ".join(f"{raw:.9f}" for _ in volumes)
mute = "true" if bool(props.get("mute", False)) else "false"
print(f"{int(route.get("index"))}|{route_device}|{channel_values}|{mute}")
' "$route_device" "$ACTION" "$VALUE")"; then
  fallback_volume
  exit 0
fi

IFS='|' read -r route_index route_device_out channel_values mute_state <<<"$route_result"
[[ $route_index =~ ^-?[0-9]+$ && $route_device_out =~ ^-?[0-9]+$ && -n $channel_values ]] || {
  fallback_volume
  exit 0
}

pw-cli s "$device_id" Route \
  "{ index: ${route_index}, device: ${route_device_out}, props: { channelVolumes: [ ${channel_values} ], mute: ${mute_state} }, save: true }" \
  >/dev/null
