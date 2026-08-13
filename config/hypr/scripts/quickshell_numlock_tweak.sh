#!/bin/sh
set -eu

hyprctl eval 'hl.config({ input = { numlock_by_default = true } })' >/dev/null
hyprctl eval 'hl.config({ input = { numlock_by_default = false } })' >/dev/null
