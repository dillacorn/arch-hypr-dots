#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
BASHRC="${ROOT}/bashrc"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
TMP="$(mktemp -d)"
FAKEBIN="${TMP}/bin"
HOME_DIR="${TMP}/home"
HELPER_LOG="${TMP}/helper.log"

cleanup() {
  rm -rf -- "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p -- "$FAKEBIN" "$HOME_DIR"
: >"$HELPER_LOG"

cat >"${FAKEBIN}/yay" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'yay\t%s\n' "$*" >>"${AWTARCHY_TEST_HELPER_LOG:?}"
EOF

cat >"${FAKEBIN}/paru" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'paru\t%s\n' "$*" >>"${AWTARCHY_TEST_HELPER_LOG:?}"
EOF

cat >"${FAKEBIN}/aur-scan" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'aur-scan\t%s\n' "$*" >>"${AWTARCHY_TEST_HELPER_LOG:?}"
if [[ ${1:-} == -h ]]; then
  printf '%s\n' 'UPSTREAM AUR-SCAN HELP'
fi
EOF

cat >"${FAKEBIN}/pacman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'pacman\t%s\n' "$*" >>"${AWTARCHY_TEST_HELPER_LOG:?}"
if [[ ${1:-} == -Qm ]]; then
  printf '%s\n' 'awtwall 1.0-1'
fi
EOF

cat >"${FAKEBIN}/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sudo\t%s\n' "$*" >>"${AWTARCHY_TEST_HELPER_LOG:?}"
EOF

chmod 0755 "${FAKEBIN}/"*

run_shell() {
  local command="$1"
  PATH="${FAKEBIN}:/usr/bin:/bin" \
  HOME="$HOME_DIR" \
  AWTARCHY_TEST_HELPER_LOG="$HELPER_LOG" \
    bash --noprofile --norc -ic "source '$BASHRC'; $command"
}

assert_logged() {
  local expected="$1"
  grep -Fxq -- "$expected" "$HELPER_LOG" \
    || fail "missing helper invocation: $expected"
}

assert_blocked() {
  local command="$1" output status
  : >"$HELPER_LOG"
  set +e
  output="$(run_shell "$command" 2>&1)"
  status=$?
  set -e
  (( status != 0 )) || fail "package-changing helper command was allowed: $command"
  [[ ! -s "$HELPER_LOG" ]] || fail "blocked helper command reached the external helper: $command"
  grep -Fq 'aur-scan install' <<<"$output" \
    || fail "blocked helper command did not direct the user to aur-scan install: $command"
}

bash -n "$BASHRC"

for retired in aurguard aurverify aurinstall aurup aurunsafe aurcheck aurguardtest aurremove auruninstall; do
  if grep -Eq "^${retired}[[:space:]]*\\(\\)" "$BASHRC"; then
    fail "retired AurGuard command remains in bashrc: $retired"
  fi
done

if grep -Fq '_AUR_GUARD_' "$BASHRC"; then
  fail 'AurGuard implementation state remains in bashrc'
fi
if grep -Fq '_aur_guard_' "$BASHRC"; then
  fail 'AurGuard implementation helpers remain in bashrc'
fi

grep -Fq 'aur-scan install' "$BASHRC" \
  || fail 'yay/paru transaction policy does not direct installs to aur-scan install'
grep -Fq 'command aur-scan -h' "$BASHRC" \
  || fail 'aurhelp does not delegate to upstream aur-scan -h'

for command in \
  'yay -Qm' \
  'yay -Qiu' \
  'yay -Ss example' \
  'yay -Si example' \
  'yay -R example' \
  'yay -Rns example' \
  'yay --remove example' \
  'yay -Sp example' \
  'yay --version' \
  'paru -Qm' \
  'paru -R example' \
  'paru -Rns example' \
  'paru --version'
do
  : >"$HELPER_LOG"
  run_shell "$command" >/dev/null 2>&1 \
    || fail "read-only helper command was rejected: $command"
  helper="${command%% *}"
  args="${command#* }"
  assert_logged "${helper}"$'\t'"${args}"
done

assert_blocked 'yay'
assert_blocked 'yay -S example'
assert_blocked 'yay -Syu'
assert_blocked 'yay -Sc'
assert_blocked 'yay -Yc'
assert_blocked 'yay -D --asdeps example'
assert_blocked 'yay -G example'
assert_blocked 'yay -R example -S other'

: >"$HELPER_LOG"
help_output="$(run_shell 'aurhelp' 2>/dev/null)" \
  || fail 'aurhelp failed'
grep -Fq 'UPSTREAM AUR-SCAN HELP' <<<"$help_output" \
  || fail 'aurhelp did not return upstream aur-scan help'
assert_logged $'aur-scan\t-h'

: >"$HELPER_LOG"
aur_output="$(run_shell 'aur' 2>/dev/null)" \
  || fail 'aur failed'
grep -Fq 'UPSTREAM AUR-SCAN HELP' <<<"$aur_output" \
  || fail 'aur did not delegate to upstream aur-scan help'
assert_logged $'aur-scan\t-h'

: >"$HELPER_LOG"
installed_output="$(run_shell 'aurinstalled' 2>/dev/null)" \
  || fail 'aurinstalled failed'
grep -Fq 'awtwall 1.0-1' <<<"$installed_output" \
  || fail 'aurinstalled did not report pacman foreign packages'
assert_logged $'pacman\t-Qm'

: >"$HELPER_LOG"
run_shell 'sysupdate' >/dev/null 2>&1 \
  || fail 'sysupdate failed'
assert_logged $'sudo\tpacman -Syu'

grep -Fq 'repair_v350_aur_helper_policy_target()' "$RUNTIME" \
  || fail 'runtime is missing the v3.5.0 AUR helper post-release repair'
# shellcheck disable=SC2016
grep -Fq '[[ "$tag" == "v3.5.0" ]] || return 0' "$RUNTIME" \
  || fail 'v3.5.0 AUR helper repair is not scoped to the published release'
# shellcheck disable=SC2016
grep -Fq 'repair_v350_aur_helper_policy_target "$target_home" "$tag"' "$RUNTIME" \
  || fail 'runtime does not apply the v3.5.0 AUR helper repair to the generated target'

# shellcheck disable=SC2016
prepare_line="$(grep -nF 'prepare_quickshell_update_target "$target_home"' "$RUNTIME" | head -n1 | cut -d: -f1)"
# shellcheck disable=SC2016
repair_line="$(grep -nF 'repair_v350_aur_helper_policy_target "$target_home" "$tag"' "$RUNTIME" | head -n1 | cut -d: -f1)"
# shellcheck disable=SC2016
baseline_line="$(grep -nF 'bootstrap_previous_baseline "$active_theme"' "$RUNTIME" | head -n1 | cut -d: -f1)"
[[ "$prepare_line" =~ ^[0-9]+$ && "$repair_line" =~ ^[0-9]+$ && "$baseline_line" =~ ^[0-9]+$ ]] \
  || fail 'could not locate v3.5.0 AUR helper target-repair ordering'
(( prepare_line < repair_line && repair_line < baseline_line )) \
  || fail 'v3.5.0 AUR helper target repair must run before baseline comparison'

v350_target_home="${TMP}/v350-target"
control_target_home="${TMP}/v350-control-target"
v350_original="${TMP}/v350-original-bashrc"
mkdir -p "$v350_target_home" "$control_target_home"
git -C "$ROOT" show v3.5.0:bashrc >"$v350_original" \
  || fail 'v3.5.0 bashrc fixture is unavailable'
cp -- "$v350_original" "${v350_target_home}/.bashrc"
cp -- "$v350_original" "${control_target_home}/.bashrc"

repair_definition="$(
  sed -n '/^repair_v350_aur_helper_policy_target() {/,/^prepare_quickshell_update_target() {/p' "$RUNTIME" |
    sed '$d'
)"
[[ -n "$repair_definition" ]] || fail 'could not extract v3.5.0 AUR helper repair function'
log() { :; }
die() { fail "$*"; }
eval "$repair_definition"

repair_v350_aur_helper_policy_target "$v350_target_home" v3.5.0
cmp -s "${v350_target_home}/.bashrc" "$BASHRC" \
  || fail 'v3.5.0 post-release repair does not produce the current fixed bashrc'

repair_v350_aur_helper_policy_target "$control_target_home" v3.4.7
cmp -s "${control_target_home}/.bashrc" "$v350_original" \
  || fail 'v3.5.0 AUR helper post-release repair changed another release target'

printf '%s\n' 'PASS: bashrc delegates AUR installation/help to aur-scanner while allowing read-only yay/paru queries and explicit package removal.'
