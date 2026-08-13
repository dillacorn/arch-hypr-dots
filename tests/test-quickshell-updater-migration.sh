#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${ROOT}/awtarchy-install.sh"
STABLE_LAUNCHER="${ROOT}/local/bin/awtarchy"
QUICKSHELL_LAUNCHER="${ROOT}/local/bin/awtarchy-quickshell"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
MANAGED_HISTORY="${ROOT}/local/share/awtarchy/quickshell-managed-history.sha256"
TEST_COMMIT="1111111111111111111111111111111111111111"
DESKTOP_STALE_SYSTEM_STATE_SHA="f96522fad74218f14c40f1a05902e8d41b6d3f929f9f8750040f5600eb45258c"
TMP="$(mktemp -d)"

cleanup() {
  if [[ -s ${TMP}/hypridle.pid ]]; then
    kill "$(<"${TMP}/hypridle.pid")" >/dev/null 2>&1 || true
  fi
  if [[ ${AWTARCHY_TEST_KEEP_TMP:-0} == 1 ]]; then
    printf 'Preserved updater test workspace: %s\n' "$TMP" >&2
    return
  fi
  rm -rf -- "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f $1 ]] || fail "missing file: $1"
}

assert_absent() {
  [[ ! -e $1 && ! -L $1 ]] || fail "path should be absent: $1"
}

assert_package() {
  grep -Fxq "$2" "$1" || fail "missing package $2 in $1"
}

assert_no_package() {
  ! grep -Fxq "$2" "$1" || fail "retired package still present: $2"
}

TARGET_USER="$(id -un)"

RETIRED_DIRS=(
  .config/waybar
  .config/fuzzel
  .config/mako
  .config/wlogout
  .config/wofi
  .cache/waybar
  .cache/fuzzel
  .cache/wofi
)
RETIRED_FILES=(
  .config/hypr/scripts/cliphist-fuzzel.sh
  .config/hypr/scripts/cliphist-wofi.sh
  .config/hypr/scripts/fuzzel_toggle.sh
  .config/hypr/scripts/mako_dismiss.sh
  .config/hypr/scripts/waybar.sh
  .config/hypr/scripts/waybar_flip.sh
  .config/hypr/scripts/waybar_ready_sound.sh
  .config/hypr/scripts/waybar_restore_resume.sh
  .config/hypr/scripts/waybar_rotate.sh
  .config/hypr/scripts/waybar_toggle.sh
  .config/hypr/scripts/waybar_toggle_idle.sh
  .config/hypr/scripts/wlogout_toggle.sh
  .local/share/applications/hypr_quicksettings.desktop
  .local/share/applications/waybar_flip.desktop
  .local/share/applications/waybar_rotate.desktop
  .local/share/applications/waybar_toggle.desktop
)

assert_retired_paths_absent() {
  local home="$1" rel
  for rel in "${RETIRED_DIRS[@]}" "${RETIRED_FILES[@]}"; do
    assert_absent "${home}/${rel}"
    assert_absent "${home}/${rel}.backup"
  done
  assert_absent "${home}/.config/fuzzel.backup.20260812-000000"
  assert_absent "${home}/.local/share/applications/hypr_quicksettings.desktop.backup.20260812-000000"
  assert_absent "${home}/.cache/wofi-drun"
  assert_absent "${home}/.cache/wofi-drun.backup"
}

fakebin="${TMP}/fakebin"
mkdir -p "$fakebin"

cat >"${fakebin}/getent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == passwd ]]; then
  printf '%s:x:1000:1000:Updater test:%s:/bin/bash\n' \
    "${AWTARCHY_TEST_TARGET_USER:?}" "${AWTARCHY_TEST_TARGET_HOME:?}"
  exit 0
fi
exec /usr/bin/getent "$@"
EOF

cat >"${fakebin}/awk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $* == *'/etc/passwd'* ]]; then
  printf '%s\n' "${AWTARCHY_TEST_TARGET_USER:?}"
  exit 0
fi
exec /usr/bin/awk "$@"
EOF

cat >"${fakebin}/runuser" <<'EOF'
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
EOF

cat >"${fakebin}/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == -v ]]; then
  exit 0
fi
exec "$@"
EOF

cat >"${fakebin}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=""
url=""
progress=0
speed_limit=""
speed_time=""
while (( $# )); do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -H|--connect-timeout|--max-time|--retry|--retry-delay)
      shift 2
      ;;
    --progress-bar)
      progress=1
      shift
      ;;
    --speed-limit)
      speed_limit="$2"
      shift 2
      ;;
    --speed-time)
      speed_time="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
printf '%s\n' "$url" >>"${AWTARCHY_TEST_CURL_LOG:?}"
if [[ $url == *'/releases/latest' ]]; then
  printf '%s\n' '{"tag_name":"v2.0.0-1"}'
  exit 0
fi
if [[ $url == 'https://api.github.com/repos/dillacorn/awtarchy/commits/quickshell-conversion-testing' ]]; then
  printf '{"sha":"%s"}\n' "${AWTARCHY_TEST_COMMIT:?}"
  exit 0
