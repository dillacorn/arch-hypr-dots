#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_absent() {
  local rel="$1"
  [[ ! -e "${REPO_ROOT}/${rel}" ]] || fail "temporary conversion artifact still ships: ${rel}"
}

assert_not_contains() {
  local file="$1" needle="$2"
  ! grep -Fq -- "$needle" "$file" || fail "${file#"${REPO_ROOT}/"} still contains temporary marker: ${needle}"
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "${file#"${REPO_ROOT}/"} is missing required production behavior: ${needle}"
}

for rel in \
  local/bin/awtarchy-quickshell \
  QUICKSHELL_CONVERSION.md \
  config/hypr/scripts/quickshell_flyout_state_collect.py \
  config/hypr/scripts/quickshell_flyout_handoff_test.py \
  config/hypr/scripts/quickshell_flyout_warp_guard_test.py \
  tests/test-awtarchy-quickshell-isolation.sh
do
  assert_absent "$rel"
done

INSTALLER="${REPO_ROOT}/awtarchy-install.sh"
WORKFLOW="${REPO_ROOT}/.github/workflows/validate-awtarchy.yml"
LAUNCHER="${REPO_ROOT}/local/bin/awtarchy"
WIREGUARD="${REPO_ROOT}/config/hypr/scripts/quickshell_wireguard.sh"
WIREGUARD_PRIVILEGED="${REPO_ROOT}/local/libexec/awtarchy/wireguard-helper"
SHELL_MANAGER="${REPO_ROOT}/config/hypr/scripts/quickshell.sh"
APP_STATE="${REPO_ROOT}/config/hypr/scripts/quickshell_application_state.sh"

assert_not_contains "$INSTALLER" '--quickshell-command'
assert_not_contains "$INSTALLER" 'awtarchy-quickshell'
assert_not_contains "$WORKFLOW" 'quickshell-conversion-testing'
assert_not_contains "$WORKFLOW" 'local/bin/awtarchy-quickshell'
assert_contains "$LAUNCHER" 'git-testing'
assert_contains "$LAUNCHER" 'Git testing'
assert_contains "$LAUNCHER" 'branch'
assert_contains "$LAUNCHER" 'revision'

# Help and version are read-only inspection commands. They must not create ~/vpn.
HOME_DIR="${TMPD}/home"
FAKE_BIN="${TMPD}/bin"
mkdir -p -- "$HOME_DIR" "$FAKE_BIN"
cat >"${FAKE_BIN}/curl" <<'EOF_CURL'
#!/usr/bin/env bash
exit 22
EOF_CURL
chmod 0755 "${FAKE_BIN}/curl"

COMMON_ENV=(
  "HOME=${HOME_DIR}"
  "USER=$(id -un)"
  "LOGNAME=$(id -un)"
  "PATH=${FAKE_BIN}:${PATH}"
  "AWTARCHY_SKIP_UPDATE_CHECK=1"
)

env "${COMMON_ENV[@]}" bash "$LAUNCHER" help >/dev/null
[[ ! -e "${HOME_DIR}/vpn" ]] || fail 'awtarchy help created ~/vpn'

env "${COMMON_ENV[@]}" bash "$LAUNCHER" version >/dev/null
[[ ! -e "${HOME_DIR}/vpn" ]] || fail 'awtarchy version created ~/vpn'

# The main updater can refresh before a matching Quickshell release is
# published. An already-installed pre-Quickshell release must become a safe
# no-op instead of entering the Quickshell migration runtime.
assert_contains "$LAUNCHER" 'release_has_quickshell_payload'
assert_contains "$LAUNCHER" 'config_release_ready_or_noop'
mkdir -p -- \
  "${HOME_DIR}/.local/state/awtarchy" \
  "${HOME_DIR}/.local/share/awtarchy"
printf 'tag=v2.0.0-1\n' >"${HOME_DIR}/.local/state/awtarchy/config-version"
cat >"${HOME_DIR}/.local/share/awtarchy/awtarchy-runtime.sh" <<EOF_RUNTIME
#!/usr/bin/env bash
printf 'runtime invoked\n' >"${TMPD}/runtime-invoked"
exit 99
EOF_RUNTIME
chmod 0755 "${HOME_DIR}/.local/share/awtarchy/awtarchy-runtime.sh"
cat >"${FAKE_BIN}/curl" <<'EOF_RELEASE_CURL'
#!/usr/bin/env bash
case " $* " in
  *'/releases/latest'*)
    printf '%s\n' '{"tag_name":"v2.0.0-1"}'
    ;;
  *'/releases/tags/v2.0.0-1'*)
    printf '%s\n' '{"tag_name":"v2.0.0-1","draft":false,"published_at":"2026-01-01T00:00:00Z"}'
    ;;
  *'/git/ref/tags/v2.0.0-1'*)
    printf '%s\n' '{"object":{"type":"commit","sha":"1111111111111111111111111111111111111111"}}'
    ;;
  *'quickshell-managed-history.sha256'*)
    exit 22
    ;;
  *)
    exit 22
    ;;
