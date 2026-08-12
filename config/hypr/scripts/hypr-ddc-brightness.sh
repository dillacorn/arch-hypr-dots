#!/usr/bin/env bash
# ~/.config/hypr/scripts/hypr-ddc-brightness.sh
# Brightness for a focused or explicitly selected Hyprland monitor.
# Internal LVDS/eDP panels use the kernel backlight through brightnessctl.
# External monitors retain the existing DDC/CI backend.
#
# Usage:
#   hypr-ddc-brightness.sh [--monitor CONNECTOR] up [step]
#   hypr-ddc-brightness.sh [--monitor CONNECTOR] down [step]
#   hypr-ddc-brightness.sh [--monitor CONNECTOR] status
#   hypr-ddc-brightness.sh [--monitor CONNECTOR] set <absolute_value>

set -euo pipefail

DEBOUNCE_MS="${HYPR_DDC_DEBOUNCE_MS:-160}"
MAX_WAIT_MS="${HYPR_DDC_MAX_WAIT_MS:-3500}"

NOTIFY_MS="${HYPR_DDC_NOTIFY_MS:-1800}"

GET_TIMEOUT="${HYPR_DDC_GET_TIMEOUT:-3}"
SET_TIMEOUT="${HYPR_DDC_SET_TIMEOUT:-3}"

STATE_TTL_MS="${HYPR_DDC_STATE_TTL_MS:-30000}"

now_ms() {
  if date +%s%3N >/dev/null 2>&1; then
    date +%s%3N
  else
    echo "$(( $(date +%s) * 1000 ))"
  fi
}

notify() {
  local ms="$1" summary="$2" body="$3" key="${4:-}"
  [[ "${HYPR_DDC_NOTIFY:-1}" == "0" ]] && return 0
  command -v notify-send >/dev/null 2>&1 || return 0

  if [[ -n "$key" ]]; then
    notify-send -a "hypr-ddc-brightness" -t "$ms" \
      -h "string:x-canonical-private-synchronous:$key" \
      "$summary" "$body" >/dev/null 2>&1 || true
  else
    notify-send -a "hypr-ddc-brightness" -t "$ms" \
      "$summary" "$body" >/dev/null 2>&1 || true
  fi
}

read_int_file() {
  local file="$1" def="${2:-0}" v=""
  if [[ -r "$file" ]]; then
    IFS= read -r v <"$file" || true
  fi
  [[ "$v" =~ ^-?[0-9]+$ ]] || v="$def"
  printf '%s\n' "$v"
}

read_uint_file() {
  local file="$1" def="${2:-0}" v=""
  if [[ -r "$file" ]]; then
    IFS= read -r v <"$file" || true
  fi
  [[ "$v" =~ ^[0-9]+$ ]] || v="$def"
  printf '%s\n' "$v"
}

lock_acquire() {
  local d="$1" i=0
  while ! mkdir "$d" 2>/dev/null; do
    i=$((i+1))
    [[ "$i" -gt 80 ]] && return 1
    sleep 0.02
  done
  return 0
}

lock_release() { rmdir "$1" 2>/dev/null || true; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "hypr-ddc-brightness: missing command: $1" >&2; exit 1; }
}