fi
if [[ $url == 'https://github.com/dillacorn/awtarchy/archive/refs/tags/v2.0.0-1.tar.gz' ]]; then
  [[ -n $out ]] || exit 43
  (( progress == 1 )) || exit 44
  [[ $speed_limit == 1024 ]] || exit 45
  [[ $speed_time == 30 ]] || exit 46
  cp -- "${AWTARCHY_TEST_PREVIOUS_ARCHIVE:?}" "$out"
  exit 0
fi
expected="https://github.com/dillacorn/awtarchy/archive/${AWTARCHY_TEST_COMMIT:?}.tar.gz"
[[ $url == "$expected" ]] || exit 42
[[ -n $out ]] || exit 43
(( progress == 1 )) || exit 44
[[ $speed_limit == 1024 ]] || exit 45
[[ $speed_time == 30 ]] || exit 46
cp -- "${AWTARCHY_TEST_ARCHIVE:?}" "$out"
EOF

cat >"${fakebin}/pacman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${AWTARCHY_TEST_PACKAGE_STATE:?}"
log="${AWTARCHY_TEST_PACMAN_LOG:?}"
printf '%s\n' "$*" >>"$log"
action="${1:-}"
shift || true
case "$action" in
  -Q)
    pkg="${1:-}"
    [[ -n $pkg ]] || exit 1
    if [[ $pkg == waybar ]] && grep -Fxq waybar-git "$state"; then
      exit 0
    fi
    grep -Fxq "$pkg" "$state"
    ;;
  -Qq)
    if (( $# == 0 )); then
      cat "$state"
      exit 0
    fi
    pkg="${1:-}"
    [[ -n $pkg ]] || exit 1
    if [[ $pkg == waybar ]] && grep -Fxq waybar-git "$state"; then
      printf '%s\n' waybar-git
      exit 0
    fi
    grep -Fxq "$pkg" "$state" && printf '%s\n' "$pkg"
    ;;
  -S)
    for pkg in "$@"; do
      [[ $pkg == -* ]] && continue
      grep -Fxq "$pkg" "$state" || printf '%s\n' "$pkg" >>"$state"
    done
    LC_ALL=C sort -u -o "$state" "$state"
    ;;
  -Rns)
    for pkg in "$@"; do
      [[ $pkg == -* ]] && continue
      if ! grep -Fxq "$pkg" "$state"; then
        printf 'error: target not found: %s\n' "$pkg" >&2
        exit 1
      fi
    done
    for pkg in "$@"; do
      [[ $pkg == -* ]] && continue
      tmp="${state}.tmp"
      grep -Fxv "$pkg" "$state" >"$tmp" || true
      mv -f "$tmp" "$state"
    done
    ;;
  *)
    exit 44
    ;;
esac
EOF

cat >"${fakebin}/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_TEST_HYPRCTL_LOG:?}"
case "${1:-}" in
  monitors)
    printf '%s\n' '[{"name":"eDP-1","focused":true,"disabled":false}]'
    ;;
  activeworkspace)
    printf '%s\n' '{"monitor":"eDP-1"}'
    ;;
  configerrors)
    printf '%s\n' 'No config errors'
    ;;
  reload)
    exit 0
    ;;
  *)
    printf '%s\n' '{}'
    ;;
esac
EOF

cat >"${fakebin}/qs" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${AWTARCHY_TEST_QS_STATE:?}"
if [[ -e /proc/$$/fd/9 ]]; then
  : >"${AWTARCHY_TEST_QS_FD_LEAK_FILE:?}"
fi
if [[ $* == *'ipc call control ping'* ]]; then
  [[ -f $state ]] || exit 1
  printf '%s\n' ok
  exit 0
fi
if [[ $* == *'ipc call control quit'* ]]; then
  if [[ ${AWTARCHY_TEST_QS_STALL_QUIT:-0} != 1 ]]; then
    rm -f -- "$state"
  fi
  exit 0
fi
if [[ $* == *' kill' ]]; then
  printf '%s\n' "$*" >>"${AWTARCHY_TEST_QS_KILL_LOG:?}"
  rm -f -- "$state"
  exit 0
fi
[[ ! -e ${AWTARCHY_TEST_QS_FAIL_FILE:?} ]] || exit 1
: >"$state"
EOF

cat >"${fakebin}/pkill" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_TEST_PKILL_LOG:?}"
if [[ $* == *hypridle* && -n ${AWTARCHY_TEST_HYPRIDLE_STATE:-} ]]; then
  if [[ -s $AWTARCHY_TEST_HYPRIDLE_STATE ]]; then
    pid="$(<"$AWTARCHY_TEST_HYPRIDLE_STATE")"
    [[ $pid =~ ^[0-9]+$ ]] && kill "$pid" >/dev/null 2>&1 || true
  fi
  rm -f -- "$AWTARCHY_TEST_HYPRIDLE_STATE"
fi
EOF

cat >"${fakebin}/pgrep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${AWTARCHY_TEST_HYPRIDLE_STATE:?}"
[[ -s $state ]] || exit 1
value="$(<"$state")"
if [[ $value =~ ^[0-9]+$ ]]; then
  kill -0 "$value" 2>/dev/null
else
  [[ $value == stale ]]
fi
EOF

