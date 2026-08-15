#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
USB_HELPER="${ROOT}/config/hypr/scripts/usb_refresh_fixer.sh"
INSTALLER="${ROOT}/awtarchy-install.sh"
LAUNCHER="${ROOT}/local/bin/awtarchy"
READY_SOUND="${ROOT}/config/hypr/scripts/quickshell_ready_sound.sh"
TMPD="$(mktemp -d)"
cleanup() {
  sudo rm -rf -- "$TMPD" 2>/dev/null || rm -rf -- "$TMPD"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" \
    || fail "${file#"${ROOT}/"} is missing required USB security behavior: ${needle}"
}

assert_not_contains() {
  local file="$1" needle="$2"
  ! grep -Fq -- "$needle" "$file" \
    || fail "${file#"${ROOT}/"} still contains unsafe USB behavior: ${needle}"
}

bash -n "$USB_HELPER"
bash -n "$INSTALLER"
bash -n "$LAUNCHER"
bash -n "$READY_SOUND"

[[ $(head -n1 "$USB_HELPER") == '#!/usr/bin/bash' ]] \
  || fail 'passwordless USB helper does not use a fixed root-owned Bash interpreter'

# The managed Hyprland script remains the user-facing command, but elevation
# must terminate at a fixed root-owned executable rather than this user-owned
# config file.
assert_contains "$USB_HELPER" 'PRIVILEGED_HELPER="/usr/local/libexec/awtarchy/usb-refresh-fixer"'
assert_contains "$USB_HELPER" 'validate_mapping_name()'
assert_contains "$INSTALLER" 'install_usb_refresh_helper()'
assert_not_contains "$LAUNCHER" 'install_usb_refresh_helper()'
assert_not_contains "$USB_HELPER" 'install_self_sudoers'
assert_not_contains "$USB_HELPER" 'SUDOERS_FILE='

# An empty wrapper invocation must become the explicitly authorized
# refresh-all form before sudo is entered. Mapping is a one-time privileged
# setup operation and must not share the passwordless refresh grant.
normalized_args="${TMPD}/normalized-args"
(
  # shellcheck source=/dev/null
  source "$USB_HELPER"
  # shellcheck disable=SC2317
  enter_privileged_helper() {
    printf '%s\n' "$@" >"$normalized_args"
  }
  # shellcheck disable=SC2317
  run_with_refresh_lock() { :; }
  main
)
[[ $(<"$normalized_args") == refresh-all ]] \
  || fail 'empty USB refresh invocation was not normalized to refresh-all before sudo'

# Config files are root-owned data, never shell programs. Mapping names must be
# validated before they can be joined to /etc/usb_refresh_fixer.
# shellcheck disable=SC2016
assert_not_contains "$USB_HELPER" 'source "$cfg"'

# The active marker is consumed by quickshell_ready_sound.sh. Keep that
# behavior, but store it below root-owned /run instead of a predictable /tmp
# pathname that could be replaced with a symbolic link.
assert_not_contains "$USB_HELPER" '/tmp/usb_refresh_fixer'
assert_contains "$USB_HELPER" 'RUNTIME_DIR="/run/awtarchy/usb-refresh"'
# shellcheck disable=SC2016
assert_contains "$READY_SOUND" '/run/awtarchy/usb-refresh/$(id -u).active'

# Source a temporary copy so the parser and validator can be exercised without
# touching the host's /etc or /sys. Sourcing must not execute the command.
mkdir -p -- "${TMPD}/configs"
sed "s|^CONFIG_DIR=.*|CONFIG_DIR=\"${TMPD}/configs\"|" \
  "$USB_HELPER" >"${TMPD}/usb-refresh-fixer"

cat >"${TMPD}/configs/dac.conf" <<'EOF_SAFE'
EXPECTED_ID=20b1:3008
USB_PORT_PATH=5-2
HOST_CONTROLLER_BDF=0000:0c:00.3
RESET_DELAY_SECONDS=2
EOF_SAFE

# A normal test fixture is intentionally not root-owned. Confirm the real
# helper rejects it before mocking root ownership for parser-only checks.
if (
  # shellcheck source=/dev/null
  source "${TMPD}/usb-refresh-fixer"
  load_config dac
); then
  fail 'USB mapping accepted a non-root-owned config'
fi

(
  # shellcheck source=/dev/null
  source "${TMPD}/usb-refresh-fixer"
  # shellcheck disable=SC2317,SC2329
  stat() {
    if [[ ${1:-} == -c && ${2:-} == %u ]]; then
      printf '0\n'
    else
      command stat "$@"
    fi
  }
  validate_mapping_name dac
  load_config dac
  [[ $EXPECTED_ID == 20b1:3008 ]] || exit 21
  [[ $USB_PORT_PATH == 5-2 ]] || exit 22
  [[ $HOST_CONTROLLER_BDF == 0000:0c:00.3 ]] || exit 23
  [[ $RESET_DELAY_SECONDS == 2 ]] || exit 24
) || fail 'safe USB mapping data did not parse'

cat >"${TMPD}/configs/injected.conf" <<EOF_INJECTED
EXPECTED_ID=20b1:3008
USB_PORT_PATH=5-2
HOST_CONTROLLER_BDF=0000:0c:00.3
RESET_DELAY_SECONDS=2
PAYLOAD=\$(touch "${TMPD}/config-payload-ran")
EOF_INJECTED

if (
  # shellcheck source=/dev/null
  source "${TMPD}/usb-refresh-fixer"
  # shellcheck disable=SC2317,SC2329
  stat() {
    if [[ ${1:-} == -c && ${2:-} == %u ]]; then
      printf '0\n'
    else
      command stat "$@"
    fi
  }
  load_config injected
); then
  fail 'USB mapping accepted an unexpected shell assignment'
fi
[[ ! -e "${TMPD}/config-payload-ran" ]] \
  || fail 'USB mapping data executed as shell code'

if (
  # shellcheck source=/dev/null
  source "${TMPD}/usb-refresh-fixer"
  validate_mapping_name ../outside
); then
  fail 'USB mapping name allowed directory traversal'
fi

# Exercise the one-time installer migration in an isolated system root. It
# must replace the removed legacy rule with a fixed, root-owned helper policy
# while leaving the user-facing command path unchanged.
installer_home="${TMPD}/installer-home"
system_root="${TMPD}/system-root"
fakebin="${TMPD}/fakebin"
mkdir -p \
  "$installer_home/.local/bin" \
  "$installer_home/.local/share/awtarchy" \
  "$system_root/etc/sudoers.d" \
  "$fakebin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$installer_home/.local/bin/awtarchy"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' \
  >"$installer_home/.local/share/awtarchy/awtarchy-runtime.sh"
chmod 0755 \
  "$installer_home/.local/bin/awtarchy" \
  "$installer_home/.local/share/awtarchy/awtarchy-runtime.sh"
printf '%s\n' \
  'awtarchytest ALL=(root) NOPASSWD: /home/awtarchytest/.config/hypr/scripts/usb_refresh_fixer.sh' \
  >"$system_root/etc/sudoers.d/usb_refresh_fixer-awtarchytest"

cat >"$fakebin/getent" <<EOF_GETENT
#!/usr/bin/env bash
set -euo pipefail
if [[ \${1:-} == passwd && \${2:-} == awtarchytest ]]; then
  printf '%s:x:1000:1000:Awtarchy test:%s:/bin/bash\n' awtarchytest '$installer_home'
  exit 0
fi
exec /usr/bin/getent "\$@"
EOF_GETENT
cat >"$fakebin/git" <<'EOF_GIT'
#!/usr/bin/env bash
set -euo pipefail
if (( $# >= 3 )) && [[ $1 == -C ]]; then
  case "${3} ${4:-}" in
    'rev-parse --is-inside-work-tree') printf 'true\n'; exit 0 ;;
    'branch --show-current') printf 'quickshell-conversion-testing\n'; exit 0 ;;
    'rev-parse HEAD') printf 'f9ea79016eb94a2c971c253504f9a6bb13841695\n'; exit 0 ;;
  esac
