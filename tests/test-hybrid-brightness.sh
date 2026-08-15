#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROLLER_SOURCE="${ROOT}/config/hypr/scripts/hypr-ddc-brightness.sh"
BAR_MODULE_SOURCE="${ROOT}/config/hypr/scripts/ddc_brightness.sh"
TMP="$(mktemp -d)"
CONTROLLER="${TMP}/hypr-ddc-brightness.sh"
BAR_MODULE="${TMP}/ddc_brightness.sh"

cleanup() {
  local pid_file pid
  pid_file="${TMP}/runtime/hypr-ddc-brightness-$(id -u)/worker_LVDS-1.pid"
  if [[ -r "$pid_file" ]]; then
    IFS= read -r pid <"$pid_file" || true
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  fi
  rm -rf -- "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
install -m 0755 "$CONTROLLER_SOURCE" "$CONTROLLER"
install -m 0755 "$BAR_MODULE_SOURCE" "$BAR_MODULE"

fakebin="${TMP}/fakebin"
config_home="${TMP}/config"
cache_home="${TMP}/cache"
runtime_dir="${TMP}/runtime"
backlight_root="${TMP}/sys/class/backlight"
backlight_target="${TMP}/sys/devices/pci0000:00/0000:00:02.0/drm/card2/card2-LVDS-1/intel_backlight"
monitor_json="${TMP}/monitors.json"
brightness_state="${TMP}/brightness.state"
brightness_log="${TMP}/brightness.log"
ddc_state="${TMP}/ddc.state"
ddc_log="${TMP}/ddc.log"

mkdir -p \
  "$fakebin" \
  "$config_home/hypr" \
  "$cache_home" \
  "$runtime_dir" \
  "$backlight_root" \
  "$backlight_target"
ln -s "$backlight_target" "$backlight_root/intel_backlight"

printf '%s\n' '2458 4710' >"$brightness_state"
printf '%s\n' '40 100' >"$ddc_state"
: >"$brightness_log"
: >"$ddc_log"

cat >"${fakebin}/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $* == '-j monitors' ]]; then
  cat "${AWTARCHY_TEST_MONITOR_JSON:?}"
  exit 0
fi
exit 2
EOF

cat >"${fakebin}/brightnessctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_TEST_BRIGHTNESS_LOG:?}"

device=""
operation=""
value=""
while (( $# )); do
  case "$1" in
    -c|--class|-d|--device)
      [[ "$1" == -d || "$1" == --device ]] && device="${2:-}"
      shift 2
      ;;
    -q|--quiet|-m|--machine-readable)
      shift
      ;;
    info|get|max)
      operation="$1"
      shift
      ;;
    set)
      operation="$1"
      value="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ "$device" == intel_backlight ]] || exit 3
read -r current maximum <"${AWTARCHY_TEST_BRIGHTNESS_STATE:?}"
percent=$(( (current * 100 + maximum / 2) / maximum ))

case "$operation" in
  info)
    printf 'intel_backlight,backlight,%s,%s%%,%s\n' "$current" "$percent" "$maximum"
    ;;
  get)
    printf '%s\n' "$current"
    ;;
  max)
    printf '%s\n' "$maximum"
    ;;
  set)
    [[ "$value" =~ ^[0-9]+%$ ]] || exit 4
    percent="${value%%%}"
    (( percent >= 0 && percent <= 100 )) || exit 5
    current=$(( (maximum * percent + 50) / 100 ))
    printf '%s %s\n' "$current" "$maximum" >"${AWTARCHY_TEST_BRIGHTNESS_STATE:?}"
    ;;
  *)
    exit 6
    ;;
esac
EOF

cat >"${fakebin}/ddcutil" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_TEST_DDC_LOG:?}"
args=("$@")

for index in "${!args[@]}"; do
  case "${args[$index]}" in
    getvcp)
      read -r current maximum <"${AWTARCHY_TEST_DDC_STATE:?}"
      printf 'VCP code 0x10 (Brightness): current value = %s, max value = %s\n' \
        "$current" "$maximum"
      exit 0
      ;;
    setvcp)
      target="${args[$((index + 2))]:-}"
      [[ "$target" =~ ^[0-9]+$ ]] || exit 7
      read -r _current maximum <"${AWTARCHY_TEST_DDC_STATE:?}"
      printf '%s %s\n' "$target" "$maximum" >"${AWTARCHY_TEST_DDC_STATE:?}"
      exit 0
      ;;
  esac
done

exit 8
EOF

chmod 0755 "${fakebin}/"*

write_monitor() {
  local connector="$1" make="$2" model="$3" serial="$4"
  jq -cn \
    --arg connector "$connector" \
    --arg make "$make" \
    --arg model "$model" \
    --arg serial "$serial" \
    '[{
      name:$connector,
      make:$make,
      model:$model,
      serial:$serial,
      description:($make + " " + $model),
      focused:true
    }]' >"$monitor_json"
}

