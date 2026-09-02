#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
INSTALLER="${ROOT}/awtarchy-install.sh"
LAUNCHER="${ROOT}/local/bin/awtarchy"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
BASHRC="${ROOT}/bashrc"
QUICKSETTINGS="${ROOT}/config/hypr/scripts/hypr_quicksettings_core.sh"
WIREGUARD="${ROOT}/config/hypr/scripts/quickshell_wireguard.sh"
WIREGUARD_PRIVILEGED="${ROOT}/local/libexec/awtarchy/wireguard-helper"
SCXCTL_PRIVILEGED="${ROOT}/local/libexec/awtarchy/scxctl-helper"
GIF_CAPTURE="${ROOT}/config/hypr/scripts/gif_capture.sh"
RESIZE_TOGGLE="${ROOT}/config/hypr/scripts/toggle_resize_if_ok.sh"
VALIDATE_WORKFLOW="${ROOT}/.github/workflows/validate-awtarchy.yml"
ANTISPAM_WORKFLOW="${ROOT}/.github/workflows/antispam-pr-labeler.yml"
TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" \
    || fail "${file#"${ROOT}/"} is missing required security boundary: ${needle}"
}

assert_not_contains() {
  local file="$1" needle="$2"
  ! grep -Fq -- "$needle" "$file" \
    || fail "${file#"${ROOT}/"} still contains unsafe behavior: ${needle}"
}

bash -n "$INSTALLER"
bash -n "$LAUNCHER"
bash -n "$RUNTIME"
bash -n "$BASHRC"
bash -n "$QUICKSETTINGS"
bash -n "$WIREGUARD"
bash -n "$GIF_CAPTURE"
bash -n "$RESIZE_TOGGLE"

# AUR builds may ask for the invoking user's existing sudo authorization, but
# the installer must never create a temporary unrestricted NOPASSWD account.
assert_not_contains "$RUNTIME" 'NOPASSWD: ALL'
assert_not_contains "$RUNTIME" 'create_temp_sudoers_for_aur'
assert_contains "$RUNTIME" 'ensure_aur_sudo_access()'

# AUR Guard must scan the exact fetched checkout before makepkg evaluates the
# PKGBUILD. High and critical aur-scan findings are a hard failure. The stable
# aur-scanner package is the automatic bootstrap target when the binary is absent.
assert_contains "$BASHRC" "_AUR_GUARD_AUR_SCAN_PACKAGE='aur-scanner'"
assert_contains "$BASHRC" '_aur_guard_scan_checkout_with_aur_scan()'
# shellcheck disable=SC2016
assert_contains "$BASHRC" '"$scanner" scan "$pkgdir" --fail-on high'
# shellcheck disable=SC2016
assert_contains "$BASHRC" '_aur_guard_scan_checkout_with_aur_scan "$pkg" "$pkgdir"'
python3 - "$BASHRC" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
legacy_scan = text.index('_aur_guard_scan_package_files "$pkg" "$pkgdir"')
aur_scan = text.index('_aur_guard_scan_checkout_with_aur_scan "$pkg" "$pkgdir"', legacy_scan)
srcinfo = text.index('_aur_guard_verify_srcinfo "$pkg" "$pkgdir"', aur_scan)
if not legacy_scan < aur_scan < srcinfo:
    raise SystemExit("aur-scan does not run on the exact checkout before makepkg metadata evaluation")
PY

