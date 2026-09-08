#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/local/share/awtarchy/awtarchy-lockscreen-hyprland-migrate.py"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$HELPER" ]] || fail "missing live Hyprland lockscreen migration helper"
python3 -m py_compile "$HELPER"

live="${TMP}/hyprland.lua"
out="${TMP}/hyprland.new.lua"
cat >"$live" <<'EOF'
-- personal monitor and screenshare customizations must survive
hl.monitor({ output = "DP-3", mode = "1920x1080@400", position = "0x0", scale = 1 })
hl.permission("/usr/bin/hyprlock", "screencopy", "allow")
hl.window_rule({ match = { class = "^(vesktop)$" }, no_screen_share = true })

-- default mode
hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"), {})

-- unrelated personal bind
hl.bind("SUPER + F11", hl.dsp.exec_cmd("notify-send custom"), {})

-- noalt submap copy
hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"), {})
EOF

python3 "$HELPER" "$live" "$out" \
    || fail 'known Awtarchy Hyprlock references could not be migrated'

[[ -s "$out" ]] || fail 'migration helper produced no output'
! grep -Fqi -- 'hyprlock' "$out" \
    || fail 'known Hyprlock references remained after live migration'
if grep -Fq 'hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})' "$out"; then
    fail 'direct SUPER + L lock binding remained after migration'
fi
grep -Fq 'hl.window_rule({ match = { class = "^(vesktop)$" }, no_screen_share = true })' "$out" \
    || fail 'personal screenshare customization was lost'
grep -Fq 'hl.monitor({ output = "DP-3", mode = "1920x1080@400", position = "0x0", scale = 1 })' "$out" \
    || fail 'personal monitor customization was lost'
grep -Fq 'hl.bind("SUPER + F11", hl.dsp.exec_cmd("notify-send custom"), {})' "$out" \
    || fail 'unrelated personal bind was lost'

# A machine that already ran the first cutover may contain the temporary native
# SUPER+L lock bindings but no literal Hyprlock reference. Those known Awtarchy
# lines are also removed without touching unrelated personal configuration.
intermediate="${TMP}/hyprland-intermediate.lua"
intermediate_out="${TMP}/hyprland-intermediate.new.lua"
cat >"$intermediate" <<'EOF'
hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})
hl.bind("SUPER + F11", hl.dsp.exec_cmd("notify-send custom"), {})
hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})
EOF
python3 "$HELPER" "$intermediate" "$intermediate_out" \
    || fail 'intermediate Awtarchy SUPER+L lock bindings could not be retired'
if grep -Fq 'awtarchy_lock.sh lock' "$intermediate_out"; then
    fail 'intermediate direct SUPER+L lock binding remained after migration'
fi
grep -Fq 'notify-send custom' "$intermediate_out" \
    || fail 'intermediate migration lost unrelated personal configuration'

# Unknown/custom Hyprlock usage must block automatic package retirement instead
# of being silently deleted or leaving a broken preserved config behind.
custom="${TMP}/hyprland-custom.lua"
custom_out="${TMP}/hyprland-custom.new.lua"
cat >"$custom" <<'EOF'
hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock --immediate"), {})
EOF

if python3 "$HELPER" "$custom" "$custom_out" >/dev/null 2>&1; then
    fail 'unknown custom Hyprlock reference was accepted for automatic migration'
fi
[[ ! -e "$custom_out" ]] \
    || fail 'failed custom migration left an output file that could be installed'
grep -Fq 'hyprlock --immediate' "$custom" \
    || fail 'failed custom migration modified the source config'

printf 'PASS: personalized live Hyprland Hyprlock migration\n'