cat >"${fakebin}/hypridle" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${AWTARCHY_TEST_HYPRIDLE_ARGS:?}"
if [[ -e /proc/$$/fd/8 || -e /proc/$$/fd/9 ]]; then
  : >"${AWTARCHY_TEST_HYPRIDLE_FD_LEAK_FILE:?}"
fi
printf '%s\n' "$$" >"${AWTARCHY_TEST_HYPRIDLE_PID:?}"
printf '%s\n' "$$" >"${AWTARCHY_TEST_HYPRIDLE_STATE:?}"
trap 'rm -f -- "${AWTARCHY_TEST_HYPRIDLE_STATE:?}"' EXIT
while :; do
  /bin/sleep 0.1
done
EOF

cat >"${fakebin}/sleep" <<'EOF'
#!/usr/bin/env bash
/bin/sleep 0.001
EOF

chmod 0755 "${fakebin}/"*

cat >"${fakebin}/makoctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"${fakebin}/python" <<'EOF'
#!/usr/bin/env bash
exec python3 "$@"
EOF
chmod 0755 "${fakebin}/makoctl" "${fakebin}/python"

archive_parent="${TMP}/archive"
archive_root="${archive_parent}/awtarchy-${TEST_COMMIT}"
mkdir -p "$archive_root"
tar --exclude=.git -C "$ROOT" -cf - . | tar -C "$archive_root" -xf -
tar -czf "${TMP}/testing-commit.tar.gz" -C "$archive_parent" "$(basename "$archive_root")"

previous_parent="${TMP}/previous-archive"
previous_root="${previous_parent}/awtarchy-2.0.0-1"
mkdir -p "$previous_parent"
git -C "$ROOT" archive \
  --format=tar.gz \
  --prefix='awtarchy-2.0.0-1/' \
  --output="${TMP}/previous-release.tar.gz" \
  v2.0.0-1
tar -xzf "${TMP}/previous-release.tar.gz" -C "$previous_parent"

seed_old_home() {
  local home="$1" rel
  mkdir -p \
    "$home/.cache" \
    "$home/.config" \
    "$home/.local/share" \
    "$home/.local/bin" \
    "$home/.local/share/awtarchy" \
    "$home/.local/state/awtarchy"

  cp -a -- "$previous_root/config/." "$home/.config/"
  if [[ -d "$previous_root/local/share/applications" ]]; then
    mkdir -p "$home/.local/share/applications"
    cp -a -- "$previous_root/local/share/applications/." "$home/.local/share/applications/"
  fi
  [[ -f "$previous_root/bashrc" ]] && cp -- "$previous_root/bashrc" "$home/.bashrc"
  [[ -f "$previous_root/bash_profile" ]] && cp -- "$previous_root/bash_profile" "$home/.bash_profile"
  [[ -f "$previous_root/Xresources" ]] && cp -- "$previous_root/Xresources" "$home/.Xresources"

  mkdir -p "$home/.config/micro"
  cat >"$home/.config/micro/settings.json" <<'EOF'
{
    "colorscheme": "default",
    "autosave": 0
}
EOF

  HOME="$home" PATH="${fakebin}:$PATH" AWTARCHY_TEST_HYPRCTL_LOG=/dev/null \
    bash "$previous_root/config/hypr/themes/gruvbox" >/dev/null

  printf '\n%s\n' '-- personal Hyprland customization survives migration' \
    >>"$home/.config/hypr/hyprland.lua"
  printf '\n%s\n' 'custom laptop waybar' >>"$home/.config/waybar/config"

  for rel in "${RETIRED_DIRS[@]}" "${RETIRED_FILES[@]}"; do
    [[ -e "${home}/${rel}" || -L "${home}/${rel}" ]] || continue
    cp -a -- "${home}/${rel}" "${home}/${rel}.backup"
  done
  [[ -d "$home/.config/fuzzel" ]] && cp -a -- "$home/.config/fuzzel" \
    "$home/.config/fuzzel.backup.20260812-000000"
  [[ -f "$home/.local/share/applications/hypr_quicksettings.desktop" ]] && cp -a -- \
    "$home/.local/share/applications/hypr_quicksettings.desktop" \
    "$home/.local/share/applications/hypr_quicksettings.desktop.backup.20260812-000000"
  printf '%s\n' 'retired Wofi launch cache' >"$home/.cache/wofi-drun"
  cp -a -- "$home/.cache/wofi-drun" "$home/.cache/wofi-drun.backup"

  printf '%s\n' 'tag=v2.0.0-1' 'installed_at=2026-08-01T00:00:00-04:00' \
    >"$home/.local/state/awtarchy/config-version"
  printf '%s\n' 'tag=v2.0.0-1' \
    'revision=2222222222222222222222222222222222222222' \
    'installed_at=2026-08-01T00:00:00-04:00' \
    >"$home/.local/state/awtarchy/command-version"
  printf '%s\n' gruvbox >"$home/.local/state/awtarchy/active-theme"

  install -m 0755 "$STABLE_LAUNCHER" "$home/.local/bin/awtarchy"
  install -m 0755 "$RUNTIME" "$home/.local/share/awtarchy/awtarchy-runtime.sh"
}

write_old_package_state() {
  printf '%s\n' \
    waybar-git fuzzel wlogout mako wofi network-manager-applet blueman \
    networkmanager bluez bluez-utils jq \
    >"$1"
}

