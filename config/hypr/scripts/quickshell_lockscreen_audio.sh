#!/usr/bin/env bash
set -euo pipefail

command -v cava >/dev/null 2>&1 || exit 0

config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
config_path="${config_home}/quickshell/awtarchy-lock/cava.conf"

[[ -r "$config_path" ]] || exit 0

exec cava -p "$config_path"
