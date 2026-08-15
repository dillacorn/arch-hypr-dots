#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

grep -Fq 'pacman_install_one playerctl || die "Failed to install required media-control dependency: playerctl"' "$RUNTIME" \
  || fail 'fresh installs do not guarantee playerctl'

grep -Fq 'local -a required=(quickshell upower playerctl) missing=()' "$RUNTIME" \
  || fail 'normal updates do not guarantee playerctl'

grep -Fq "hyprland quickshell upower playerctl \\" "$RUNTIME" \
  || fail 'troubleshoot output does not report playerctl'

printf 'PASS: playerctl is required by install/update paths and visible to troubleshooting.\n'