home="${TMP}/home"
seed_old_home "$home"
legacy_personal_hypr="${TMP}/legacy-personal-hyprland.lua"
cp -- "$home/.config/hypr/hyprland.lua" "$legacy_personal_hypr"
stable_launcher_hash="$(sha256sum "$home/.local/bin/awtarchy" | awk '{print $1}')"
stable_runtime_hash="$(sha256sum "$home/.local/share/awtarchy/awtarchy-runtime.sh" | awk '{print $1}')"

common_env=(
  "HOME=$home"
  "USER=$TARGET_USER"
  "SUDO_USER=$TARGET_USER"
  "PATH=${fakebin}:$PATH"
  "AWTARCHY_INSTALL_BRANCH=quickshell-conversion-testing"
  "AWTARCHY_TESTING_COMMIT=$TEST_COMMIT"
  "AWTARCHY_SYSTEM_BIN_DIR=${TMP}/system-bin"
  "AWTARCHY_TEST_TARGET_USER=$TARGET_USER"
  "AWTARCHY_TEST_TARGET_HOME=$home"
)
mkdir -p "${TMP}/system-bin"
env "${common_env[@]}" bash "$INSTALLER" --quickshell-command \
  >"${TMP}/installer.out"

installed_launcher="$home/.local/bin/awtarchy-quickshell"
installed_runtime="$home/.local/share/awtarchy-quickshell/awtarchy-runtime.sh"
managed_packages="${TMP}/managed-packages"
assert_file "$installed_launcher"
assert_file "$installed_runtime"
assert_file "$MANAGED_HISTORY"
grep -Fqx "${DESKTOP_STALE_SYSTEM_STATE_SHA}"$'\t''.config/quickshell/awtarchy/SystemState.qml' \
  "$MANAGED_HISTORY" \
  || fail "managed history does not recognize the stale desktop SystemState.qml"
while IFS= read -r repo_path; do
  repo_rel="${repo_path#"$ROOT/"}"
  current_entry="$(sha256sum "$repo_path" | awk '{print $1}')"$'\t'".${repo_rel}"
  grep -Fqx "$current_entry" "$MANAGED_HISTORY" \
    || fail "managed history is missing the current stock hash for ${repo_path}"
done < <(
  {
    find "$ROOT/config/quickshell/awtarchy" -maxdepth 1 -type f -print
    find "$ROOT/config/hypr/scripts" -maxdepth 1 -type f \
      \( -name 'quickshell*' -o -name 'ddc_brightness.sh' -o -name 'hypr-ddc-brightness.sh' \) \
      -print
  } | LC_ALL=C sort -u
)
cmp -s "$installed_launcher" "$QUICKSHELL_LAUNCHER" \
  || fail "installer did not install the branch testing launcher"
assert_file "${TMP}/system-bin/awtarchy-quickshell"
assert_absent "${TMP}/system-bin/awtarchy"
[[ $stable_launcher_hash == "$(sha256sum "$home/.local/bin/awtarchy" | awk '{print $1}')" ]] \
  || fail "testing command installation changed the stable launcher"
[[ $stable_runtime_hash == "$(sha256sum "$home/.local/share/awtarchy/awtarchy-runtime.sh" | awk '{print $1}')" ]] \
  || fail "testing command installation changed the stable runtime"
grep -Fxq "revision=${TEST_COMMIT}" \
  "$home/.local/state/awtarchy-quickshell/command-version" \
  || fail "testing command did not record its exact commit"
bash -n "$installed_runtime"
bash -n "$installed_launcher"
grep -Fq -- '--testing-commit' "$installed_runtime" \
  || fail "testing runtime did not retain pinned-commit support"
grep -Fq 'ensure_quickshell_update_prerequisites' "$installed_runtime" \
  || fail "testing runtime did not receive updater migration prerequisites"
grep -Fq 'start_quickshell_update_shell' "$installed_runtime" \
  || fail "testing runtime did not receive live shell validation"
grep -Fq 'restart 9>&-' "$installed_runtime" \
  || fail "testing runtime does not close the updater lock for Quickshell"
grep -Fq ' start 9>&-' "$installed_runtime" \
  || fail "testing runtime does not restart a restored Quickshell after rollback"

failure_home="${TMP}/failure-home"
cp -a -- "$home" "$failure_home"

# Model a user who already has a working Quickshell manager. The preserved
# manager rejects the newly applied shell, then accepts the restored tree. This
# verifies that rollback does not leave the previously working shell stopped.
cat >"$failure_home/.config/hypr/scripts/quickshell.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state="${AWTARCHY_TEST_ROLLBACK_QS_STATE:?}"
log="${AWTARCHY_TEST_ROLLBACK_QS_LOG:?}"
action="${1:-}"
printf '%s\n' "$action" >>"$log"

case "$action" in
  start)
    [[ ! -e "$HOME/.config/quickshell/awtarchy/shell.qml" ]] || exit 1
    : >"$state"
    ;;
  stop)
    rm -f -- "$state"
    ;;
  restart)
    "$0" stop
    "$0" start
    ;;
  status)
    [[ -e $state ]] && printf '%s\n' running || printf '%s\n' stopped
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod 0755 "$failure_home/.config/hypr/scripts/quickshell.sh"
: >"${TMP}/rollback-qs.state"
: >"${TMP}/rollback-qs.log"

