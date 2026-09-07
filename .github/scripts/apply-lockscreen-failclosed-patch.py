#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "local/share/awtarchy/awtarchy-runtime.sh"

old = r'''runtime_catalog_has_exact_package() {
  local runtime_source="$1" package="$2"
  awk -v package="$package" '
    /^declare -a PKG_GROUPS=\(/ {
      in_groups=1
      next
    }
    in_groups && /^[[:space:]]*\)[[:space:]]*$/ { exit }
    in_groups {
      line=$0
      sub(/^[[:space:]]*"/, "", line)
      sub(/"[[:space:]]*$/, "", line)
      sub(/^[^:]*:/, "", line)
      count=split(line, fields, /[[:space:]]+/)
      for (i=1; i<=count; i++) {
        if (fields[i] == package)
          found=1
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$runtime_source"
}

lockscreen_target_retires_hyprlock() {
  local repo_dir="$1"
  local runtime_source="${repo_dir}/local/share/awtarchy/awtarchy-runtime.sh"
  local config_root="${repo_dir}/config"

  [[ -f "${repo_dir}/config/quickshell/awtarchy-lock/shell.qml" \
    && ! -L "${repo_dir}/config/quickshell/awtarchy-lock/shell.qml" ]] || return 1
  [[ -f "${repo_dir}/config/hypr/scripts/awtarchy_lock.sh" \
    && ! -L "${repo_dir}/config/hypr/scripts/awtarchy_lock.sh" ]] || return 1
  [[ ! -e "${repo_dir}/config/hypr/hyprlock.conf" \
    && ! -L "${repo_dir}/config/hypr/hyprlock.conf" ]] || return 1
  [[ -r "$runtime_source" && ! -L "$runtime_source" ]] || return 1
  [[ -d "$config_root" && ! -L "$config_root" ]] || return 1

  runtime_catalog_has_exact_package "$runtime_source" hyprlock && return 1
  if grep -R -I -w -q -- hyprlock "$config_root"; then
    return 1
  fi
  return 0
}
'''

new = r'''runtime_catalog_has_exact_package() {
  local runtime_source="$1" package="$2"
  awk -v package="$package" '
    /^declare -a PKG_GROUPS=\(/ {
      if (seen)
        invalid=1
      seen=1
      in_groups=1
      next
    }
    in_groups && /^[[:space:]]*\)[[:space:]]*$/ {
      closed=1
      in_groups=0
      next
    }
    in_groups {
      line=$0
      sub(/^[[:space:]]*"/, "", line)
      sub(/"[[:space:]]*$/, "", line)
      sub(/^[^:]*:/, "", line)
      count=split(line, fields, /[[:space:]]+/)
      for (i=1; i<=count; i++) {
        if (fields[i] == package)
          found=1
      }
    }
    END {
      if (!seen || !closed || in_groups || invalid)
        exit 2
      exit(found ? 0 : 1)
    }
  ' "$runtime_source"
}

lockscreen_target_retires_hyprlock() {
  local repo_dir="$1"
  local runtime_source="${repo_dir}/local/share/awtarchy/awtarchy-runtime.sh"
  local config_root="${repo_dir}/config"
  local catalog_rc scan_rc

  [[ -f "${repo_dir}/config/quickshell/awtarchy-lock/shell.qml" \
    && ! -L "${repo_dir}/config/quickshell/awtarchy-lock/shell.qml" ]] || return 1
  [[ -f "${repo_dir}/config/hypr/scripts/awtarchy_lock.sh" \
    && ! -L "${repo_dir}/config/hypr/scripts/awtarchy_lock.sh" ]] || return 1
  [[ ! -e "${repo_dir}/config/hypr/hyprlock.conf" \
    && ! -L "${repo_dir}/config/hypr/hyprlock.conf" ]] || return 1
  [[ -r "$runtime_source" && ! -L "$runtime_source" ]] || return 1
  [[ -d "$config_root" && ! -L "$config_root" ]] || return 1

  if runtime_catalog_has_exact_package "$runtime_source" hyprlock; then
    return 1
  else
    catalog_rc=$?
    [[ $catalog_rc -eq 1 ]] || return 1
  fi

  if grep -R -I -w -q -- hyprlock "$config_root"; then
    return 1
  else
    scan_rc=$?
    [[ $scan_rc -eq 1 ]] || return 1
  fi
  return 0
}
'''

text = RUNTIME.read_text(encoding="utf-8")
count = text.count(old)
if count != 1:
    raise SystemExit(f"expected exactly one lockscreen gate block, found {count}")
RUNTIME.write_text(text.replace(old, new, 1), encoding="utf-8")
