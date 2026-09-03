#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="$ROOT/local/share/awtarchy/awtarchy-runtime.sh"
MIGRATOR="$ROOT/config/hypr/scripts/hyprmoncfg_config_migrate.py"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$MIGRATOR" ]] || fail 'Hyprmoncfg preserved-config migrator is missing'
grep -Fq 'hyprmoncfg_config_migrate.py' "$RUNTIME" \
    || fail 'updater does not invoke the Hyprmoncfg preserved-config migrator'

home="$TMP/home"
config="$home/.config/hypr/hyprland.lua"
mkdir -p "$(dirname "$config")"
cat >"$config" <<'EOF_CONFIG'
local maccel = "~/.config/hypr/scripts/launch_handler.sh maccel \"alacritty --class maccel -e maccel\""
local smtty = "smtty"

for _, bind in ipairs({
    { "SUPER + SHIFT + M", maccel },
}) do
    hl.bind(bind[1], hl.dsp.exec_cmd(bind[2]), {})
end

hl.define_submap("noalt", function()
    for _, bind in ipairs({
        { "SUPER + SHIFT + M", maccel },
    }) do
        hl.bind(bind[1], hl.dsp.exec_cmd(bind[2]), {})
    end
end)
EOF_CONFIG

HOME="$home" HYPRLAND_CONFIG="$config" python3 "$MIGRATOR"

grep -Fq 'local hyprmoncfg = "APP_NO_LAUNCH_IF_TILED=1 ~/.config/hypr/scripts/launch_handler.sh hyprmoncfg' "$config" \
    || fail 'migration did not add the Hyprmoncfg launcher variable'
[[ $(grep -Fc '{ "SUPER + CTRL + M", hyprmoncfg },' "$config" || true) -eq 2 ]] \
    || fail 'migration did not add SUPER+CTRL+M to normal and noalt bind tables'
grep -Fq 'hl.window_rule({ match = { class = "^(hyprmoncfg)$" }, float = true })' "$config" \
    || fail 'migration did not add Hyprmoncfg floating rule'
grep -Fq 'hl.window_rule({ match = { class = "^(hyprmoncfg)$" }, size = { "(monitor_w*0.85)", "(monitor_h*0.90)" } })' "$config" \
    || fail 'migration did not add Hyprmoncfg size rule'
grep -Fq 'hl.window_rule({ match = { class = "^(hyprmoncfg)$" }, center = true })' "$config" \
    || fail 'migration did not add Hyprmoncfg centering rule'

before="$(sha256sum "$config" | awk '{print $1}')"
HOME="$home" HYPRLAND_CONFIG="$config" python3 "$MIGRATOR"
after="$(sha256sum "$config" | awk '{print $1}')"
[[ "$before" == "$after" ]] || fail 'migration is not idempotent'

conflict_home="$TMP/conflict-home"
conflict_config="$conflict_home/.config/hypr/hyprland.lua"
mkdir -p "$(dirname "$conflict_config")"
cat >"$conflict_config" <<'EOF_CONFLICT'
local maccel = "maccel"
for _, bind in ipairs({
    { "SUPER + SHIFT + M", maccel },
    { "SUPER + CTRL + M", "my-own-command" },
}) do
    hl.bind(bind[1], hl.dsp.exec_cmd(bind[2]), {})
end
EOF_CONFLICT
cp "$conflict_config" "$conflict_config.before"
HOME="$conflict_home" HYPRLAND_CONFIG="$conflict_config" python3 "$MIGRATOR" 2>"$TMP/conflict.err"
cmp -s "$conflict_config.before" "$conflict_config" \
    || fail 'migration overwrote a user-owned SUPER+CTRL+M binding'
grep -Fq 'already uses SUPER+CTRL+M' "$TMP/conflict.err" \
    || fail 'migration did not warn about the user-owned shortcut conflict'

printf '%s\n' 'PASS: preserved Hyprland configs receive Hyprmoncfg integration without replacing user binds.'