package_state="${TMP}/packages"
write_old_package_state "$package_state"
cp -- "$package_state" "$managed_packages"
: >"${TMP}/curl.log"
: >"${TMP}/pacman.log"
: >"${TMP}/hyprctl.log"
: >"${TMP}/pkill.log"
: >"${TMP}/qs-kill.log"
mkdir -p "${TMP}/runtime"
: >"${TMP}/qs.state"
printf '%s\n' stale >"${TMP}/hypridle.state"
printf '%s\n' 1 >"${TMP}/runtime/awtarchy-quickshell-idle-hidden"

update_env=(
  "HOME=$home"
  "USER=$TARGET_USER"
  "SUDO_USER=$TARGET_USER"
  "PATH=${fakebin}:$PATH"
  "XDG_RUNTIME_DIR=${TMP}/runtime"
  "HYPRLAND_INSTANCE_SIGNATURE=awtarchy-test"
  "AWTARCHY_SKIP_UPDATE_CHECK=1"
  "AWTARCHY_TEST_SKIP_CURSOR_REFRESH=1"
  "AWTARCHY_TEST_TARGET_USER=$TARGET_USER"
  "AWTARCHY_TEST_TARGET_HOME=$home"
  "AWTARCHY_TEST_ARCHIVE=${TMP}/testing-commit.tar.gz"
  "AWTARCHY_TEST_PREVIOUS_ARCHIVE=${TMP}/previous-release.tar.gz"
  "AWTARCHY_TEST_COMMIT=$TEST_COMMIT"
  "AWTARCHY_TEST_CURL_LOG=${TMP}/curl.log"
  "AWTARCHY_TEST_PACKAGE_STATE=$package_state"
  "AWTARCHY_MANAGED_PACKAGES_FILE=$managed_packages"
  "AWTARCHY_TEST_PACMAN_LOG=${TMP}/pacman.log"
  "AWTARCHY_TEST_HYPRCTL_LOG=${TMP}/hyprctl.log"
  "AWTARCHY_TEST_PKILL_LOG=${TMP}/pkill.log"
  "AWTARCHY_TEST_QS_STATE=${TMP}/qs.state"
  "AWTARCHY_TEST_QS_FAIL_FILE=${TMP}/qs.fail"
  "AWTARCHY_TEST_QS_FD_LEAK_FILE=${TMP}/qs-fd-leak"
  "AWTARCHY_TEST_QS_STALL_QUIT=1"
  "AWTARCHY_TEST_QS_KILL_LOG=${TMP}/qs-kill.log"
  "AWTARCHY_TEST_HYPRIDLE_STATE=${TMP}/hypridle.state"
  "AWTARCHY_TEST_HYPRIDLE_PID=${TMP}/hypridle.pid"
  "AWTARCHY_TEST_HYPRIDLE_ARGS=${TMP}/hypridle.args"
  "AWTARCHY_TEST_HYPRIDLE_FD_LEAK_FILE=${TMP}/hypridle-fd-leak"
  "HYPRIDLE_BIN=${fakebin}/hypridle"
  "HYPRIDLE_PGREP_BIN=${fakebin}/pgrep"
  "HYPRIDLE_PKILL_BIN=${fakebin}/pkill"
  "HYPRIDLE_SLEEP_BIN=${fakebin}/sleep"
  "HYPRIDLE_RESTART_LOG=${TMP}/hypridle.log"
  "HYPRIDLE_STOP_ATTEMPTS=3"
  "HYPRIDLE_START_ATTEMPTS=20"
  "HYPRIDLE_START_STABLE_CHECKS=3"
  "HYPRIDLE_WAIT_INTERVAL=0.01"
)

hypr_hash_before="$(sha256sum "$home/.config/hypr/hyprland.lua" | awk '{print $1}')"
packages_hash_before="$(sha256sum "$package_state" | awk '{print $1}')"
env "${update_env[@]}" "$installed_launcher" review \
  >"${TMP}/review.out" 2>&1
[[ $hypr_hash_before == "$(sha256sum "$home/.config/hypr/hyprland.lua" | awk '{print $1}')" ]] \
  || fail "review-only changed the live Hyprland config"
[[ $packages_hash_before == "$(sha256sum "$package_state" | awk '{print $1}')" ]] \
  || fail "review-only changed packages"
grep -Fq 'Review-only mode complete. No files were changed.' "${TMP}/review.out" \
  || fail "review-only did not report its non-mutating result"
grep -Fq 'Reconstructing previous generated baseline from release: v2.0.0-1' \
  "${TMP}/review.out" \
  || fail "updater did not reconstruct the previous baseline from config-version"

env "${update_env[@]}" "$installed_launcher" update \
  >"${TMP}/update.out" 2>&1

grep -Fq -- \
  '-Rns --noconfirm waybar-git fuzzel wlogout mako wofi network-manager-applet blueman' \
  "${TMP}/pacman.log" \
  || fail "updater did not remove the exact installed retired package names"
if grep -Fq -- '-Rns --noconfirm waybar waybar-git' "${TMP}/pacman.log"; then
  fail "updater passed a provider alias to the package removal transaction"
