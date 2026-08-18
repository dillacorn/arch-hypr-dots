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
atomic_body="$(function_body atomic_update_root_file_from_stdin)"
install_body="$(function_body install_managed_pacman_packages)"
record_body="$(function_body record_managed_packages)"
remove_body="$(function_body remove_managed_packages_matching)"
ensure_body="$(function_body ensure_current_hardware_packages)"
nvidia_stack_body="$(function_body nvidia_stack_installed)"
exact_nvidia_body="$(function_body remove_exact_nvidia_files)"
boot_nvidia_body="$(function_body remove_nvidia_boot_entries)"
hardware_body="$(function_body hardware_reconcile)"

[[ -n "$root_body" ]] || fail 'run_update_root is missing'
[[ "$root_body" == *'sudo -- "$@"'* ]] \
  || fail 'update root helper does not narrowly elevate the requested command'

[[ -n "$atomic_body" ]] || fail 'atomic privileged root-write helper is missing'
[[ "$atomic_body" == *'/usr/bin/mktemp'* ]] \
  || fail 'privileged file writes do not stage in a root-created temporary file'
[[ "$atomic_body" == *'/usr/bin/tee'* ]] \
  || fail 'root staging does not consume transformed content through stdin'
[[ "$atomic_body" == *'/usr/bin/mv -Tf'* ]] \
  || fail 'root staging is not atomically activated'
[[ "$atomic_body" == *'test ! -L'* ]] \
  || fail 'root staging does not reject symbolic-link paths'

[[ "$ensure_body" != *'Hardware package reconciliation requires sudo/root.'* ]] \
  || fail 'hardware reconciliation still exits early for the normal-user updater'
[[ "$install_body" != *'installation requires sudo/root.'* ]] \
  || fail 'managed package installation still exits early for the normal-user updater'
[[ "$remove_body" != *'cleanup requires sudo/root'* ]] \
  || fail 'managed package cleanup still exits early for the normal-user updater'
# shellcheck disable=SC2016 # This test intentionally matches literal shell source.
[[ "$record_body" != *'[[ "${EUID}" -eq 0 ]] || return 0'* ]] \
  || fail 'Awtarchy package ledger recording still silently skips normal-user updates'

[[ "$install_body" == *'run_update_root /usr/bin/pacman -S --needed --noconfirm'* ]] \
  || fail 'missing hardware packages are not installed through narrow sudo elevation'
[[ "$remove_body" == *'run_update_root /usr/bin/pacman -Rns --noconfirm'* ]] \
  || fail 'obsolete Awtarchy-owned hardware packages are not removed through narrow sudo elevation'
# shellcheck disable=SC2016 # This test intentionally matches literal shell source.
[[ "$record_body" == *'atomic_update_root_file_from_stdin 0644 0 0 "$manifest"'* ]] \
  || fail 'hardware package ownership ledger is not written through root-owned staging'
# shellcheck disable=SC2016 # This test intentionally matches literal shell source.
[[ "$remove_body" == *'atomic_update_root_file_from_stdin 0644 0 0 "$manifest"'* ]] \
  || fail 'hardware package ledger cleanup is not written through root-owned staging'

[[ -n "$nvidia_stack_body" ]] || fail 'nvidia_stack_installed is missing'
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
cat >"${tmp_dir}/pacman" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-Qq" ]]; then
  printf '%s\n' nvidia-open-dkms
  exec yes pkg
fi
exit 1
EOF
chmod 0755 "${tmp_dir}/pacman"
{
  printf '%s\n' 'set -o pipefail'
  printf '%s\n' "$nvidia_stack_body"
  printf '%s\n' 'nvidia_stack_installed'
} >"${tmp_dir}/test-nvidia-stack.sh"
if ! PATH="${tmp_dir}:$PATH" bash "${tmp_dir}/test-nvidia-stack.sh"; then
  fail 'NVIDIA stack detection fails when a recognized package is followed by additional pacman output under pipefail'
fi

[[ "$ensure_body" == *'run_update_root /usr/bin/systemctl enable --now tlp.service'* ]] \
  || fail 'new TLP installs are not enabled through narrow sudo elevation'
[[ "$ensure_body" == *'run_update_root /usr/bin/systemctl enable --now thermald.service'* ]] \
  || fail 'new thermald installs are not enabled through narrow sudo elevation'
[[ "$hardware_body" == *'run_update_root /usr/bin/systemctl disable --now thermald.service'* ]] \
  || fail 'obsolete thermald service cleanup is not elevated safely'
[[ "$hardware_body" == *'run_update_root /usr/bin/systemctl disable --now tlp.service'* ]] \
  || fail 'obsolete TLP service cleanup is not elevated safely'

# shellcheck disable=SC2016 # This test intentionally matches literal shell source.
[[ "$exact_nvidia_body" != *'[[ "${EUID}" -eq 0 ]] || return 0'* ]] \
  || fail 'exact NVIDIA system-file cleanup still silently skips normal-user updates'
# shellcheck disable=SC2016 # This test intentionally matches literal shell source.
[[ "$exact_nvidia_body" == *'run_update_root /usr/bin/rm -f -- "$file"'* ]] \
  || fail 'exact NVIDIA system-file cleanup is not narrowly elevated'
# shellcheck disable=SC2016 # This test intentionally matches literal shell source.
[[ "$boot_nvidia_body" != *'[[ "${EUID}" -eq 0 ]] || return 0'* ]] \
  || fail 'NVIDIA boot cleanup still silently skips normal-user updates'
# shellcheck disable=SC2016 # This test intentionally matches literal shell source.
[[ "$boot_nvidia_body" == *'atomic_update_root_file_from_stdin "$mode" "$uid" "$gid" "$file"'* ]] \
  || fail 'NVIDIA boot-file updates do not use root-owned staging'
# shellcheck disable=SC2016 # This test intentionally matches literal shell source.
[[ "$boot_nvidia_body" == *'atomic_update_root_file_from_stdin "$mode" "$uid" "$gid" /etc/mkinitcpio.conf'* ]] \
  || fail 'mkinitcpio updates do not use root-owned staging'
# shellcheck disable=SC2016 # This test intentionally matches literal shell source.
[[ "$boot_nvidia_body" != *'run_update_root /usr/bin/install -m "$mode" "$tmp"'* ]] \
  || fail 'privileged NVIDIA cleanup still reads user-owned temporary files directly'

printf '%s\n' 'PASS: updater hardware reconciliation uses narrow sudo elevation and root-owned staging for privileged writes.'