run_controller() {
  env \
    PATH="${fakebin}:$PATH" \
    HOME="$TMP" \
    XDG_CONFIG_HOME="$config_home" \
    XDG_CACHE_HOME="$cache_home" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    HYPR_BACKLIGHT_SYSFS_DIR="$backlight_root" \
    HYPR_DDC_NOTIFY=0 \
    HYPR_DDC_DEBOUNCE_MS=10 \
    HYPR_DDC_MAX_WAIT_MS=100 \
    AWTARCHY_TEST_MONITOR_JSON="$monitor_json" \
    AWTARCHY_TEST_BRIGHTNESS_STATE="$brightness_state" \
    AWTARCHY_TEST_BRIGHTNESS_LOG="$brightness_log" \
    AWTARCHY_TEST_DDC_STATE="$ddc_state" \
    AWTARCHY_TEST_DDC_LOG="$ddc_log" \
    "$CONTROLLER" "$@"
}

write_monitor "LVDS-1" "AU Optronics" "0x203E" ""
internal_status="$(run_controller --monitor LVDS-1 status)"
grep -Fxq 'conn=LVDS-1' <<<"$internal_status" || fail "internal connector was not selected"
grep -Fxq 'cur=52' <<<"$internal_status" || fail "internal raw brightness was not normalized"
grep -Fxq 'max=100' <<<"$internal_status" || fail "internal brightness maximum was not normalized"
grep -Fxq 'backend=backlight' <<<"$internal_status" || fail "LVDS did not use the backlight backend"
grep -Fxq 'device=intel_backlight' <<<"$internal_status" || fail "LVDS did not map to intel_backlight"
[[ ! -s "$ddc_log" ]] || fail "internal brightness invoked ddcutil"

bar_json="$(
  env \
    PATH="${fakebin}:$PATH" \
    HOME="$TMP" \
    XDG_CONFIG_HOME="$config_home" \
    XDG_CACHE_HOME="$cache_home" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    HYPR_BRIGHTNESS_SCRIPT="$CONTROLLER" \
    HYPR_BACKLIGHT_SYSFS_DIR="$backlight_root" \
    HYPR_DDC_NOTIFY=0 \
    AWTARCHY_OUTPUT_NAME=LVDS-1 \
    AWTARCHY_TEST_MONITOR_JSON="$monitor_json" \
    AWTARCHY_TEST_BRIGHTNESS_STATE="$brightness_state" \
    AWTARCHY_TEST_BRIGHTNESS_LOG="$brightness_log" \
    AWTARCHY_TEST_DDC_STATE="$ddc_state" \
    AWTARCHY_TEST_DDC_LOG="$ddc_log" \
    "$BAR_MODULE" status
)"
[[ $(jq -r '.percentage' <<<"$bar_json") == 52 ]] \
  || fail "bar did not expose internal-panel percentage"
[[ $(jq -r '.tooltip' <<<"$bar_json") != *DDC* ]] \
  || fail "bar still described the internal panel as DDC"

run_controller --monitor LVDS-1 set 40
grep -Fq 'set 40%' "$brightness_log" || fail "internal set did not use a logical percentage"
internal_status="$(run_controller --monitor LVDS-1 status)"
grep -Fxq 'cur=40' <<<"$internal_status" || fail "internal set did not update brightness"

run_controller --monitor LVDS-1 up 5
for _ in {1..100}; do
  IFS=' ' read -r raw maximum <"$brightness_state"
  [[ $raw == 2120 && $maximum == 4710 ]] && break
  sleep 0.05
done
[[ $raw == 2120 && $maximum == 4710 ]] \
  || fail "debounced internal adjustment did not apply five percentage points"

edp_target="${TMP}/sys/devices/pci0000:00/0000:00:02.0/drm/card2/card2-eDP-1/intel_backlight"
mkdir -p "$edp_target"
ln -sfn "$edp_target" "$backlight_root/intel_backlight"
write_monitor "eDP-1" "Internal" "Panel" ""
edp_status="$(run_controller --monitor eDP-1 status)"
grep -Fxq 'backend=backlight' <<<"$edp_status" || fail "eDP did not use the backlight backend"
grep -Fxq 'device=intel_backlight' <<<"$edp_status" || fail "eDP did not map to intel_backlight"

printf '%s\n' 'DP-1=7' >"$config_home/hypr/ddcutil-bus-map.conf"
write_monitor "DP-1" "Dell Inc." "U2720Q" "ABC123"
brightness_calls_before="$(wc -l <"$brightness_log")"
external_status="$(run_controller --monitor DP-1 status)"
grep -Fxq 'conn=DP-1' <<<"$external_status" || fail "external connector was not selected"
grep -Fxq 'cur=40' <<<"$external_status" || fail "external DDC brightness changed unexpectedly"
grep -Fxq 'max=100' <<<"$external_status" || fail "external DDC maximum changed unexpectedly"
grep -Fxq 'backend=ddc' <<<"$external_status" || fail "external monitor did not use DDC"
grep -Fxq 'bus=7' <<<"$external_status" || fail "external monitor lost its configured DDC bus"

run_controller --monitor DP-1 set 45
IFS=' ' read -r ddc_current ddc_maximum <"$ddc_state"
[[ $ddc_current == 45 && $ddc_maximum == 100 ]] || fail "external DDC write failed"
[[ $(wc -l <"$brightness_log") == "$brightness_calls_before" ]] \
  || fail "external DDC brightness invoked brightnessctl"
grep -Fq -- '--bus 7' "$ddc_log" || fail "external DDC command did not retain its bus selection"

printf '%s\n' "Hybrid brightness backend tests passed."