get_focused_monitor_tsv() {
  if [[ -n "${TARGET_CONN:-}" ]]; then
    hyprctl -j monitors 2>/dev/null | jq -r --arg conn "$TARGET_CONN" '
      .[] | select(.name == $conn) |
      [(.name//""),(.make//""),(.model//""),(.serial//""),(.description//"")] | @tsv
    ' | head -n1
  else
    hyprctl -j monitors 2>/dev/null | jq -r '
      .[] | select(.focused==true or .focused=="yes") |
      [(.name//""),(.make//""),(.model//""),(.serial//""),(.description//"")] | @tsv
    ' | head -n1
  fi
}

parse_vcp_any() {
  awk '
    {
      n=0
      for (i=1;i<=NF;i++) {
        x=$i
        gsub(/[,;]/,"",x)
        if (x ~ /^\([0-9]+\)$/) { gsub(/[()]/,"",x); nums[++n]=x; continue }
        if (x ~ /^[0-9]+$/) { nums[++n]=x; continue }
      }
      if (n>=2) print nums[n-1], nums[n]
    }
  '
}

MODE="client"
WORKER_CONN=""
TARGET_CONN="${HYPR_DDC_MONITOR:-}"

if [[ "${1:-}" == "--monitor" ]]; then
  [[ -n "${2:-}" ]] || {
    echo "hypr-ddc-brightness: --monitor requires a connector name" >&2
    exit 2
  }
  TARGET_CONN="$2"
  shift 2
fi

cmd="${1:-}"

case "$cmd" in
  --worker)
    MODE="worker"
    WORKER_CONN="${2:-}"
    [[ -n "${WORKER_CONN:-}" ]] || exit 1
    ;;
  up|down)
    dir="$cmd"
    step="${2:-5}"
    [[ "$step" =~ ^[0-9]+$ ]] || { echo "hypr-ddc-brightness: step must be integer" >&2; exit 2; }
    ;;
  status)
    ;;
  set)
    [[ -n "${2:-}" ]] || { echo "hypr-ddc-brightness: usage: $0 set <absolute_value>" >&2; exit 2; }
    [[ "$2" =~ ^[0-9]+$ ]] || { echo "hypr-ddc-brightness: set value must be integer" >&2; exit 2; }
    set_value="$2"
    ;;
  ""|-h|--help|help)
    cat <<'EOF'
Usage:
  hypr-ddc-brightness.sh [--monitor CONNECTOR] up [step]
  hypr-ddc-brightness.sh [--monitor CONNECTOR] down [step]
  hypr-ddc-brightness.sh [--monitor CONNECTOR] status
  hypr-ddc-brightness.sh [--monitor CONNECTOR] set <absolute_value>
EOF
    exit 0
    ;;
  *)
    echo "hypr-ddc-brightness: unknown cmd: $cmd" >&2
    exit 2
    ;;
esac

need_cmd hyprctl
need_cmd jq
need_cmd timeout

uid="$(id -u)"
rundir="${XDG_RUNTIME_DIR:-/tmp}/hypr-ddc-brightness-${uid}"
cachedir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-ddc-brightness"
config_map="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/ddcutil-bus-map.conf"
backlight_sysfs_dir="${HYPR_BACKLIGHT_SYSFS_DIR:-/sys/class/backlight}"
mkdir -p "$rundir" "$cachedir"

state_path_for_conn() { printf '%s/state_%s.tsv\n' "$cachedir" "$1"; }

read_state() {
  local conn="$1" sf
  sf="$(state_path_for_conn "$conn")"
  [[ -r "$sf" ]] || return 1
  awk 'NF>=3 {print $1, $2, $3; exit}' "$sf" 2>/dev/null
}

write_state() {
  local conn="$1" cur="$2" max="$3" ts sf tmp
  ts="$(now_ms)"
  sf="$(state_path_for_conn "$conn")"
  tmp="${sf}.tmp.$$"
  printf '%s\t%s\t%s\n' "$cur" "$max" "$ts" >"$tmp"
  mv -f "$tmp" "$sf"
}

notify_level() {
  local conn="$1" cur="$2" max="$3"
  notify "$NOTIFY_MS" "Brightness $conn" "${cur}/${max}" "hypr-ddc-$conn"
}

bus_from_config_map() {
  local conn="$1"
  [[ -f "$config_map" ]] || return 1
  awk -v c="$conn" '
    BEGIN{FS="[= \t]+"}
    $1==c && $2 ~ /^[0-9]+$/ { print $2; exit }
  ' "$config_map" 2>/dev/null | head -n1
}