fi

assert_package "$package_state" quickshell
assert_package "$package_state" upower
for pkg in waybar waybar-git fuzzel wlogout mako wofi network-manager-applet blueman; do
  assert_no_package "$package_state" "$pkg"
done
assert_package "$managed_packages" quickshell
assert_package "$managed_packages" upower
assert_no_package "$managed_packages" waybar-git

assert_file "$home/.config/quickshell/awtarchy/shell.qml"
assert_retired_paths_absent "$home"
assert_file "$home/.local/state/awtarchy/quickshell-connectivity-migration-complete"
assert_file "${TMP}/qs.state"
assert_absent "${TMP}/qs-fd-leak"
if [[ ! -s ${TMP}/hypridle.pid ]]; then
  printf '%s\n' 'Hypridle updater diagnostics:' >&2
  grep -F 'Hypridle' "${TMP}/update.out" >&2 || true
  [[ ! -r ${TMP}/hypridle.log ]] || tail -n 20 "${TMP}/hypridle.log" >&2
  fail "missing replacement Hypridle PID: ${TMP}/hypridle.pid"
fi
assert_absent "${TMP}/hypridle-fd-leak"
grep -Fxq -- "-c ${home}/.config/hypr/hypridle.conf" "${TMP}/hypridle.args" \
  || fail "updater did not restart Hypridle with the managed config"
[[ $(<"${TMP}/runtime/awtarchy-quickshell-idle-hidden") == 0 ]] \
  || fail "Hypridle restart did not restore the idle-hidden bar state"
grep -Fq 'Restarting Hypridle to load updated idle callbacks...' "${TMP}/update.out" \
  || fail "updater did not report the Hypridle callback refresh"
grep -Fxq -- '-c awtarchy kill' "${TMP}/qs-kill.log" \
  || fail "Quickshell manager did not force a stalled instance to stop"
grep -Fxq "tag=quickshell-conversion-testing@${TEST_COMMIT}" \
  "$home/.local/state/awtarchy/config-version" \
  || fail "config version did not record the exact testing commit"
grep -Fxq "https://github.com/dillacorn/awtarchy/archive/${TEST_COMMIT}.tar.gz" \
  "${TMP}/curl.log" \
  || fail "updater did not download the exact pinned commit"
grep -Fxq 'https://api.github.com/repos/dillacorn/awtarchy/commits/quickshell-conversion-testing' \
  "${TMP}/curl.log" \
  || fail "testing command did not resolve the configured branch head"
[[ $stable_launcher_hash == "$(sha256sum "$home/.local/bin/awtarchy" | awk '{print $1}')" ]] \
  || fail "successful migration changed the stable launcher"
[[ $stable_runtime_hash == "$(sha256sum "$home/.local/share/awtarchy/awtarchy-runtime.sh" | awk '{print $1}')" ]] \
  || fail "successful migration changed the stable runtime"
grep -Fq '.config/hypr/scripts/quickshell.sh start &' "$home/.config/hypr/hyprland.lua" \
  || fail "updater did not migrate Hyprland startup to Quickshell"
grep -Fq 'local power_menu = "~/.config/hypr/scripts/quickshell_power_menu.sh"' "$home/.config/hypr/hyprland.lua" \
  || fail "updater did not migrate the power menu"
grep -Fq -- '-- personal Hyprland customization survives migration' "$home/.config/hypr/hyprland.lua" \
  || fail "updater lost the user's Hyprland customization"
! grep -Fq 'fuzzel_toggle.sh' "$home/.config/hypr/hyprland.lua" \
  || fail "updater retained the retired launcher in migrated Hyprland"
assert_file "$home/.config/hypr/hyprland.lua.backup"
grep -Fq 'fuzzel_toggle.sh' "$home/.config/hypr/hyprland.lua.backup" \
  || fail "Hyprland migration backup did not preserve the old personalized config"
assert_file "$home/.local/state/awtarchy/migrations/quickshell-hyprland-user.patch"
grep -Fq -- '-- personal Hyprland customization survives migration' \
  "$home/.local/state/awtarchy/migrations/quickshell-hyprland-user.patch" \
  || fail "updater did not record the Hyprland user delta"
grep -Fq 'Recorded personal Hyprland modifications against the previous Awtarchy baseline.' \
  "${TMP}/update.out" \
  || fail "updater did not report recording personal Hyprland modifications"

# Reproduce an already-poisoned migration state: the current beta baseline and
# config-version are installed, but the live personalized Hyprland file is still
# the old Waybar-era copy. The stable command-version is the recovery source.
poisoned_home="${TMP}/poisoned-home"
cp -a -- "$home" "$poisoned_home"
cp -- "$legacy_personal_hypr" "$poisoned_home/.config/hypr/hyprland.lua"
rm -f -- "$poisoned_home/.config/hypr/hyprland.lua.backup" \
  "$poisoned_home/.local/state/awtarchy/migrations/quickshell-hyprland-user.patch"

env \
  "${update_env[@]}" \
  "HOME=$poisoned_home" \
  "AWTARCHY_TEST_TARGET_HOME=$poisoned_home" \
  "$poisoned_home/.local/bin/awtarchy-quickshell" update \
  >"${TMP}/poisoned-update.out" 2>&1

