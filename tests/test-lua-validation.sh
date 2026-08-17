#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_SOURCE="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
HYPRLAND_CONFIG="${ROOT}/config/hypr/hyprland.lua"
QT5CT_CONFIG="${ROOT}/config/qt5ct/qt5ct.conf"
QT6CT_CONFIG="${ROOT}/config/qt6ct/qt6ct.conf"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

command -v lua >/dev/null 2>&1 || fail "lua is required for this test"

if grep -Fq 'gnome-keyring-daemon --start' "$HYPRLAND_CONFIG"; then
  fail "Hyprland still starts GNOME Keyring manually instead of leaving startup to the login/session integration"
fi

if grep -Fq 'hl.env("QT_STYLE_OVERRIDE"' "$HYPRLAND_CONFIG"; then
  fail "Hyprland globally forces QT_STYLE_OVERRIDE, which breaks Qt Quick/Kirigami applications"
fi

grep -Fq 'hl.env("QT_QUICK_CONTROLS_STYLE", "org.hyprland.style")' "$HYPRLAND_CONFIG" \
  || fail "Hyprland Quick Controls style selection is missing"
grep -Fq 'style=kvantum-dark' "$QT5CT_CONFIG" \
  || fail "Qt5 configuration no longer selects the Awtarchy Kvantum style"
grep -Fq 'style=kvantum-dark' "$QT6CT_CONFIG" \
  || fail "Qt6 configuration no longer selects the Awtarchy Kvantum style"

if grep -Fq "lua -e 'assert(loadfile(arg[1]))'" "$RUNTIME_SOURCE"; then
  fail "runtime still validates Lua through arg[1] and standard input"
fi

awk '
  /^validate_candidate\(\) \{/ { capture=1 }
  capture { print }
  capture && /^}$/ { exit }
' "$RUNTIME_SOURCE" > "$TMP/validate_candidate.sh"

# shellcheck disable=SC2016
grep -Fq 'AWTARCHY_LUA_VALIDATE_FILE="$file" lua -e' "$TMP/validate_candidate.sh" \
  || fail "validate_candidate does not pass the Lua path explicitly"

# shellcheck source=/dev/null
source "$TMP/validate_candidate.sh"

valid_lua="$TMP/valid config.lua"
invalid_lua="$TMP/invalid config.lua"
execution_marker="$TMP/lua-config-executed"

printf '%s\n' \
  'local marker = os.getenv("AWTARCHY_LUA_EXECUTION_MARKER")' \
  'if marker then' \
  '  local output = assert(io.open(marker, "w"))' \
  '  output:write("executed\\n")' \
  '  output:close()' \
  'end' \
  'return true' >"$valid_lua"
printf '%s\n' 'local broken =' >"$invalid_lua"

export AWTARCHY_LUA_EXECUTION_MARKER="$execution_marker"

validate_candidate "$valid_lua" '.config/hypr/valid config.lua' </dev/null \
  || fail "valid Lua failed validation with closed standard input"
[[ ! -e $execution_marker ]] \
  || fail "Lua validation executed the config instead of only compiling it"

printf '/terminal input must not be parsed as Lua\n' \
  | validate_candidate "$valid_lua" '.config/hypr/valid config.lua' \
  || fail "Lua validation consumed terminal input"
[[ ! -e $execution_marker ]] \
  || fail "Lua validation executed the config while terminal input was present"

if validate_candidate "$invalid_lua" '.config/hypr/invalid config.lua' </dev/null; then
  fail "invalid Lua passed validation"
fi

printf 'Lua validation tests passed.\n'