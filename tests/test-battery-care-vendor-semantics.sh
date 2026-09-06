#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"
DETECTOR="${ROOT}/config/hypr/scripts/quickshell_battery_care.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$HELPER" ]] || fail 'power-profile-helper is missing'
[[ -f "$DETECTOR" ]] || fail 'battery detector is missing'

grep -Fq 'setcharge' "$HELPER" \
    || fail 'battery helper does not delegate threshold application to tlp setcharge'
grep -Fq 'battery_config_suffixes' "$HELPER" \
    || fail 'battery helper does not derive managed config keys from TLP output'

for source in "$HELPER" "$DETECTOR"; do
    if grep -Eq '(^|[^[:alnum:]_-])(asus|dell|huawei|lenovo|lg|samsung|sony|thinkpad|tuxedo)([^[:alnum:]_-]|$)' "$source"; then
        fail "${source#"$ROOT"/} still contains vendor-specific battery behavior"
    fi
done

if grep -Eq 'battery-enable-fixed|Long_Life|conservation_mode|battery_life_extender|battery_care_limiter' "$HELPER"; then
    fail 'privileged helper still translates vendor selector semantics'
fi

printf '%s\n' 'PASS: Battery Care helper contains no vendor-specific write semantics.'
