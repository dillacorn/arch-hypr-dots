#!/usr/bin/env bash
# Memory slot topology helper for the Awtarchy Quickshell bar.
# Normal reads never prompt for root. Exact SMBIOS topology can be cached once
# with: sudo memory_topology.sh --refresh

set -euo pipefail
export LC_ALL=C

CACHE_DIR="${HOME}/.cache/awtarchy"
CACHE_FILE="${CACHE_DIR}/memory-topology.tsv"

print_result() {
  local populated="$1" total="$2" empty="$3" source="$4"
  printf 'MEMORY_SLOTS\t%s\t%s\t%s\t%s\n' "$populated" "$total" "$empty" "$source"
}

cache_target_for_root() {
  local user home
  user="${SUDO_USER:-}"
  if [[ -n "$user" && "$user" != "root" ]]; then
    home="$(getent passwd "$user" | cut -d: -f6)"
    [[ -n "$home" ]] || return 1
    printf '%s/.cache/awtarchy/memory-topology.tsv\n' "$home"
  else
    printf '%s\n' "$CACHE_FILE"
  fi
}

parse_dmidecode() {
  local data="$1"
  local total populated

  total="$(awk '/^[[:space:]]*Memory Device$/ { count++ } END { print count+0 }' <<<"$data")"
  populated="$(awk '
    /^[[:space:]]*Memory Device$/ { in_device=1; next }
    in_device && /^[[:space:]]*Size:/ {
      line=$0
      sub(/^[[:space:]]*Size:[[:space:]]*/, "", line)
      if (line !~ /^No Module Installed$/ && line !~ /^Unknown$/ && line !~ /^0[[:space:]]/) populated++
      in_device=0
    }
    END { print populated+0 }
  ' <<<"$data")"

  (( total > 0 )) || return 1
  (( populated >= 0 && populated <= total )) || return 1
  print_result "$populated" "$total" "$((total - populated))" "SMBIOS"
}

from_dmidecode() {
  command -v dmidecode >/dev/null 2>&1 || return 1
  local data
  data="$(dmidecode -t 17 2>/dev/null)" || return 1
  [[ -n "$data" ]] || return 1
  parse_dmidecode "$data"
}

from_cache() {
  [[ -r "$CACHE_FILE" ]] || return 1
  local line
  line="$(head -n1 "$CACHE_FILE" 2>/dev/null || true)"
  [[ "$line" == MEMORY_SLOTS$'\t'* ]] || return 1
  printf '%s\n' "$line"
}

from_edac() {
  shopt -s nullglob
  local dirs=(/sys/devices/system/edac/mc/mc*/dimm*)
  (( ${#dirs[@]} > 0 )) || return 1

  local total=0 populated=0 zero_slots=0 d size
  for d in "${dirs[@]}"; do
    [[ -r "$d/size" ]] || continue
    size="$(<"$d/size")"
    [[ "$size" =~ ^[0-9]+$ ]] || continue
    ((total += 1))
    if (( size > 0 )); then
      ((populated += 1))
    else
      ((zero_slots += 1))
    fi
  done

  (( total > 0 )) || return 1

  if (( zero_slots > 0 )); then
    print_result "$populated" "$total" "$zero_slots" "EDAC"
  else
    print_result "$populated" "?" "?" "EDAC"
  fi
}

refresh_cache() {
  if (( EUID != 0 )); then
    printf 'memory_topology.sh --refresh requires sudo/root.\n' >&2
    exit 1
  fi

  command -v dmidecode >/dev/null 2>&1 || {
    printf 'dmidecode is required to cache physical DIMM topology.\n' >&2
    exit 1
  }

  local data result target target_dir owner
  data="$(dmidecode -t 17 2>/dev/null)" || {
    printf 'Could not read SMBIOS memory-device data.\n' >&2
    exit 1
  }
  result="$(parse_dmidecode "$data")" || {
    printf 'SMBIOS did not expose usable memory-device topology.\n' >&2
    exit 1
  }

  target="$(cache_target_for_root)"
  target_dir="$(dirname "$target")"
  install -d -m 0755 "$target_dir"
  printf '%s\n' "$result" > "$target"
  chmod 0644 "$target"

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    owner="${SUDO_USER}:$(id -gn "$SUDO_USER")"
    chown "$owner" "$target_dir" "$target"
  fi

  printf '%s\n' "$result"
}

main() {
  case "${1:-}" in
    --refresh)
      refresh_cache
      return
      ;;
    --clear-cache)
      rm -f -- "$CACHE_FILE"
      return
      ;;
  esac

  from_cache && return 0
  from_edac && return 0
  from_dmidecode && return 0
  print_result "?" "?" "?" "needs-SMBIOS-cache"
}

main "$@"
