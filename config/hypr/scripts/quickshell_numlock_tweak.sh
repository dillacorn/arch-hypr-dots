#!/usr/bin/env bash
set -euo pipefail

hyprctl eval 'hl.config({ input = { numlock_by_default = true } })' >/dev/null
hyprctl eval 'hl.config({ input = { numlock_by_default = false } })' >/dev/null