esac
EOF_RELEASE_CURL
chmod 0755 "${FAKE_BIN}/curl"

env "${COMMON_ENV[@]}" bash "$LAUNCHER" update >"${TMPD}/pre-quickshell.out"
[[ ! -e "${TMPD}/runtime-invoked" ]] || fail 'pre-Quickshell release entered the migration runtime'
grep -Fq 'predates the Quickshell migration and is already installed' "${TMPD}/pre-quickshell.out" \
  || fail 'pre-Quickshell release guard did not report its safe no-op'

# User-provided WireGuard profiles must not inject root command hooks, and the
# elevated executable must be the trusted Arch wireguard-tools path.
assert_contains "$WIREGUARD" 'WIREGUARD_HELPER="/usr/local/libexec/awtarchy/wireguard-helper"'
assert_contains "$WIREGUARD_PRIVILEGED" 'WG_QUICK = "/usr/bin/wg-quick"'
assert_not_contains "$WIREGUARD" 'command -v wg-quick'

VPN_DIR="${TMPD}/vpn"
mkdir -p -- "$VPN_DIR"
cat >"${VPN_DIR}/unsafe.conf" <<'EOF_PROFILE'
[Interface]
PrivateKey = test
Address = 10.0.0.2/32
PostUp = /bin/sh -c 'touch /tmp/awtarchy-wireguard-hook-ran'

[Peer]
PublicKey = test
AllowedIPs = 0.0.0.0/0
EOF_PROFILE

if AWTARCHY_VPN_DIR="$VPN_DIR" HOME="$HOME_DIR" bash "$WIREGUARD" up unsafe >"${TMPD}/wg.out" 2>"${TMPD}/wg.err"; then
  fail 'WireGuard profile containing a privileged hook was accepted'
fi
grep -Eqi 'hook|PreUp|PostUp|PreDown|PostDown' "${TMPD}/wg.err" \
  || fail 'WireGuard hook rejection did not explain the unsafe profile'

cat >"${VPN_DIR}/hidden-hook.conf" <<'EOF_COMMENT_PROFILE'
[Interface]
PrivateKey = test
PostUp # imported profile = /bin/sh -c 'touch /tmp/awtarchy-wireguard-hook-ran'
EOF_COMMENT_PROFILE
if AWTARCHY_VPN_DIR="$VPN_DIR" HOME="$HOME_DIR" \
  bash "$WIREGUARD" up hidden-hook \
  >"${TMPD}/wg-comment.out" 2>"${TMPD}/wg-comment.err";
then
  fail 'WireGuard profile containing a comment-obfuscated privileged hook was accepted'
fi
grep -Eqi 'hook|PreUp|PostUp|PreDown|PostDown' "${TMPD}/wg-comment.err" \
  || fail 'comment-obfuscated WireGuard hook rejection was not explained'

cat >"${VPN_DIR}/safe-target.conf" <<'EOF_SAFE_PROFILE'
[Interface]
PrivateKey = test
Address = 10.0.0.2/32

[Peer]
PublicKey = test
AllowedIPs = 0.0.0.0/0
EOF_SAFE_PROFILE
ln -s -- safe-target.conf "${VPN_DIR}/linked.conf"
if AWTARCHY_VPN_DIR="$VPN_DIR" HOME="$HOME_DIR" bash "$WIREGUARD" up linked >"${TMPD}/wg-link.out" 2>"${TMPD}/wg-link.err"; then
  fail 'WireGuard symbolic-link profile was accepted'
fi
grep -Eqi 'symbolic link|symlink' "${TMPD}/wg-link.err" \
  || fail 'WireGuard symbolic-link rejection did not explain the unsafe profile path'

cp -- "${VPN_DIR}/safe-target.conf" "${VPN_DIR}/unreadable.conf"
chmod 000 "${VPN_DIR}/unreadable.conf"
wireguard_read_command=(
  env
  "AWTARCHY_VPN_DIR=$VPN_DIR"
  "HOME=$HOME_DIR"
  bash "$WIREGUARD" up unreadable
)
if [[ ${EUID} -eq 0 ]]; then
  command -v capsh >/dev/null 2>&1 \
    || fail 'capsh is required to verify unreadable WireGuard profiles as root'
  wireguard_read_command=(
    env
    "AWTARCHY_VPN_DIR=$VPN_DIR"
    "HOME=$HOME_DIR"
    "AWTARCHY_WIREGUARD_TEST_SCRIPT=$WIREGUARD"
    capsh --drop=cap_dac_override -- -c
    'exec bash "$AWTARCHY_WIREGUARD_TEST_SCRIPT" up unreadable'
  )
