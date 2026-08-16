#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

function_body() {
  local name="$1"
  awk -v signature="${name}() {" '
    $0 == signature { active=1; depth=0 }
    active {
      print
      opens=gsub(/\{/, "{")
      closes=gsub(/\}/, "}")
      depth += opens - closes
      if (depth == 0) exit
    }
  ' "$RUNTIME"
}

root_body="$(function_body run_update_root)"
install_body="$(function_body install_managed_pacman_packages)"
record_body="$(function_body record_managed_packages)"
remove_body="$(function_body remove_managed_packages_matching)"
ensure_body="$(function_body ensure_current_hardware_packages)"
exact_nvidia_body="$(function_body remove_exact_nvidia_files)"
boot_nvidia_body="$(function_body remove_nvidia_boot_entries)"
hardware_body="$(function_body hardware_reconcile)"

[[ -n "$root_body" ]] || fail 'run_update_root is missing'
[[ "$root_body" == *'sudo -- "$@"'* ]] \
  || fail 'update root helper does not narrowly elevate the requested command'

[[ "$ensure_body" != *'Hardware package reconciliation requires sudo/root.'* ]] \
  || fail 'hardware reconciliation still exits early for the normal-user updater'
[[ "$install_body" != *'installation requires sudo/root.'* ]] \
  || fail 'managed package installation still exits early for the normal-user updater'
[[ "$remove_body" != *'cleanup requires sudo/root'* ]] \
  || fail 'managed package cleanup still exits early for the normal-user updater'
[[ "$record_body" != *'[[ "${EUID}" -eq 0 ]] || return 0'* ]] \
  || fail 'Awtarchy package ledger recording still silently skips normal-user updates'

[[ "$install_body" == *'run_update_root /usr/bin/pacman -S --needed --noconfirm'* ]] \
  || fail 'missing hardware packages are not installed through narrow sudo elevation'
[[ "$remove_body" == *'run_update_root /usr/bin/pacman -Rns --noconfirm'* ]] \
  || fail 'obsolete Awtarchy-owned hardware packages are not removed through narrow sudo elevation'
[[ "$record_body" == *'run_update_root /usr/bin/install -m 0644'* ]] \
  || fail 'hardware package ownership ledger is not written through narrow sudo elevation'

[[ "$ensure_body" == *'run_update_root /usr/bin/systemctl enable --now tlp.service'* ]] \
  || fail 'new TLP installs are not enabled through narrow sudo elevation'
[[ "$ensure_body" == *'run_update_root /usr/bin/systemctl enable --now thermald.service'* ]] \
  || fail 'new thermald installs are not enabled through narrow sudo elevation'
[[ "$hardware_body" == *'run_update_root /usr/bin/systemctl disable --now thermald.service'* ]] \
  || fail 'obsolete thermald service cleanup is not elevated safely'
[[ "$hardware_body" == *'run_update_root /usr/bin/systemctl disable --now tlp.service'* ]] \
  || fail 'obsolete TLP service cleanup is not elevated safely'

[[ "$exact_nvidia_body" != *'[[ "${EUID}" -eq 0 ]] || return 0'* ]] \
  || fail 'exact NVIDIA system-file cleanup still silently skips normal-user updates'
[[ "$exact_nvidia_body" == *'run_update_root /usr/bin/rm -f -- "$file"'* ]] \
  || fail 'exact NVIDIA system-file cleanup is not narrowly elevated'
[[ "$boot_nvidia_body" != *'[[ "${EUID}" -eq 0 ]] || return 0'* ]] \
  || fail 'NVIDIA boot cleanup still silently skips normal-user updates'
[[ "$boot_nvidia_body" == *'run_update_root /usr/bin/install'* ]] \
  || fail 'NVIDIA boot-file updates are not narrowly elevated'

printf '%s\n' 'PASS: updater hardware reconciliation keeps user config unprivileged and elevates only system operations.'