aur_guard_fixture="${TMPD}/bashrc-aur-guard"
aur_scan_fakebin="${TMPD}/aur-scan-fakebin"
aur_scan_runner="${TMPD}/aur-scan-runner"
aur_scan_log="${TMPD}/aur-scan.log"
aur_scan_pkgdir="${TMPD}/aur-package"
mkdir -p -- "$aur_scan_fakebin" "$aur_scan_pkgdir"
printf '%s\n' 'pkgname=fixture' >"${aur_scan_pkgdir}/PKGBUILD"
sed 's/^\[\[ \$- != \*i\* \]\] && return$/:/' "$BASHRC" >"$aur_guard_fixture"
cat >"${aur_scan_fakebin}/aur-scan" <<'EOF_AUR_SCAN'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"${AWTARCHY_TEST_AUR_SCAN_LOG:?}"
status="${AWTARCHY_TEST_AUR_SCAN_STATUS:-0}"
(( status == 0 ))
EOF_AUR_SCAN
cat >"$aur_scan_runner" <<'EOF_AUR_SCAN_RUNNER'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
source "${AWTARCHY_TEST_AUR_GUARD_FIXTURE:?}"
_aur_guard_scan_checkout_with_aur_scan fixture "${AWTARCHY_TEST_AUR_SCAN_PKGDIR:?}"
EOF_AUR_SCAN_RUNNER
chmod 0755 "${aur_scan_fakebin}/aur-scan" "$aur_scan_runner"

if ! env \
    "PATH=${aur_scan_fakebin}:$PATH" \
    AWTARCHY_TEST_AUR_SCAN_LOG="$aur_scan_log" \
    AWTARCHY_TEST_AUR_GUARD_FIXTURE="$aur_guard_fixture" \
    AWTARCHY_TEST_AUR_SCAN_PKGDIR="$aur_scan_pkgdir" \
    "$aur_scan_runner"; then
  fail 'AUR Guard rejected a clean exact-checkout aur-scan result'
