#!/usr/bin/env bash
# Hardware temperature helper for the Awtarchy Quickshell bar.

set -u
export LC_ALL=C

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CPU_TEMP_SCRIPT="$CONFIG_HOME/hypr/scripts/cpu_temp.sh"

trim() {
  sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//'
}

sanitize() {
  tr -d '\0\r\n\t' | trim
}

read_temp_c() {
  local file="$1" raw
  [[ -r "$file" ]] || return 1
  raw="$(<"$file")"
  [[ "$raw" =~ ^-?[0-9]+$ ]] || return 1

  if (( raw > 1000 || raw < -1000 )); then
    raw=$((raw / 1000))
  fi

  (( raw >= -20 && raw <= 150 )) || return 1
  printf '%d\n' "$raw"
}

sensor_label() {
  local input="$1" label_file label
  label_file="${input/_input/_label}"
  if [[ -r "$label_file" ]]; then
    label="$(sanitize < "$label_file")"
    [[ -n "$label" ]] && { printf '%s\n' "$label"; return 0; }
  fi
  basename "${input%_input}"
}

hwmon_model() {
  local d="$1" f value
  for f in "$d/device/model" "$d/device/device/model" "$d/device/name"; do
    [[ -r "$f" ]] || continue
    value="$(sanitize < "$f")"
    [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
  done
  return 1
}

friendly_chip_name() {
  case "$1" in
    acpitz) printf 'ACPI\n' ;;
    pch_*) printf 'Chipset\n' ;;
    nct*|it87|it86*|w83627*) printf 'Motherboard\n' ;;
    thinkpad) printf 'ThinkPad\n' ;;
    dell_smm) printf 'Dell system\n' ;;
    asus*|asus_wmi_sensors) printf 'ASUS system\n' ;;
    iwlwifi) printf 'Wi-Fi\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

emit_cpu() {
  local value='N/A'
  if [[ -x "$CPU_TEMP_SCRIPT" ]]; then
    value="$($CPU_TEMP_SCRIPT 2>/dev/null || true)"
    [[ -n "$value" ]] || value='N/A'
  fi
  printf 'CPU_TEMP %s\n' "$value"
}

emit_gpu() {
  local d name input c best=''
  shopt -s nullglob

  for d in /sys/class/hwmon/*; do
    [[ -r "$d/name" ]] || continue
    name="$(sanitize < "$d/name")"
    case "$name" in
      amdgpu|nouveau|nvidia)
        for input in "$d"/temp*_input; do
          c="$(read_temp_c "$input" 2>/dev/null || true)"
          [[ -n "$c" ]] || continue
          if [[ -z "$best" ]] || (( c > best )); then
            best="$c"
          fi
        done
        ;;
    esac
  done

  if [[ -n "$best" ]]; then
    printf 'GPU_TEMP %s°\n' "$best"
  else
    printf 'GPU_TEMP N/A\n'
  fi
}

emit_drives() {
  local d name input c model label chosen chosen_c
  shopt -s nullglob

  for d in /sys/class/hwmon/*; do
    [[ -r "$d/name" ]] || continue
    name="$(sanitize < "$d/name")"
    case "$name" in
      nvme|drivetemp) ;;
      *) continue ;;
    esac

    chosen=''
    chosen_c=''

    if [[ "$name" == 'nvme' ]]; then
      for input in "$d"/temp*_input; do
        label="$(sensor_label "$input")"
        [[ "$label" == 'Composite' ]] || continue
        c="$(read_temp_c "$input" 2>/dev/null || true)"
        [[ -n "$c" ]] || continue
        chosen="$input"
        chosen_c="$c"
        break
      done
    fi

    if [[ -z "$chosen" ]]; then
      for input in "$d"/temp*_input; do
        c="$(read_temp_c "$input" 2>/dev/null || true)"
        [[ -n "$c" ]] || continue
        chosen="$input"
        chosen_c="$c"
        break
      done
    fi

    [[ -n "$chosen_c" ]] || continue
    model="$(hwmon_model "$d" 2>/dev/null || true)"
    if [[ -z "$model" ]]; then
      [[ "$name" == 'nvme' ]] && model='NVMe drive' || model='Drive'
    fi

    printf 'TEMP\tDrive\t%s\t%s°\n' "$model" "$chosen_c"
  done
}

emit_other_hwmon() {
  local d name input c label chip key count=0
  local max_sensors=8
  declare -A seen=()
  shopt -s nullglob

  for d in /sys/class/hwmon/*; do
    [[ -r "$d/name" ]] || continue
    name="$(sanitize < "$d/name")"

    case "$name" in
      k10temp|coretemp|zenpower|cpu_thermal|x86_pkg_temp|amdgpu|nouveau|nvidia|nvme|drivetemp)
        continue
        ;;
    esac

    chip="$(friendly_chip_name "$name")"

    for input in "$d"/temp*_input; do
      c="$(read_temp_c "$input" 2>/dev/null || true)"
      [[ -n "$c" ]] || continue
      (( c > 0 )) || continue

      label="$(sensor_label "$input")"
      if [[ "$label" == temp[0-9]* ]]; then
        label=''
      fi

      if [[ -n "$label" ]]; then
        key="$chip $label"
      else
        key="$chip"
      fi

      [[ -z "${seen[$key]:-}" ]] || continue
      seen[$key]=1

      printf 'TEMP\tOther\t%s\t%s°\n' "$key" "$c"
      count=$((count + 1))
      (( count < max_sensors )) || return 0
    done
  done
}

main() {
  emit_cpu
  emit_gpu
  emit_drives
  emit_other_hwmon
}

main