fi
exec /usr/bin/git "$@"
EOF_GIT
cat >"$fakebin/runuser" <<'EOF_RUNUSER'
#!/usr/bin/env bash
set -euo pipefail
while (( $# )); do
  if [[ $1 == -- ]]; then
    shift
    exec "$@"
  fi
  shift
done
exit 2
EOF_RUNUSER
cat >"$fakebin/visudo" <<'EOF_VISUDO'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == -cf && -f ${2:-} ]]
grep -Fq '/usr/local/libexec/awtarchy/usb-refresh-fixer refresh *' "$2"
grep -Fq '/usr/local/libexec/awtarchy/usb-refresh-fixer refresh-audio *' "$2"
grep -Fq '/usr/local/libexec/awtarchy/usb-refresh-fixer refresh-audio-default *' "$2"
grep -Fq '/usr/local/libexec/awtarchy/usb-refresh-fixer audio-default *' "$2"
grep -Fq '/usr/local/libexec/awtarchy/usb-refresh-fixer refresh-all' "$2"
! grep -Fq '/usr/local/libexec/awtarchy/usb-refresh-fixer map' "$2"
! grep -Fxq 'awtarchytest ALL=(root) NOPASSWD: /usr/local/libexec/awtarchy/usb-refresh-fixer' "$2"
EOF_VISUDO
cat >"$fakebin/chown" <<'EOF_CHOWN'
#!/usr/bin/env bash
# The fixture's synthetic user has no host passwd entry. User-home writes are
# already exercised through the runuser shim; retain real root ownership here.
exit 0
EOF_CHOWN
chmod 0755 "$fakebin/getent" "$fakebin/git" "$fakebin/runuser" "$fakebin/visudo" "$fakebin/chown"