fi
mapfile -t aur_scan_args <"$aur_scan_log"
[[ ${#aur_scan_args[@]} -eq 4 ]] \
  || fail 'AUR Guard passed unexpected arguments to aur-scan'
[[ ${aur_scan_args[0]} == scan ]] \
  || fail 'AUR Guard did not use aur-scan scan mode'
[[ ${aur_scan_args[1]} == "$aur_scan_pkgdir" ]] \
  || fail 'AUR Guard did not scan the exact fetched checkout'
[[ ${aur_scan_args[2]} == --fail-on && ${aur_scan_args[3]} == high ]] \
  || fail 'AUR Guard did not block high and critical aur-scan findings'

if env \
    "PATH=${aur_scan_fakebin}:$PATH" \
    AWTARCHY_TEST_AUR_SCAN_LOG="$aur_scan_log" \
    AWTARCHY_TEST_AUR_SCAN_STATUS=42 \
    AWTARCHY_TEST_AUR_GUARD_FIXTURE="$aur_guard_fixture" \
    AWTARCHY_TEST_AUR_SCAN_PKGDIR="$aur_scan_pkgdir" \
    "$aur_scan_runner" >/dev/null 2>&1; then
  fail 'AUR Guard ignored a failing aur-scan result'
fi

# AUR Guard bootstrap regression: missing aur-scan must bootstrap stable aur-scanner.
aur_scan_bootstrap_runner="${TMPD}/aur-scan-bootstrap-runner"
aur_scan_bootstrap_fakebin="${TMPD}/aur-scan-bootstrap-fakebin"
aur_scan_bootstrap_log="${TMPD}/aur-scan-bootstrap.log"
mkdir -p -- "$aur_scan_bootstrap_fakebin"
cat >"$aur_scan_bootstrap_runner" <<'EOF_AUR_SCAN_BOOTSTRAP_RUNNER'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
source "${AWTARCHY_TEST_AUR_GUARD_FIXTURE:?}"

aurinstall() {
  [[ $# -eq 1 ]]
  printf '%s\n' "$1" >"${AWTARCHY_TEST_AUR_SCAN_BOOTSTRAP_LOG:?}"
  [[ ${_AUR_GUARD_AUR_SCAN_BOOTSTRAP:-0} == 1 ]]

  cat >"${AWTARCHY_TEST_AUR_SCAN_BOOTSTRAP_FAKEBIN:?}/aur-scan" <<'EOF_FAKE_AUR_SCAN'
#!/usr/bin/env bash
exit 0
EOF_FAKE_AUR_SCAN
  chmod 0755 "${AWTARCHY_TEST_AUR_SCAN_BOOTSTRAP_FAKEBIN:?}/aur-scan"
}

_AUR_GUARD_AUR_SCAN_BOOTSTRAP=0
_aur_guard_ensure_aur_scan fixture
[[ ${_AUR_GUARD_AUR_SCAN_BOOTSTRAP:-0} == 0 ]]
type -P aur-scan >/dev/null 2>&1
EOF_AUR_SCAN_BOOTSTRAP_RUNNER
chmod 0755 "$aur_scan_bootstrap_runner"

if ! env \
    "PATH=${aur_scan_bootstrap_fakebin}:/usr/bin:/bin" \
    AWTARCHY_TEST_AUR_GUARD_FIXTURE="$aur_guard_fixture" \
    AWTARCHY_TEST_AUR_SCAN_BOOTSTRAP_FAKEBIN="$aur_scan_bootstrap_fakebin" \
    AWTARCHY_TEST_AUR_SCAN_BOOTSTRAP_LOG="$aur_scan_bootstrap_log" \
    "$aur_scan_bootstrap_runner"; then
  fail 'AUR Guard could not bootstrap aur-scanner when aur-scan was absent'
fi
grep -Fxq -- 'aur-scanner' "$aur_scan_bootstrap_log" \
  || fail 'AUR Guard did not bootstrap the stable aur-scanner package'

# Once a launcher/runtime is target-user-owned, root must only invoke it after
# dropping to that target user. Maintenance config operations are user-scoped.
assert_contains "$INSTALLER" 'run_as_target env -u XDG_DATA_HOME -u XDG_STATE_HOME'
# shellcheck disable=SC2016
assert_contains "$INSTALLER" 'run_as_target install -m 0755 "$LAUNCHER_SOURCE" "${bin_dir}/awtarchy"'
# shellcheck disable=SC2016
assert_contains "$INSTALLER" 'run_as_target install -m 0755 "$RUNTIME_SOURCE" "${data_dir}/awtarchy-runtime.sh"'
# shellcheck disable=SC2016
assert_not_contains "$INSTALLER" '  install -m 0755 "$LAUNCHER_SOURCE" "${bin_dir}/awtarchy"'
assert_contains "$RUNTIME" 'drop_update_privileges()'
assert_contains "$LAUNCHER" 'drop_launcher_privileges()'
# shellcheck disable=SC2016
assert_not_contains "$RUNTIME" 'chown -R "${TARGET_USER}:${TARGET_USER}" "${HOME_DIR}/.ssh"'

# A sudo-invoked maintenance launcher must re-exec as the invoking desktop
# user before it creates a VPN directory or performs its own updater writes.
python3 - "$LAUNCHER" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
main = text.index("main() {")
drop = text.index('drop_launcher_privileges "$@"', main)
init = text.index("init_target", drop)
vpn = text.index("ensure_vpn_directory", init)
if not main < drop < init < vpn:
    raise SystemExit("launcher privilege drop does not precede user-home operations")
PY

launcher_fixture="${TMPD}/awtarchy-root-entry"
launcher_fakebin="${TMPD}/launcher-fakebin"
launcher_home="${TMPD}/launcher-home"
launcher_runuser_log="${TMPD}/launcher-runuser.log"
mkdir -p -- "$launcher_fakebin" "$launcher_home"
# shellcheck disable=SC2016
sed \
  -e "s|/usr/bin/runuser|${launcher_fakebin}/runuser|g" \
  -e "s|/usr/bin/getent|${launcher_fakebin}/getent|g" \
  -e 's/${EUID} -ne 0/${AWTARCHY_TEST_EUID:-${EUID}} -ne 0/' \
  "$LAUNCHER" >"$launcher_fixture"
chmod 0755 "$launcher_fixture"
cat >"$launcher_fakebin/getent" <<EOF_GETENT
#!/usr/bin/env bash
set -euo pipefail
if [[ \${1:-} == passwd && \${2:-} == awtarchytest ]]; then
  printf '%s:x:1000:1000:Awtarchy test:%s:/bin/bash\n' awtarchytest '$launcher_home'
  exit 0
fi
exec /usr/bin/getent "\$@"
EOF_GETENT
cat >"$launcher_fakebin/runuser" <<'EOF_RUNUSER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"${AWTARCHY_TEST_RUNUSER_LOG:?}"
EOF_RUNUSER
chmod 0755 "$launcher_fakebin/getent" "$launcher_fakebin/runuser"
env \
  "PATH=$launcher_fakebin:$PATH" \
  HOME=/root \
  USER=root \
  SUDO_USER=awtarchytest \
  AWTARCHY_TEST_EUID=0 \
  "AWTARCHY_TEST_RUNUSER_LOG=$launcher_runuser_log" \
  "$launcher_fixture" version
grep -Fxq -- '-u' "$launcher_runuser_log" \
  || fail 'root launcher did not invoke runuser'
grep -Fxq -- 'awtarchytest' "$launcher_runuser_log" \
  || fail 'root launcher did not select SUDO_USER'
grep -Fxq -- "HOME=$launcher_home" "$launcher_runuser_log" \
  || fail 'root launcher did not restore the target account home'
grep -Fxq -- 'version' "$launcher_runuser_log" \
  || fail 'root launcher did not preserve command arguments during privilege drop'
[[ ! -e $launcher_home/vpn ]] \
  || fail 'root launcher touched the target home before dropping privileges'

# Remote candidate scripts are data under review, not code to execute before
# the user has accepted the operation.
# shellcheck disable=SC2016
assert_not_contains "$RUNTIME" 'bash "$quickshell_helper"'
assert_contains "$RUNTIME" 'render_theme_target()'

# User-owned baseline state and TSV rows cannot escape the explicitly managed
# home-relative path set.
assert_contains "$RUNTIME" 'validate_managed_relative_path()'
assert_contains "$RUNTIME" 'validate_plan_row()'

# Stable release labels remain release based, while archive bytes are bound to
# the immutable commit resolved for that tag and every tar member is checked.
assert_contains "$RUNTIME" 'resolve_release_tag_commit()'
assert_contains "$RUNTIME" 'validate_source_archive()'
# shellcheck disable=SC2016
assert_contains "$RUNTIME" '/releases/tags/${tag_enc}'
# shellcheck disable=SC2016
assert_contains "$RUNTIME" '/git/ref/tags/${tag_enc}'
# shellcheck disable=SC2016
assert_not_contains "$RUNTIME" '/commits/${tag_enc}'
assert_contains "$RUNTIME" 'resolve_remote_testing_branch_head()'
assert_contains "$RUNTIME" 'testing_commit_belongs_to_branch()'

# Sudoers staging is root-owned from creation through validation and rename.
# shellcheck disable=SC2016
assert_contains "$QUICKSETTINGS" 'sudo mktemp "/etc/sudoers.d/.${sudoers_name}.XXXXXX"'
# shellcheck disable=SC2016
assert_not_contains "$QUICKSETTINGS" 'printf '\''%s ALL=(root) NOPASSWD: /usr/bin/scxctl\n'\'' "$user" > "$tmpfile"'

# The passwordless scheduler boundary is a fixed root-owned broker, not the
# complete external scxctl CLI. Exercise both accepted UI forms and malformed
# direct calls through the same broker parser.
[[ -f $SCXCTL_PRIVILEGED ]] || fail 'root-owned scxctl helper source is missing'
bash -n "$SCXCTL_PRIVILEGED"
[[ $(head -n1 "$SCXCTL_PRIVILEGED") == '#!/usr/bin/bash' ]] \
  || fail 'privileged scxctl helper does not use a fixed Bash interpreter'
assert_contains "$QUICKSETTINGS" 'SCXCTL_HELPER="/usr/local/libexec/awtarchy/scxctl-helper"'
assert_not_contains "$QUICKSETTINGS" 'NOPASSWD: /usr/bin/scxctl'
assert_not_contains "$QUICKSETTINGS" 'sudo -n /usr/bin/scxctl'

scx_fixture="${TMPD}/scxctl-helper"
scx_log="${TMPD}/scxctl.log"
scx_fake="${TMPD}/scxctl"
sed "s|^SCXCTL=.*|SCXCTL=\"${scx_fake}\"|" "$SCXCTL_PRIVILEGED" >"$scx_fixture"
cat >"$scx_fake" <<'EOF_SCXCTL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >>"${AWTARCHY_TEST_SCXCTL_LOG:?}"
EOF_SCXCTL
chmod 0755 "$scx_fixture" "$scx_fake"
for command in \
  'list' \
  'get' \
  'stop' \
  'start --sched beerland' \
  'switch --sched lavd --args --performance'; do
  # The production caller passes each field as a separate argument.
  IFS=' ' read -r -a fields <<<"$command"
  AWTARCHY_TEST_SCXCTL_LOG="$scx_log" "$scx_fixture" "${fields[@]}" \
    || fail "privileged scxctl helper rejected supported form: $command"
done
for command in \
  'status' \
  'start --sched arbitrary' \
  'start --args unsafe' \
  'stop extra'; do
  IFS=' ' read -r -a fields <<<"$command"
  if AWTARCHY_TEST_SCXCTL_LOG="$scx_log" "$scx_fixture" "${fields[@]}" \
      >/dev/null 2>&1; then
    fail "privileged scxctl helper accepted unsupported form: $command"
  fi
done
if AWTARCHY_TEST_SCXCTL_LOG="$scx_log" "$scx_fixture" \
    start --sched lavd --args $'ok\nunsafe' >/dev/null 2>&1; then
  fail 'privileged scxctl helper accepted control characters in scheduler args'
fi

# Cross-invocation PID/state files belong below a verified private desktop
# runtime directory. A symlinked XDG_RUNTIME_DIR must be rejected before either
# script reaches recorder or compositor commands.
assert_not_contains "$GIF_CAPTURE" '/tmp/gif-record-'
assert_not_contains "$RESIZE_TOGGLE" '/tmp/hypr-resize.'
assert_contains "$GIF_CAPTURE" 'XDG_RUNTIME_DIR'
assert_contains "$RESIZE_TOGGLE" 'XDG_RUNTIME_DIR'

runtime_fakebin="${TMPD}/runtime-fakebin"
runtime_safe="${TMPD}/runtime-safe"
runtime_link="${TMPD}/runtime-link"
runtime_marker="${TMPD}/runtime-command-ran"
mkdir -m 0700 -- "$runtime_fakebin" "$runtime_safe"
ln -s -- "$runtime_safe" "$runtime_link"
for command in wf-recorder ffmpeg notify-send jq pkill; do
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"${runtime_fakebin}/${command}"
done
cat >"${runtime_fakebin}/slurp" <<'EOF_SLURP'
#!/usr/bin/env bash
: >"${AWTARCHY_TEST_RUNTIME_MARKER:?}"
exit 1
EOF_SLURP
cat >"${runtime_fakebin}/hyprctl" <<'EOF_HYPRCTL'
#!/usr/bin/env bash
: >"${AWTARCHY_TEST_RUNTIME_MARKER:?}"
printf '%s\n' null
EOF_HYPRCTL
chmod 0755 "$runtime_fakebin"/*

if env PATH="$runtime_fakebin:$PATH" HOME="$TMPD" USER="$(id -un)" \
    XDG_RUNTIME_DIR="$runtime_link" AWTARCHY_TEST_RUNTIME_MARKER="$runtime_marker" \
    bash "$GIF_CAPTURE" >/dev/null 2>&1; then
  fail 'GIF capture accepted a symlinked XDG runtime directory'
fi
[[ ! -e $runtime_marker ]] \
  || fail 'GIF capture reached recorder commands before rejecting unsafe runtime state'
if env PATH="$runtime_fakebin:$PATH" HOME="$TMPD" USER="$(id -un)" \
    XDG_RUNTIME_DIR="$runtime_link" AWTARCHY_TEST_RUNTIME_MARKER="$runtime_marker" \
    bash "$RESIZE_TOGGLE" >/dev/null 2>&1; then
  fail 'resize toggle accepted a symlinked XDG runtime directory'
fi
[[ ! -e $runtime_marker ]] \
  || fail 'resize toggle reached compositor commands before rejecting unsafe runtime state'

env PATH="$runtime_fakebin:$PATH" HOME="$TMPD" USER="$(id -un)" \
  XDG_RUNTIME_DIR="$runtime_safe" AWTARCHY_TEST_RUNTIME_MARKER="$runtime_marker" \
  bash "$GIF_CAPTURE" >/dev/null 2>&1 || true
[[ -d $runtime_safe/awtarchy ]] \
  || fail 'GIF capture did not create private Awtarchy runtime state'
[[ $(stat -c '%u:%a' "$runtime_safe/awtarchy") == "$(id -u):700" ]] \
  || fail 'Awtarchy desktop runtime state ownership or mode is unsafe'

# The privileged WireGuard process reopens and snapshots the profile itself;
# the user-owned wrapper never passes a mutable profile path to wg-quick.
[[ -f $WIREGUARD_PRIVILEGED ]] || fail 'root-owned WireGuard helper source is missing'
PYTHONDONTWRITEBYTECODE=1 python3 - "$WIREGUARD_PRIVILEGED" "$TMPD" <<'PY'
from importlib.machinery import SourceFileLoader
from pathlib import Path
import os
import sys

module = SourceFileLoader("awtarchy_wireguard_helper", sys.argv[1]).load_module()
home = Path(sys.argv[2]) / "home"
vpn = home / "vpn"
vpn.mkdir(parents=True, mode=0o700)
home.chmod(0o700)
vpn.chmod(0o700)
safe = vpn / "safe.conf"
safe.write_text("[Interface]\nPrivateKey = test\n", encoding="utf-8")
safe.chmod(0o600)
assert module.read_profile_snapshot(str(home), os.getuid(), "safe").startswith(b"[Interface]")

unsafe = vpn / "unsafe.conf"
unsafe.write_text("[Interface]\nPostUp = touch /tmp/pwned\n", encoding="utf-8")
unsafe.chmod(0o600)
try:
    module.read_profile_snapshot(str(home), os.getuid(), "unsafe")
except module.ProfileError:
    pass
else:
    raise SystemExit("privileged WireGuard helper accepted a command hook")

for index, directive in enumerate(
    (
        "PreUp # imported = touch /tmp/pwned",
        "PostUp#comment=touch /tmp/pwned",
        "PreDown \t# imported = touch /tmp/pwned",
        "PostDown #= touch /tmp/pwned",
    ),
    start=1,
):
    hidden = vpn / f"hidden{index}.conf"
    hidden.write_text(f"[Interface]\n{directive}\n", encoding="utf-8")
    hidden.chmod(0o600)
    try:
        module.read_profile_snapshot(str(home), os.getuid(), f"hidden{index}")
    except module.ProfileError:
        pass
    else:
        raise SystemExit(
            f"privileged WireGuard helper accepted a comment-obfuscated hook: {directive}"
        )

linked = vpn / "linked.conf"
linked.symlink_to(safe.name)
try:
    module.read_profile_snapshot(str(home), os.getuid(), "linked")
except (module.ProfileError, OSError):
    pass
else:
    raise SystemExit("privileged WireGuard helper followed a profile symlink")
PY
assert_contains "$WIREGUARD" 'WIREGUARD_HELPER="/usr/local/libexec/awtarchy/wireguard-helper"'
# shellcheck disable=SC2016
assert_not_contains "$WIREGUARD" 'exec pkexec "$WG_QUICK" "$action" "$conf"'

# Workflow dependencies that receive repository context or a token are pinned
# to reviewed commits. The PR labeler gets only the permission it needs.
assert_contains "$VALIDATE_WORKFLOW" \
  'uses: actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955 # v4.3.0'
assert_contains "$ANTISPAM_WORKFLOW" 'permissions:'
assert_contains "$ANTISPAM_WORKFLOW" 'pull-requests: write'
assert_contains "$ANTISPAM_WORKFLOW" \
  'uses: PraiseXI/AntiSpamPRLabeler@6dceeed42338b61e9d2957a124f170efee7aaf7a # v1.2.0'

printf 'PASS: installer, updater, and privileged helper security boundaries\n'
