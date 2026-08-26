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

grep -Fq 'pacman_install_one hyprland-qt-support || die "Failed to install required Hyprland Qt style provider: hyprland-qt-support"' "$RUNTIME" \
  || fail 'fresh installs do not guarantee hyprland-qt-support'

grep -Fq 'local -a required=(quickshell upower playerctl hyprland-qt-support polkit python-gobject) missing=()' "$RUNTIME" \
  || fail 'normal updates do not guarantee playerctl, hyprland-qt-support, and PolicyKit dependencies'

grep -Fq "hyprland hyprland-qt-support quickshell upower playerctl \\" "$RUNTIME" \
  || fail 'troubleshoot output does not report required shell dependencies'

printf 'PASS: playerctl and hyprland-qt-support are required by install/update paths and visible to troubleshooting.\n'