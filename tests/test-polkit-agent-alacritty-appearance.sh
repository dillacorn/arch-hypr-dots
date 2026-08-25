#!/usr/bin/bash
set -euo pipefail

AUTH_CONFIG="config/hypr/scripts/awtarchy-polkit-agent/alacritty.toml"
MAIN_CONFIG="config/alacritty/alacritty.toml"

[[ -f $AUTH_CONFIG ]]
[[ -f $MAIN_CONFIG ]]

# The trusted authentication terminal should look like Awtarchy's normal
# Alacritty without importing any user-writable configuration at runtime.
grep -Fq 'padding = { x = 22, y = 22 }' "$MAIN_CONFIG"
grep -Fq 'opacity = 0.85' "$MAIN_CONFIG"
grep -Fq 'decorations = "Buttonless"' "$MAIN_CONFIG"
grep -Eq '^size = 12([.]0+)?$' "$MAIN_CONFIG"
grep -Fq '"~/.config/alacritty/themes/themes/wombat.toml"' "$MAIN_CONFIG"

grep -Fq 'padding = { x = 22, y = 22 }' "$AUTH_CONFIG"
grep -Fq 'opacity = 0.85' "$AUTH_CONFIG"
grep -Fq 'decorations = "Buttonless"' "$AUTH_CONFIG"
grep -Eq '^size = 12([.]0+)?$' "$AUTH_CONFIG"

# Trusted embedded Wombat palette. Do not load the user's live theme file in
# the authentication process.
grep -Fq 'background = "#1f1f1f"' "$AUTH_CONFIG"
grep -Fq 'foreground = "#e5e1d8"' "$AUTH_CONFIG"
grep -Fq 'magenta = "#ef88ff"' "$AUTH_CONFIG"
grep -Fq 'green = "#bde97c"' "$AUTH_CONFIG"
grep -Fq 'bright_magenta = "#e5bdff"' "$AUTH_CONFIG"
grep -Fq 'bright_green = "#e3f7a1"' "$AUTH_CONFIG"

# Authentication history stays disabled even though the normal terminal keeps
# scrollback.
grep -Fq 'history = 0' "$AUTH_CONFIG"

if grep -Eq '(^|[[:space:]])import[[:space:]]*=|~/[.]config|/home/' "$AUTH_CONFIG"; then
    echo 'authentication Alacritty config must not import user-writable files' >&2
    exit 1
fi

echo 'Polkit Alacritty appearance contract passed.'