grep -Fq 'Live Hyprland still references the retired Awtarchy shell; reconstructing the previous stable baseline before migration.' \
  "${TMP}/poisoned-update.out" \
  || fail "poisoned baseline recovery did not reconstruct the stable baseline"
grep -Fq '.config/hypr/scripts/quickshell.sh start &' "$poisoned_home/.config/hypr/hyprland.lua" \
  || fail "poisoned baseline recovery did not migrate Hyprland startup"
grep -Fq -- '-- personal Hyprland customization survives migration' "$poisoned_home/.config/hypr/hyprland.lua" \
  || fail "poisoned baseline recovery lost the user's Hyprland customization"
! grep -Fq 'fuzzel_toggle.sh' "$poisoned_home/.config/hypr/hyprland.lua" \
  || fail "poisoned baseline recovery retained the retired launcher"
assert_file "$poisoned_home/.config/hypr/hyprland.lua.backup"
assert_file "$poisoned_home/.local/state/awtarchy/migrations/quickshell-hyprland-user.patch"

# Reproduce the poisoned-baseline failure from an already migrated desktop:
# config-version and baseline are current, but an installed managed UI file is
# still an exact older Awtarchy copy. The updater must repair that stock file,
# preserve an actual QML customization and hyprland.lua, and repeat retired UI
# cleanup even though the migration marker already exists.
stale_system_state="$home/.config/quickshell/awtarchy/SystemState.qml"
personal_launcher="$home/.config/quickshell/awtarchy/Launcher.qml"
repair_history="${TMP}/repair-history.sha256"
printf '%s\n' '// previously shipped Awtarchy SystemState fixture' >"$stale_system_state"
stale_fixture_sha="$(sha256sum "$stale_system_state" | awk '{print $1}')"
printf '%s\t%s\n' \
  "$stale_fixture_sha" \
  '.config/quickshell/awtarchy/SystemState.qml' \
  >"$repair_history"

printf '\n%s\n' '// personal desktop launcher customization' >>"$personal_launcher"
personal_launcher_sha="$(sha256sum "$personal_launcher" | awk '{print $1}')"
printf '%s\n' '-- personal desktop Hyprland policy' >>"$home/.config/hypr/hyprland.lua"
personal_hypr_sha="$(sha256sum "$home/.config/hypr/hyprland.lua" | awk '{print $1}')"

for rel in "${RETIRED_DIRS[@]}"; do
  mkdir -p "${home}/${rel}"
  printf '%s\n' 'retired directory recreated after migration' >"${home}/${rel}/recreated"
  cp -a -- "${home}/${rel}" "${home}/${rel}.backup"
done
for rel in "${RETIRED_FILES[@]}"; do
  mkdir -p "$(dirname "${home}/${rel}")"
  printf '%s\n' 'retired file recreated after migration' >"${home}/${rel}"
  cp -a -- "${home}/${rel}" "${home}/${rel}.backup"
done
printf '%s\n' 'recreated retired launch cache' >"$home/.cache/wofi-drun"
cp -a -- "$home/.cache/wofi-drun" "$home/.cache/wofi-drun.backup"

for pkg in waybar-git fuzzel wlogout mako wofi network-manager-applet blueman; do
  printf '%s\n' "$pkg" >>"$package_state"
  printf '%s\n' "$pkg" >>"$managed_packages"
done
LC_ALL=C sort -u -o "$package_state" "$package_state"
LC_ALL=C sort -u -o "$managed_packages" "$managed_packages"

env \
  "${update_env[@]}" \
  "AWTARCHY_QUICKSHELL_MANAGED_HISTORY=$repair_history" \
  "$installed_launcher" update \
  >"${TMP}/repair-update.out" 2>&1

cmp -s "$stale_system_state" "$ROOT/config/quickshell/awtarchy/SystemState.qml" \
  || fail "updater did not repair a previously shipped stale SystemState.qml"
[[ $personal_launcher_sha == "$(sha256sum "$personal_launcher" | awk '{print $1}')" ]] \
  || fail "updater replaced a genuine Launcher.qml customization"
[[ $personal_hypr_sha == "$(sha256sum "$home/.config/hypr/hyprland.lua" | awk '{print $1}')" ]] \
  || fail "updater replaced the personalized Hyprland configuration on repair"
assert_retired_paths_absent "$home"
for pkg in waybar waybar-git fuzzel wlogout mako wofi network-manager-applet blueman; do
  assert_no_package "$package_state" "$pkg"
  assert_no_package "$managed_packages" "$pkg"
done
grep -Fq 'Recognized 1 previously shipped Awtarchy file(s) as managed updates.' \
  "${TMP}/repair-update.out" \
  || fail "repair update did not report the stale managed-file correction"
latest_audit="$(
  find "$home/.local/state/awtarchy/logs" -maxdepth 1 -type f -name 'update-*.log' \
    -printf '%T@ %p\n' | LC_ALL=C sort -nr | head -n1 | cut -d' ' -f2-
)"
grep -Fq '  .config/quickshell/awtarchy/SystemState.qml' "$latest_audit" \
  || fail "repair audit did not record the corrected SystemState.qml"

