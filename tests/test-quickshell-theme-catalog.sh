#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="${ROOT}/config/hypr/scripts/quickshell_theme_catalog.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

config="${TMP}/config"
mkdir -p "${config}/hypr/themes"
marker="${TMP}/executed"

cat >"${config}/hypr/themes/zeta_theme" <<EOF
QS_BACKGROUND="#111111"
QS_FOREGROUND="#eeeeee"
QS_HOVER="#222222"
QS_FOCUS="#333333"
QS_ACTIVE="#181818"
QS_URGENT="#ff0000"
QS_DARK="#090909"
QS_CHARGING="#00ff00"
QS_CRITICAL="#ff0000"
QS_MUTED="#888888"
NEW_ACTIVE_BORDER="eeeeeeff"
NEW_INACTIVE_BORDER="111111ff"
MICRO_COLORSCHEME="zenburn"
ALACRITTY_THEME="wombat.toml"
SPEEDCRUNCH_COLORSCHEME="zeta_theme"
EVIL="\$(touch ${marker})"
EOF

cp -- "${config}/hypr/themes/zeta_theme" "${config}/hypr/themes/zeta_theme.backup"
sed 's/zeta_theme/alpha-theme/g' \
    "${config}/hypr/themes/zeta_theme" >"${config}/hypr/themes/alpha-theme"

[[ -f "$CATALOG" ]] || fail "theme catalog helper does not exist"

json="$(XDG_CONFIG_HOME="$config" bash "$CATALOG")"

jq -e 'length == 2' <<<"$json" >/dev/null \
    || fail "catalog did not exclude backup files"
jq -e '.[0].name == "alpha-theme" and .[1].name == "zeta_theme"' <<<"$json" >/dev/null \
    || fail "catalog ordering is not deterministic"
jq -e '.[0].display_name == "Alpha Theme" and .[1].display_name == "Zeta Theme"' <<<"$json" >/dev/null \
    || fail "display names were not normalized"
jq -e '.[1].palette.background == "#111111" and .[1].palette.foreground == "#eeeeee"' <<<"$json" >/dev/null \
    || fail "palette values were not parsed"
jq -e '.[1].borders.active == "eeeeeeff" and .[1].borders.inactive == "111111ff"' <<<"$json" >/dev/null \
    || fail "border values were not parsed"
jq -e '.[1].apps.micro == "zenburn" and .[1].apps.alacritty == "wombat.toml" and .[1].apps.speedcrunch == "zeta_theme"' <<<"$json" >/dev/null \
    || fail "application theme metadata was not parsed"
[[ ! -e "$marker" ]] || fail "theme catalog executed theme-file contents"

stock_config="${TMP}/stock-config"
mkdir -p "${stock_config}/hypr"
cp -a -- "${ROOT}/config/hypr/themes" "${stock_config}/hypr/themes"
stock_json="$(XDG_CONFIG_HOME="$stock_config" bash "$CATALOG")"

jq -e 'length > 0' <<<"$stock_json" >/dev/null \
    || fail "stock catalog is empty"
jq -e 'all(.[].palette[]; test("^#[0-9a-fA-F]{6}$"))' <<<"$stock_json" >/dev/null \
    || fail "a stock theme has an invalid preview color"
jq -e 'all(.[].borders[]; test("^[0-9a-fA-F]{8}$"))' <<<"$stock_json" >/dev/null \
    || fail "a stock theme has an invalid border color"

expected_names="$(find "${stock_config}/hypr/themes" -maxdepth 1 -type f ! -name '*.backup*' -printf '%f\n' | LC_ALL=C sort)"
actual_names="$(jq -r '.[].name' <<<"$stock_json")"
[[ "$actual_names" == "$expected_names" ]] \
    || fail "stock catalog does not match the sorted theme files"

printf '%s\n' 'Quickshell theme catalog test passed.'