bus_from_cache() {
  local conn="$1"
  local cache_tsv="$cachedir/busmap.tsv"
  [[ -f "$cache_tsv" ]] || return 1
  local now bus
  now="$(date +%s)"
  bus="$(
    awk -v c="$conn" -v now="$now" '
      $1==c && (now-$3) < 604800 { print $2; exit }
    ' "$cache_tsv" 2>/dev/null || true
  )"
  [[ -n "${bus:-}" ]] || return 1
  echo "$bus"
}

bus_from_detect_by_identity() {
  local conn="$1" hypr_make="$2" hypr_model="$3" hypr_serial="$4" hypr_desc="$5"
  local hypr_make_u hypr_model_u hypr_serial_u hypr_desc_u
  hypr_make_u="$(printf '%s' "$hypr_make" | tr '[:lower:]' '[:upper:]')"
  hypr_model_u="$(printf '%s' "$hypr_model" | tr '[:lower:]' '[:upper:]')"
  hypr_serial_u="$(printf '%s' "$hypr_serial" | tr -dc 'A-Za-z0-9' | tr '[:lower:]' '[:upper:]')"
  hypr_desc_u="$(printf '%s' "$hypr_desc" | tr '[:lower:]' '[:upper:]')"

  local best_bus="" best_score=-1

  while IFS=$'\t' read -r bus mfg model serial; do
    [[ -n "${bus:-}" ]] || continue

    local mfg_u model_u serial_u score=0
    mfg_u="$(printf '%s' "$mfg" | tr '[:lower:]' '[:upper:]')"
    model_u="$(printf '%s' "$model" | tr '[:lower:]' '[:upper:]')"
    serial_u="$(printf '%s' "$serial" | tr -dc 'A-Za-z0-9' | tr '[:lower:]' '[:upper:]')"

    if [[ -n "$hypr_serial_u" && -n "$serial_u" && "$hypr_serial_u" == "$serial_u" ]]; then
      score=$((score + 1000))
    fi

    if [[ -n "$hypr_model_u" && -n "$model_u" ]]; then
      if [[ "$model_u" == "$hypr_model_u" || "$model_u" == *"$hypr_model_u"* || "$hypr_model_u" == *"$model_u"* ]]; then
        score=$((score + 250))
      fi
    fi

    if [[ -n "$hypr_desc_u" && -n "$model_u" && "$hypr_desc_u" == *"$model_u"* ]]; then
      score=$((score + 150))
    fi

    if [[ -n "$hypr_make_u" && -n "$mfg_u" ]]; then
      if [[ "$hypr_make_u" == "$mfg_u" || "$hypr_make_u" == *"$mfg_u"* || "$mfg_u" == *"$hypr_make_u"* ]]; then
        score=$((score + 80))
      fi
    fi

    if (( score > best_score )); then
      best_score="$score"
      best_bus="$bus"
    fi
  done < <(
    timeout 3 ddcutil detect --verbose 2>/dev/null | awk '
      function flush() {
        if (bus != "") print bus "\t" mfg "\t" model "\t" serial
        bus=""; mfg=""; model=""; serial=""
      }
      /^Display[[:space:]]+[0-9]+/ { flush(); next }
      /I2C bus:/ { if (match($0, /\/dev\/i2c-([0-9]+)/, m)) bus=m[1]; next }
      /Mfg id:/ { s=$0; sub(/^.*Mfg id:[[:space:]]*/, "", s); mfg=s; next }
      /^ *Model:/ { s=$0; sub(/^.*Model:[[:space:]]*/, "", s); model=s; next }
      /Serial number:/ { s=$0; sub(/^.*Serial number:[[:space:]]*/, "", s); serial=s; next }
      END { flush() }
    '
  )

  [[ -n "${best_bus:-}" && "$best_score" -ge 180 ]] || return 1

  local cache_tsv="$cachedir/busmap.tsv" epoch tmp
  epoch="$(date +%s)"
  tmp="${cache_tsv}.tmp.$$"
  if [[ -f "$cache_tsv" ]]; then
    awk -v c="$conn" '$1!=c' "$cache_tsv" >"$tmp"
  else
    : >"$tmp"
  fi
  printf '%s\t%s\t%s\n' "$conn" "$best_bus" "$epoch" >>"$tmp"
  mv -f "$tmp" "$cache_tsv"

  echo "$best_bus"
}