failure_packages="${TMP}/failure-packages"
failure_managed="${TMP}/failure-managed-packages"
write_old_package_state "$failure_packages"
cp -- "$failure_packages" "$failure_managed"
: >"${TMP}/failure-curl.log"
: >"${TMP}/failure-pacman.log"
: >"${TMP}/failure-hyprctl.log"
: >"${TMP}/failure-pkill.log"
: >"${TMP}/failure-qs.fail"
mkdir -p "${TMP}/failure-runtime"

failure_env=(
  "HOME=$failure_home"
  "USER=$TARGET_USER"
  "SUDO_USER=$TARGET_USER"
  "PATH=${fakebin}:$PATH"
  "XDG_RUNTIME_DIR=${TMP}/failure-runtime"
  "HYPRLAND_INSTANCE_SIGNATURE=awtarchy-test"
  "AWTARCHY_SKIP_UPDATE_CHECK=1"
  "AWTARCHY_TEST_SKIP_CURSOR_REFRESH=1"
  "AWTARCHY_TEST_TARGET_USER=$TARGET_USER"
  "AWTARCHY_TEST_TARGET_HOME=$failure_home"
  "AWTARCHY_TEST_ARCHIVE=${TMP}/testing-commit.tar.gz"
  "AWTARCHY_TEST_PREVIOUS_ARCHIVE=${TMP}/previous-release.tar.gz"
  "AWTARCHY_TEST_COMMIT=$TEST_COMMIT"
  "AWTARCHY_TEST_CURL_LOG=${TMP}/failure-curl.log"
  "AWTARCHY_TEST_PACKAGE_STATE=$failure_packages"
  "AWTARCHY_MANAGED_PACKAGES_FILE=$failure_managed"
  "AWTARCHY_TEST_PACMAN_LOG=${TMP}/failure-pacman.log"
  "AWTARCHY_TEST_HYPRCTL_LOG=${TMP}/failure-hyprctl.log"
  "AWTARCHY_TEST_PKILL_LOG=${TMP}/failure-pkill.log"
  "AWTARCHY_TEST_QS_STATE=${TMP}/failure-qs.state"
  "AWTARCHY_TEST_QS_FAIL_FILE=${TMP}/failure-qs.fail"
  "AWTARCHY_TEST_QS_FD_LEAK_FILE=${TMP}/failure-qs-fd-leak"
  "AWTARCHY_TEST_ROLLBACK_QS_STATE=${TMP}/rollback-qs.state"
  "AWTARCHY_TEST_ROLLBACK_QS_LOG=${TMP}/rollback-qs.log"
)

set +e
env "${failure_env[@]}" "$failure_home/.local/bin/awtarchy-quickshell" update \
  >"${TMP}/failure-update.out" 2>&1
failure_rc=$?
set -e
(( failure_rc != 0 )) || fail "forced Quickshell startup failure unexpectedly succeeded"
assert_absent "${TMP}/failure-qs-fd-leak"
grep -Fq 'Quickshell did not start successfully. User files were rolled back.' \
  "${TMP}/failure-update.out" \
  || fail "startup failure did not report automatic rollback"
grep -Fq 'fuzzel_toggle.sh' "$failure_home/.config/hypr/hyprland.lua" \
  || fail "rollback did not restore the old personalized Hyprland config"
grep -Fq -- '-- personal Hyprland customization survives migration' "$failure_home/.config/hypr/hyprland.lua" \
  || fail "rollback lost the user's pre-migration Hyprland customization"
grep -Fxq 'custom laptop waybar' "$failure_home/.config/waybar/config" \
  || fail "rollback did not restore the custom Waybar config"
assert_file "$failure_home/.config/waybar.backup/config"
assert_file "$failure_home/.config/fuzzel.backup.20260812-000000/fuzzel.ini"
assert_file "$failure_home/.local/share/applications/hypr_quicksettings.desktop.backup"
assert_file "$failure_home/.local/share/applications/hypr_quicksettings.desktop.backup.20260812-000000"
assert_file "$failure_home/.cache/wofi-drun"
assert_file "$failure_home/.cache/wofi-drun.backup"
assert_absent "$failure_home/.config/quickshell/awtarchy/shell.qml"
assert_file "${TMP}/rollback-qs.state"
[[ $(tail -n1 "${TMP}/rollback-qs.log") == start ]] \
  || fail "rollback did not restart the restored Quickshell manager"
for pkg in waybar-git fuzzel wlogout mako wofi network-manager-applet blueman; do
  assert_package "$failure_packages" "$pkg"
done
assert_package "$failure_packages" quickshell
assert_package "$failure_packages" upower
grep -Fxq 'tag=v2.0.0-1' "$failure_home/.local/state/awtarchy/config-version" \
  || fail "failed migration incorrectly advanced the config version"
[[ $stable_launcher_hash == "$(sha256sum "$failure_home/.local/bin/awtarchy" | awk '{print $1}')" ]] \
  || fail "failed migration changed the stable launcher"
[[ $stable_runtime_hash == "$(sha256sum "$failure_home/.local/share/awtarchy/awtarchy-runtime.sh" | awk '{print $1}')" ]] \
  || fail "failed migration changed the stable runtime"

printf 'Quickshell updater migration tests passed.\n'
