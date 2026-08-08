#!/usr/bin/env bash
# Memory slot topology helper for the Awtarchy Quickshell bar.
# Uses unprivileged kernel interfaces first and never prompts for root.

set -euo pipefail
export LC_ALL=C

print_result() {
  local populated="$1" total="$2" empty="$3" source="$4"
  printf 'MEMORY_SLOTS\t%s\t%s\t%s\t%s\n' "$populated" "$total" "$empty" "$source"
}

from_dmidecode() {
  command -v dmidecode >/dev/null 2>&1 || return 1

  local data
  data="$(dmidecode -t 17 2>/dev/null)" || return 1
  [[ -n "$data" ]] || return 1

  local total populated
  total="$(awk '/^[[:space:]]*Memory Device$/ { count++ } END { print count+0 }' <<<"$data")"
  populated="$(awk '
    /^[[:space:]]*Memory Device$/ { in_device=1; size=""; next }
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
  return 0
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

  # A zero-sized EDAC DIMM object proves the kernel is exposing empty slots,
  # so total/empty counts are trustworthy. If every exposed object is
  # populated, EDAC may be hiding empty physical slots; report only the
  # populated count rather than falsely claiming there are no empty slots.
  if (( zero_slots > 0 )); then
    print_result "$populated" "$total" "$zero_slots" "EDAC"
  else
    print_result "$populated" "?" "?" "EDAC"
  fi
  return 0
}

main() {
  from_dmidecode && return 0
  from_edac && return 0
  print_result "?" "?" "?" "unavailable"
}

main
