#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_weather.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$HELPER" ]] || fail 'lockscreen weather refresh helper is missing'

mkdir -p "$TMP/bin" "$TMP/cache/awtarchy" "$TMP/home"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$TEST_CURL_LOG"
case "$*" in
    *ipwho.is*)
        printf '%s\n' '{"success":true,"city":"Pittsburgh","region":"Pennsylvania","country_code":"US","latitude":40.4406,"longitude":-79.9959}'
        ;;
    *geocoding-api.open-meteo.com*)
        printf '%s\n' '{"results":[{"name":"Pittsburgh","admin1":"Pennsylvania","country_code":"US","latitude":40.4406,"longitude":-79.9959}]}'
        ;;
    *api.open-meteo.com*)
        printf '%s\n' '{"current":{"temperature_2m":72.3,"weather_code":0},"current_units":{"temperature_2m":"°F"}}'
        ;;
    *)
        exit 22
        ;;
esac
STUB
chmod 0755 "$TMP/bin/curl"

export TEST_CURL_LOG="$TMP/curl.log"
PATH="$TMP/bin:$PATH" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" \
    bash "$HELPER" refresh 'Pittsburgh, PA'

CACHE="$TMP/cache/awtarchy/lockscreen-weather.json"
[[ -s "$CACHE" ]] || fail 'weather helper did not write the lockscreen cache'
jq -e '
    .provider == "open-meteo"
    and .summary == "72°F · Clear"
    and .location == "Pittsburgh, Pennsylvania"
    and (.fetched_at | type) == "number"
    and (.expires_at | type) == "number"
    and (.expires_at - .fetched_at) == 1800
' "$CACHE" >/dev/null || fail 'weather helper wrote an invalid explicit-location cache payload'

grep -Fq -- 'geocoding-api.open-meteo.com' "$TEST_CURL_LOG" \
    || fail 'weather helper did not use Open-Meteo geocoding for an explicit location'
grep -Fq -- 'api.open-meteo.com' "$TEST_CURL_LOG" \
    || fail 'weather helper did not use Open-Meteo forecast API'
grep -Fq -- 'name=Pittsburgh, PA' "$TEST_CURL_LOG" \
    || fail 'weather helper did not send the explicit configured location'
if grep -Fq -- 'ipwho.is' "$TEST_CURL_LOG"; then
    fail 'explicit weather location unnecessarily triggered IP geolocation'
fi
grep -Fq -- '--connect-timeout' "$TEST_CURL_LOG" \
    || fail 'weather helper curl calls have no connection timeout'
grep -Fq -- '--max-time' "$TEST_CURL_LOG" \
    || fail 'weather helper curl calls have no total timeout'

: >"$TEST_CURL_LOG"
PATH="$TMP/bin:$PATH" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" \
    bash "$HELPER" refresh ''

jq -e '
    .provider == "open-meteo"
    and .summary == "72°F · Clear"
    and .location == "Pittsburgh, Pennsylvania"
' "$CACHE" >/dev/null || fail 'automatic weather location wrote an invalid cache payload'
grep -Fq -- 'ipwho.is' "$TEST_CURL_LOG" \
    || fail 'blank weather location did not use automatic public-IP geolocation'
grep -Fq -- 'api.open-meteo.com' "$TEST_CURL_LOG" \
    || fail 'automatic weather location did not fetch Open-Meteo forecast data'
if grep -Fq -- 'geocoding-api.open-meteo.com' "$TEST_CURL_LOG"; then
    fail 'automatic weather location unnecessarily used text geocoding'
fi

before_calls="$(wc -l <"$TEST_CURL_LOG")"
if PATH="$TMP/bin:$PATH" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" \
    bash "$HELPER" refresh $'Pittsburgh\nPA' >/dev/null 2>&1; then
    fail 'weather helper accepted a control character in an explicit location'
fi
long_location="$(printf 'x%.0s' {1..97})"
if PATH="$TMP/bin:$PATH" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" \
    bash "$HELPER" refresh "$long_location" >/dev/null 2>&1; then
    fail 'weather helper accepted more than 96 characters in an explicit location'
fi
after_calls="$(wc -l <"$TEST_CURL_LOG")"
[[ "$before_calls" -eq "$after_calls" ]] \
    || fail 'invalid explicit weather location still triggered a network request'

cp -- "$CACHE" "$TMP/cache-before.json"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
exit 28
STUB
chmod 0755 "$TMP/bin/curl"
if PATH="$TMP/bin:$PATH" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" \
    bash "$HELPER" refresh '' >/dev/null 2>&1; then
    fail 'automatic weather refresh reported success after a network failure'
fi
cmp -s "$CACHE" "$TMP/cache-before.json" \
    || fail 'failed automatic weather refresh destroyed or replaced the prior cache'

printf 'PASS: lockscreen weather refresh contracts\n'