fi
if "${wireguard_read_command[@]}" >"${TMPD}/wg-read.out" 2>"${TMPD}/wg-read.err"; then
  fail 'Unreadable WireGuard profile was accepted'
fi
grep -Eqi 'read|inspect' "${TMPD}/wg-read.err" \
  || fail 'Unreadable WireGuard profile did not fail closed during inspection'
chmod 0600 "${VPN_DIR}/unreadable.conf"

# Both writers of quickshell-state.json must serialize through the same lock.
assert_contains "$SHELL_MANAGER" 'STATE_LOCK_FILE="${STATE_FILE}.lock"'
assert_contains "$SHELL_MANAGER" 'flock -x'
assert_contains "$APP_STATE" 'STATE_LOCK_FILE="${STATE_FILE}.lock"'
assert_contains "$APP_STATE" 'flock -x'

assert_contains "$APP_STATE" 'set-notification-popup-limit'
assert_contains "$APP_STATE" '.notification_popup_limit = $popup_limit'
assert_not_contains "$APP_STATE" '{popup_limit:$popup_limit}'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/QuickSettings.qml" 'text: "Maximum output volume"'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/QuickSettings.qml" 'property int outputVolumeHoverPercent: -1'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/QuickSettings.qml" 'function outputLimitForPosition(x, width)'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/QuickSettings.qml" 'AudioLimitState.setLimit(root.outputVolumeHoverPercent)'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/Bar.qml" 'configHome + "/hypr/scripts/quickshell_volume.sh"'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/Bar.qml" 'String(AudioLimitState.limitPercent)'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/AudioLimitState.qml" 'Quickshell.execDetached([volumeScript, "set", String(limitPercent)])'
assert_contains "${REPO_ROOT}/config/hypr/scripts/quickshell_volume.sh" 'pw-cli s "$device_id" Route'
assert_contains "${REPO_ROOT}/config/hypr/scripts/quickshell_volume.sh" 'channelVolumes: [ ${channel_values} ]'
assert_not_contains "${REPO_ROOT}/config/quickshell/awtarchy/Bar.qml" '"wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@"'

volume_test_bin="${TMPD}/volume-route-bin"
volume_test_log="${TMPD}/volume-route.log"
mkdir -p "$volume_test_bin"
cat >"${volume_test_bin}/wpctl" <<'EOF_WPCTL'
#!/usr/bin/env bash
if [[ ${1:-} == inspect ]]; then
  cat <<'EOF_INSPECT'
id 60, type PipeWire:Interface:Node
    * device.id = "42"
    * card.profile.device = "7"
EOF_INSPECT
  exit 0
fi
printf 'unexpected wpctl fallback: %s\n' "$*" >&2
exit 90
EOF_WPCTL
cat >"${volume_test_bin}/pw-dump" <<'EOF_PWDUMP'
#!/usr/bin/env bash
cat <<'EOF_JSON'
[{"id":42,"info":{"params":{"Route":[{"index":3,"device":7,"props":{"mute":false,"channelVolumes":[1.0,1.0]}}]}}}]
EOF_JSON
EOF_PWDUMP
cat >"${volume_test_bin}/pw-cli" <<'EOF_PWCLI'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${AWTARCHY_VOLUME_TEST_LOG:?}"
EOF_PWCLI
chmod +x "${volume_test_bin}/wpctl" "${volume_test_bin}/pw-dump" "${volume_test_bin}/pw-cli"
PATH="${volume_test_bin}:$PATH" AWTARCHY_VOLUME_TEST_LOG="$volume_test_log"   bash "${REPO_ROOT}/config/hypr/scripts/quickshell_volume.sh" up 125
grep -Fq 'Route { index: 3, device: 7, props: { channelVolumes: [ 1.157625000, 1.157625000 ]'   "$volume_test_log" || fail 'Route-aware bar volume did not write 105% through the device route'
assert_not_contains "${REPO_ROOT}/config/quickshell/awtarchy/FlyoutSettings.qml" 'text: "Maximum output volume"'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/Notifications.qml" 'Maximum simultaneous popups · Global'
assert_not_contains "${REPO_ROOT}/config/quickshell/awtarchy/Notifications.qml" 'persisted.popupLimit'
assert_not_contains "${REPO_ROOT}/config/quickshell/awtarchy/Notifications.qml" 'notification-popup-limits.json'
assert_contains "$LAUNCHER" 'Update to current Awtarchy UI files and create backups (recommended)'

printf 'PASS: Quickshell production readiness regressions\n'
