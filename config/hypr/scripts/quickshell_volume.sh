#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# Serialized default output volume control for the Awtarchy bar.

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

for command in wpctl python3 flock; do
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

limit_ratio="$(python3 -c 'import sys; print(max(0.0, min(2.0, float(sys.argv[1]) / 100.0)))' "$VALUE")"

case "$ACTION" in
  up)
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ --limit "$limit_ratio"
    ;;
  down)
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- --limit "$limit_ratio"
    ;;
  set)
    wpctl set-volume @DEFAULT_AUDIO_SINK@ "${VALUE}%" --limit "$limit_ratio"
    ;;
esac
