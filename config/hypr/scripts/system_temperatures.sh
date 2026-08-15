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

hwmon_name() {
  local d="$1"
  [[ -r "$d/name" ]] || return 1
  sanitize < "$d/name"
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

pci_display_device() {
  local d="$1" p class
  p="$(readlink -f "$d/device" 2>/dev/null || true)"
  [[ -n "$p" ]] || return 1

  while [[ "$p" == /sys/* && "$p" != /sys ]]; do
    if [[ -r "$p/class" ]]; then
      class="$(sanitize < "$p/class")"
      case "$class" in
        0x03*) return 0 ;;
      esac
    fi
    p="$(dirname "$p")"
  done
  return 1
}

is_gpu_hwmon() {
  local d="$1" name="$2"
  case "$name" in
    amdgpu|radeon|nouveau|nvidia|i915|xe) return 0 ;;
  esac
  pci_display_device "$d"
}

is_cpu_hwmon() {
  case "$1" in
    k10temp|coretemp|zenpower|cpu_thermal|x86_pkg_temp) return 0 ;;
  esac
  return 1
}

is_drive_hwmon() {
  case "$1" in
    nvme|drivetemp) return 0 ;;
  esac
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

emit_primary_cpu() {
  local value='N/A'
  if [[ -x "$CPU_TEMP_SCRIPT" ]]; then
    value="$($CPU_TEMP_SCRIPT 2>/dev/null || true)"
    [[ -n "$value" ]] || value='N/A'
  fi
  printf 'CPU_TEMP %s\n' "$value"
}

emit_cpu_details() {
  local d name input c label chip count=0
  shopt -s nullglob

  for d in /sys/class/hwmon/*; do
    name="$(hwmon_name "$d" 2>/dev/null || true)"
    [[ -n "$name" ]] || continue
    is_cpu_hwmon "$name" || continue
    chip="$(friendly_chip_name "$name")"

    for input in "$d"/temp*_input; do
      c="$(read_temp_c "$input" 2>/dev/null || true)"
      [[ -n "$c" ]] || continue
      label="$(sensor_label "$input")"
      [[ "$label" == temp[0-9]* ]] && label="$chip"
      printf 'TEMP\tCPU\t%s\t%s°\n' "$label" "$c"
      count=$((count + 1))
      (( count < 8 )) || return 0
    done
  done
}

emit_gpu() {
  local d name input c label chip best='' count=0
  shopt -s nullglob

  for d in /sys/class/hwmon/*; do
    name="$(hwmon_name "$d" 2>/dev/null || true)"
    [[ -n "$name" ]] || continue
    is_gpu_hwmon "$d" "$name" || continue
    chip="$(friendly_chip_name "$name")"

    for input in "$d"/temp*_input; do
      c="$(read_temp_c "$input" 2>/dev/null || true)"
      [[ -n "$c" ]] || continue
      label="$(sensor_label "$input")"
      [[ "$label" == temp[0-9]* ]] && label="$chip"

      if [[ -z "$best" ]] || (( c > best )); then
        best="$c"
      fi

      if (( count < 6 )); then
        printf 'TEMP\tGPU\t%s\t%s°\n' "$label" "$c"
        count=$((count + 1))
      fi
    done
  done

  if [[ -z "$best" ]] && command -v nvidia-smi >/dev/null 2>&1; then
    while IFS= read -r c; do
      c="$(printf '%s' "$c" | sanitize)"
      [[ "$c" =~ ^-?[0-9]+$ ]] || continue
      (( c >= -20 && c <= 150 )) || continue
      if [[ -z "$best" ]] || (( c > best )); then
        best="$c"
      fi
    done < <(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null || true)
  fi

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
    name="$(hwmon_name "$d" 2>/dev/null || true)"
    [[ -n "$name" ]] || continue
    is_drive_hwmon "$name" || continue

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
  local max_sensors=12
  declare -A seen=()
  shopt -s nullglob

  for d in /sys/class/hwmon/*; do
    name="$(hwmon_name "$d" 2>/dev/null || true)"
    [[ -n "$name" ]] || continue

    is_cpu_hwmon "$name" && continue
    is_drive_hwmon "$name" && continue
    is_gpu_hwmon "$d" "$name" && continue

    chip="$(friendly_chip_name "$name")"

    for input in "$d"/temp*_input; do
      c="$(read_temp_c "$input" 2>/dev/null || true)"
      [[ -n "$c" ]] || continue
      (( c > 0 )) || continue

      label="$(sensor_label "$input")"
      [[ "$label" == temp[0-9]* ]] && label=''

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

debug_hwmon() {
  local d name p input c label class
  shopt -s nullglob

  for d in /sys/class/hwmon/*; do
    name="$(hwmon_name "$d" 2>/dev/null || true)"
    p="$(readlink -f "$d/device" 2>/dev/null || true)"
    class=''
    [[ -r "$d/device/class" ]] && class="$(sanitize < "$d/device/class")"
    printf 'HWMON\t%s\tname=%s\tclass=%s\tdevice=%s\n' "$(basename "$d")" "${name:-?}" "${class:-?}" "${p:-?}"
    for input in "$d"/temp*_input; do
      c="$(read_temp_c "$input" 2>/dev/null || true)"
      [[ -n "$c" ]] || continue
      label="$(sensor_label "$input")"
      printf '  TEMP\t%s\t%s°C\n' "$label" "$c"
    done
  done
}

main() {
  if [[ "${1:-}" == '--debug' ]]; then
    debug_hwmon
    return
  fi

  emit_primary_cpu
  emit_cpu_details
  emit_gpu
  emit_drives
  emit_other_hwmon
}

main "$@"