get_bus_for_conn() {
  local conn="$1" hypr_make="$2" hypr_model="$3" hypr_serial="$4" hypr_desc="$5"
  local bus=""

  bus="$(bus_from_config_map "$conn" || true)"
  [[ -n "${bus:-}" ]] && { echo "$bus"; return 0; }

  bus="$(bus_from_cache "$conn" || true)"
  [[ -n "${bus:-}" ]] && { echo "$bus"; return 0; }

  bus_from_detect_by_identity "$conn" "$hypr_make" "$hypr_model" "$hypr_serial" "$hypr_desc"
}

is_internal_connector() {
  case "$1" in
    eDP-*|LVDS-*) return 0 ;;
    *) return 1 ;;
  esac
}

backlight_device_for_conn() {
  local conn="$1" path resolved device
  local -a devices=()

  if [[ -n "${HYPR_BACKLIGHT_DEVICE:-}" ]]; then
    path="${backlight_sysfs_dir}/${HYPR_BACKLIGHT_DEVICE}"
    [[ -e "$path" || -L "$path" ]] || return 1
    printf '%s\n' "$HYPR_BACKLIGHT_DEVICE"
    return 0
  fi

  shopt -s nullglob
  for path in "${backlight_sysfs_dir}"/*; do
    [[ -e "$path" || -L "$path" ]] || continue
    device="${path##*/}"
    devices+=("$device")
    resolved="$(readlink -f -- "$path" 2>/dev/null || true)"
    case "$resolved" in
      */card*-"$conn"/*)
        printf '%s\n' "$device"
        return 0
        ;;
    esac
  done

  # Some firmware/platform backlight paths do not include their DRM connector.
  # A single internal-panel backlight is unambiguous and safe to use.
  if is_internal_connector "$conn" && (( ${#devices[@]} == 1 )); then
    printf '%s\n' "${devices[0]}"
    return 0
  fi

  return 1
}

controller_for_conn() {
  local conn="$1" hypr_make="$2" hypr_model="$3" hypr_serial="$4" hypr_desc="$5"
  local controller=""

  if is_internal_connector "$conn"; then
    command -v brightnessctl >/dev/null 2>&1 || {
      echo "hypr-ddc-brightness: missing command: brightnessctl" >&2
      return 1
    }
    controller="$(backlight_device_for_conn "$conn" || true)"
    [[ -n "$controller" ]] || return 1
    printf 'backlight\t%s\n' "$controller"
    return 0
  fi

  command -v ddcutil >/dev/null 2>&1 || {
    echo "hypr-ddc-brightness: missing command: ddcutil" >&2
    return 1
  }
  controller="$(get_bus_for_conn "$conn" "$hypr_make" "$hypr_model" "$hypr_serial" "$hypr_desc" || true)"
  [[ -n "$controller" ]] || return 1
  printf 'ddc\t%s\n' "$controller"
}

build_ddc_base_cmd() {
  local bus="$1"
  local -a ddc_cmd=(ddcutil)
  local -a extra=()

  if [[ -n "${HYPR_DDC_SLEEP_MULTIPLIER:-}" ]]; then
    ddc_cmd+=(--sleep-multiplier "$HYPR_DDC_SLEEP_MULTIPLIER")
  fi
  if [[ "${HYPR_DDC_DISABLE_DYNAMIC_SLEEP:-0}" == "1" ]]; then
    ddc_cmd+=(--disable-dynamic-sleep)
  fi
  if [[ "${HYPR_DDC_NODETECT:-0}" == "1" ]]; then
    ddc_cmd+=(--nodetect)
  fi

  if [[ -n "${DDCUTIL_BUS:-}" ]]; then
    read -r -a extra <<<"$DDCUTIL_BUS"
    ddc_cmd+=("${extra[@]}")
  else
    ddc_cmd+=(--bus "$bus")
  fi

  printf '%s\0' "${ddc_cmd[@]}"
}

build_ddc_safe_cmd() {
  local bus="$1"
  local -a ddc_cmd=(ddcutil)
  local -a extra=()

  if [[ -n "${DDCUTIL_BUS:-}" ]]; then
    read -r -a extra <<<"$DDCUTIL_BUS"
    ddc_cmd+=("${extra[@]}")
  else
    ddc_cmd+=(--bus "$bus")
  fi

  printf '%s\0' "${ddc_cmd[@]}"
}

must_focused_info() {
  local line target

  line="$(get_focused_monitor_tsv || true)"
  target="${TARGET_CONN:-focused monitor}"

  [[ -n "${line:-}" ]] || {
    echo "hypr-ddc-brightness: monitor not found: $target" >&2
    exit 1
  }

  printf '%s\n' "$line"
}

ddc_get_curmax() {
  local bus="$1"
  local -a ddc=()
  local vcp cur max

  mapfile -d '' -t ddc < <(build_ddc_base_cmd "$bus")
  vcp="$(timeout "$GET_TIMEOUT" "${ddc[@]}" getvcp 0x10 2>/dev/null || true)"
  read -r cur max < <(printf '%s\n' "$vcp" | parse_vcp_any)
  if [[ -n "${cur:-}" && -n "${max:-}" ]]; then
    printf '%s %s\n' "$cur" "$max"
    return 0
  fi

  mapfile -d '' -t ddc < <(build_ddc_safe_cmd "$bus")
  vcp="$(timeout 5 "${ddc[@]}" getvcp 0x10 2>/dev/null || true)"
  read -r cur max < <(printf '%s\n' "$vcp" | parse_vcp_any)
  [[ -n "${cur:-}" && -n "${max:-}" ]] || return 1
  printf '%s %s\n' "$cur" "$max"
}

ddc_set_abs_fast() {
  local bus="$1" target="$2"
  local -a ddc=()

  mapfile -d '' -t ddc < <(build_ddc_base_cmd "$bus")
  if timeout "$SET_TIMEOUT" "${ddc[@]}" --noverify setvcp 0x10 "$target" >/dev/null 2>&1; then
    return 0
  fi

  mapfile -d '' -t ddc < <(build_ddc_safe_cmd "$bus")
  timeout 5 "${ddc[@]}" setvcp 0x10 "$target" >/dev/null 2>&1
}

backlight_get_curmax() {
  local device="$1" info found_device class raw _percentage raw_max logical

  info="$(brightnessctl -c backlight -d "$device" --machine-readable info 2>/dev/null || true)"
  IFS=',' read -r found_device class raw _percentage raw_max <<<"$info"

  [[ "$found_device" == "$device" ]] || return 1
  [[ "$class" == "backlight" ]] || return 1
  [[ "$raw" =~ ^[0-9]+$ ]] || return 1
  [[ "$raw_max" =~ ^[1-9][0-9]*$ ]] || return 1

  logical=$(( (raw * 100 + raw_max / 2) / raw_max ))
  (( logical < 0 )) && logical=0
  (( logical > 100 )) && logical=100
  printf '%s 100\n' "$logical"
}

backlight_set_abs_fast() {
  local device="$1" target="$2"

  (( target < 0 )) && target=0
  (( target > 100 )) && target=100
  brightnessctl -q -c backlight -d "$device" set "${target}%" >/dev/null 2>&1
}

brightness_get_curmax() {
  local backend="$1" controller="$2"
  case "$backend" in
    backlight) backlight_get_curmax "$controller" ;;
    ddc) ddc_get_curmax "$controller" ;;
    *) return 1 ;;
  esac
}

brightness_set_abs_fast() {
  local backend="$1" controller="$2" target="$3"
  case "$backend" in
    backlight) backlight_set_abs_fast "$controller" "$target" ;;
    ddc) ddc_set_abs_fast "$controller" "$target" ;;
    *) return 1 ;;
  esac
}

if [[ "$MODE" == "client" && "$cmd" == "status" ]]; then
  focused_line="$(must_focused_info)"
  IFS=$'\t' read -r conn make model serial desc <<<"$focused_line"

  controller="$(controller_for_conn "$conn" "$make" "$model" "$serial" "$desc" || true)"
  IFS=$'\t' read -r backend controller_id <<<"$controller"
  [[ -n "${backend:-}" && -n "${controller_id:-}" ]] \
    || { echo "hypr-ddc-brightness: no brightness controller for $conn" >&2; exit 1; }

  if ! read -r cur max < <(brightness_get_curmax "$backend" "$controller_id"); then
    echo "hypr-ddc-brightness: brightness read failed" >&2
    exit 1
  fi

  write_state "$conn" "$cur" "$max"
  printf 'conn=%s\ncur=%s\nmax=%s\nbackend=%s\n' "$conn" "$cur" "$max" "$backend"
  if [[ "$backend" == "backlight" ]]; then
    printf 'device=%s\n' "$controller_id"
  else
    printf 'bus=%s\n' "$controller_id"
  fi
  exit 0
fi

if [[ "$MODE" == "client" && "$cmd" == "set" ]]; then
  focused_line="$(must_focused_info)"
  IFS=$'\t' read -r conn make model serial desc <<<"$focused_line"

  controller="$(controller_for_conn "$conn" "$make" "$model" "$serial" "$desc" || true)"
  IFS=$'\t' read -r backend controller_id <<<"$controller"
  [[ -n "${backend:-}" && -n "${controller_id:-}" ]] \
    || { echo "hypr-ddc-brightness: no brightness controller for $conn" >&2; exit 1; }

  max=""
  if st="$(read_state "$conn" 2>/dev/null || true)"; then
    read -r _cur max _ts <<<"$st"
  fi
  if [[ -z "${max:-}" || ! "$max" =~ ^[0-9]+$ || "$max" -le 0 ]]; then
    if ! read -r _cur max < <(brightness_get_curmax "$backend" "$controller_id"); then
      echo "hypr-ddc-brightness: brightness read failed" >&2
      exit 1
    fi
  fi

  target="$set_value"
  (( target < 0 )) && target=0
  (( target > max )) && target="$max"

  if ! brightness_set_abs_fast "$backend" "$controller_id" "$target"; then
    echo "hypr-ddc-brightness: brightness write failed" >&2
    exit 1
  fi

  write_state "$conn" "$target" "$max"
  notify_level "$conn" "$target" "$max"
  exit 0
fi

if [[ "$MODE" == "client" ]]; then
  focused_line="$(must_focused_info)"
  IFS=$'\t' read -r conn _make _model _serial _desc <<<"$focused_line"

  sign=1
  [[ "$dir" == "down" ]] && sign=-1
  delta=$((sign * step))

  pending_file="$rundir/pending_${conn}.txt"
  last_file="$rundir/last_${conn}.txt"
  first_file="$rundir/first_${conn}.txt"
  pid_file="$rundir/worker_${conn}.pid"
  lock_dir="$rundir/lock_${conn}.d"

  lock_acquire "$lock_dir" || { echo "hypr-ddc-brightness: lock timeout" >&2; exit 1; }

  old_pending="$(read_int_file "$pending_file" 0)"
  new_pending=$((old_pending + delta))

  printf '%s\n' "$new_pending" >"$pending_file"
  printf '%s\n' "$(now_ms)" >"$last_file"
  if [[ "$old_pending" == "0" ]]; then
    printf '%s\n' "$(now_ms)" >"$first_file"
  fi

  lock_release "$lock_dir"

  if [[ -f "$pid_file" ]]; then
    wp="$(read_uint_file "$pid_file" 0)"
    if [[ "$wp" -gt 1 ]] && kill -0 "$wp" 2>/dev/null; then
      exit 0
    fi
  fi

  script_self="$(readlink -f "$0" 2>/dev/null || echo "$0")"
  nohup "$script_self" --worker "$conn" >/dev/null 2>&1 &
  exit 0
fi

conn="$WORKER_CONN"
pending_file="$rundir/pending_${conn}.txt"
last_file="$rundir/last_${conn}.txt"
first_file="$rundir/first_${conn}.txt"
pid_file="$rundir/worker_${conn}.pid"
lock_dir="$rundir/lock_${conn}.d"

printf '%s\n' "$$" >"$pid_file"

idle_loops=0

while :; do
  while :; do
    sleep 0.05
    now="$(now_ms)"
    last="$(read_uint_file "$last_file" 0)"
    first="$(read_uint_file "$first_file" 0)"

    idle_age=$((now - last))
    elapsed=$(( first > 0 ? now - first : 0 ))

    if (( idle_age >= DEBOUNCE_MS )); then break; fi
    if (( first > 0 && elapsed >= MAX_WAIT_MS )); then break; fi
  done

  lock_acquire "$lock_dir" || exit 0
  pending="$(read_int_file "$pending_file" 0)"
  printf '0\n' >"$pending_file"
  printf '0\n' >"$first_file"
  lock_release "$lock_dir"

  if [[ "$pending" == "0" ]]; then
    idle_loops=$((idle_loops + 1))
    (( idle_loops >= 6 )) && exit 0
    sleep 0.05
    continue
  fi
  idle_loops=0

  monitor_info="$(
    TARGET_CONN="$conn" get_focused_monitor_tsv || true
  )"
  hypr_make="" hypr_model="" hypr_serial="" hypr_desc=""

  if [[ -n "${monitor_info:-}" ]]; then
    IFS=$'\t' read -r _conn hypr_make hypr_model hypr_serial hypr_desc <<<"$monitor_info"
  fi

  controller="$(controller_for_conn "$conn" "$hypr_make" "$hypr_model" "$hypr_serial" "$hypr_desc" || true)"
  IFS=$'\t' read -r backend controller_id <<<"$controller"
  if [[ -z "${backend:-}" || -z "${controller_id:-}" ]]; then
    notify "$NOTIFY_MS" "Brightness $conn" "controller unavailable" "hypr-ddc-$conn"
    continue
  fi

  cur="" max="" ts=""
  if st="$(read_state "$conn" 2>/dev/null || true)"; then
    read -r cur max ts <<<"$st"
  fi

  now="$(now_ms)"
  need_sync=1
  if [[ -n "${cur:-}" && -n "${max:-}" && "$cur" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ && "$max" -gt 0 && "$ts" =~ ^[0-9]+$ ]]; then
    age=$((now - ts))
    (( age <= STATE_TTL_MS )) && need_sync=0
  fi

  if (( need_sync == 1 )); then
    if ! read -r cur max < <(brightness_get_curmax "$backend" "$controller_id"); then
      notify "$NOTIFY_MS" "Brightness $conn" "read failed" "hypr-ddc-$conn"
      continue
    fi
    write_state "$conn" "$cur" "$max"
  fi

  target=$((cur + pending))
  (( target < 0 )) && target=0
  (( target > max )) && target="$max"

  if ! brightness_set_abs_fast "$backend" "$controller_id" "$target"; then
    notify "$NOTIFY_MS" "Brightness $conn" "write failed" "hypr-ddc-$conn"
    continue
  fi

  write_state "$conn" "$target" "$max"
  notify_level "$conn" "$target" "$max"
done