# Redirect intentionally remains owned by the invoking test user.
# shellcheck disable=SC2024
sudo env \
  "PATH=$fakebin:$PATH" \
  "HOME=$installer_home" \
  USER=root \
  SUDO_USER=awtarchytest \
  "AWTARCHY_TEST_SYSTEM_ROOT=$system_root" \
  "AWTARCHY_SYSTEM_BIN_DIR=$system_root/usr/local/bin" \
  bash "$INSTALLER" >"${TMPD}/installer.out"

installed_helper="$system_root/usr/local/libexec/awtarchy/usb-refresh-fixer"
installed_wireguard="$system_root/usr/local/libexec/awtarchy/wireguard-helper"
installed_scxctl="$system_root/usr/local/libexec/awtarchy/scxctl-helper"
installed_rule="$system_root/etc/sudoers.d/awtarchy-usb-refresh-awtarchytest"
[[ -x $installed_helper ]] || fail 'installer did not create the privileged USB helper'
[[ -x $installed_wireguard ]] || fail 'installer did not create the privileged WireGuard helper'
[[ -x $installed_scxctl ]] || fail 'installer did not create the privileged scxctl helper'
cmp -s "$USB_HELPER" "$installed_helper" \
  || fail 'installer privileged USB helper differs from its reviewed source'
[[ $(stat -c '%U:%G:%a' "$installed_helper") == root:root:755 ]] \
  || fail 'privileged USB helper ownership or mode is unsafe'
[[ $(stat -c '%U:%G:%a' "$installed_scxctl") == root:root:755 ]] \
  || fail 'privileged scxctl helper ownership or mode is unsafe'
[[ $(stat -c '%U:%G:%a' "$installed_rule") == root:root:440 ]] \
  || fail 'USB sudoers policy ownership or mode is unsafe'
for allowed in \
  'usb-refresh-fixer refresh *' \
  'usb-refresh-fixer refresh-audio *' \
  'usb-refresh-fixer refresh-audio-default *' \
  'usb-refresh-fixer audio-default *' \
  'usb-refresh-fixer refresh-all'; do
  sudo grep -Fq -- "$allowed" "$installed_rule" \
    || fail "USB sudoers policy is missing allowed operation: $allowed"
done
! sudo grep -Fq -- 'usb-refresh-fixer map' "$installed_rule" \
  || fail 'USB mapping is incorrectly authorized without a password'
! sudo grep -Fxq \
  'awtarchytest ALL=(root) NOPASSWD: /usr/local/libexec/awtarchy/usb-refresh-fixer' \
  "$installed_rule" \
  || fail 'USB sudoers policy still authorizes every helper operation'
[[ ! -e $system_root/etc/sudoers.d/usb_refresh_fixer-awtarchytest ]] \
  || fail 'installer did not remove the legacy user-script sudoers policy'

printf 'PASS: USB refresh privilege and config security regressions\n'
