#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/local/libexec/awtarchy/scxctl-helper"
TOGGLE="${ROOT}/config/hypr/scripts/hyprbars_toggle.sh"
TITLE_CARD="${ROOT}/config/quickshell/awtarchy/TitleBarsCard.qml"
AUTO_RELOAD="${ROOT}/config/hypr/scripts/hyprpm-auto-reload.sh"
TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

contains() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || fail "$message"
}

fakebin="$TMPD/fakebin"
mkdir -p -- "$fakebin"

cat >"$fakebin/hyprpm" <<'EOF_HYPRPM'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n ${TEST_HYPRPM_LOG:-} ]]; then
  printf '%s\n' "$*" >>"$TEST_HYPRPM_LOG"
fi
if [[ ${1:-} == list ]]; then
  case "${TEST_PERSISTED:-disabled}" in
    enabled)
      cat <<'EOF_STATE'
→ Repository hyprland-plugins (by hyprwm):
  │ Plugin hyprbars
  └─ enabled: true
EOF_STATE
      ;;
    disabled)
      cat <<'EOF_STATE'
→ Repository hyprland-plugins (by hyprwm):
  │ Plugin hyprbars
  └─ enabled: false
EOF_STATE
      ;;
    absent)
      printf '%s\n' '→ Repository hyprland-plugins (by hyprwm):'
      ;;
    *)
      exit 2
      ;;
  esac
  exit 0
fi
if [[ ${1:-} == reload ]]; then
  rc="${TEST_RELOAD_RC:-0}"
  if [[ $rc == 0 && ${TEST_RELOAD_LOADS:-1} == 1 && -n ${TEST_LOADED_MARKER:-} ]]; then
    : >"$TEST_LOADED_MARKER"
  fi
  exit "$rc"
fi
exit 0
EOF_HYPRPM

cat >"$fakebin/hyprctl" <<'EOF_HYPRCTL'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == plugin && ${2:-} == list ]]; then
  emitted=0
  if [[ ${TEST_LOADED:-0} == 1 \
    || ( ${TEST_PERSISTED:-disabled} == enabled && -n ${TEST_LOADED_MARKER:-} && -f ${TEST_LOADED_MARKER} ) ]]; then
    cat <<'EOF_STATE'
Plugin hyprbars by Vaxry:
    Version: 1.0
EOF_STATE
    emitted=1
  fi
  if [[ ${TEST_OTHER_LOADED:-0} == 1 \
    || ( ${TEST_OTHER_ENABLED:-0} == 1 && -n ${TEST_LOADED_MARKER:-} && -f ${TEST_LOADED_MARKER} ) ]]; then
    cat <<'EOF_STATE'
Plugin hyprexpo by Vaxry:
    Version: 1.0
EOF_STATE
    emitted=1
  fi
  (( emitted == 1 )) || printf '%s\n' 'no plugins loaded'
  exit 0
fi
if [[ ${1:-} == -j && ${2:-} == version ]]; then
  if [[ ${TEST_VERSION_UNAVAILABLE:-0} == 1 ]]; then
    exit 1
  fi
  printf '{"commit":"%s","abiHash":"%s"}\n' \
    "${TEST_RUNNING_COMMIT:-running-commit}" "${TEST_RUNNING_ABI:-running-abi}"
  exit 0
fi
if [[ ${1:-} == notify ]]; then
  if [[ -n ${TEST_HYPRCTL_LOG:-} ]]; then
    printf '%s\n' "$*" >>"$TEST_HYPRCTL_LOG"
  fi
  exit 0
fi
exit 0
EOF_HYPRCTL

cat >"$fakebin/pkgconf" <<'EOF_PKGCONF'
#!/usr/bin/env bash
set -euo pipefail
pc_dir="${PKG_CONFIG_PATH%%:*}"
pc="$pc_dir/hyprland.pc"
[[ -r $pc ]] || exit 1
awk '
  /^[[:space:]]*Cflags:/ {
    sub(/^[[:space:]]*Cflags:[[:space:]]*/, "")
    print
    found = 1
    exit
  }
  END { if (!found) exit 1 }
' "$pc"
EOF_PKGCONF

chmod 0755 "$fakebin/hyprpm" "$fakebin/hyprctl" "$fakebin/pkgconf"

helper_fixture="$TMPD/scxctl-helper"
sed \
  -e "s|^HYPRPM=.*|HYPRPM=\"$fakebin/hyprpm\"|" \
  -e "s|^HYPRCTL=.*|HYPRCTL=\"$fakebin/hyprctl\"|" \
  -e "s@^  (( EUID != 0 )) || die 'hyprbars operations must run as the desktop user'@  :@" \
  "$HELPER" >"$helper_fixture"
chmod 0755 "$helper_fixture"

toggle_fixture="$TMPD/hyprbars_toggle.sh"
sed \
  -e "s|^TRUSTED_HELPER=.*|TRUSTED_HELPER=\"$TMPD/nonexistent-helper\"|" \
  "$TOGGLE" >"$toggle_fixture"
chmod 0755 "$toggle_fixture"

assert_state() {
  local label="$1" command_path="$2" expected="$3" persisted="$4" loaded="$5" repair="${6:-0}"
  local state_home="$TMPD/state-$label-$expected-$persisted-$loaded-$repair"
  local output
  rm -rf -- "$state_home"
  mkdir -p -- "$state_home/awtarchy"
  if [[ $repair == 1 ]]; then
    printf '%s\n' 'reload-failed' >"$state_home/awtarchy/hyprbars-repair-required"
  fi

  if [[ $label == helper ]]; then
    output="$(
      env XDG_STATE_HOME="$state_home" TEST_PERSISTED="$persisted" TEST_LOADED="$loaded" \
        "$command_path" hyprbars-status
    )"
  else
    output="$(
      env PATH="$fakebin:$PATH" XDG_STATE_HOME="$state_home" TEST_PERSISTED="$persisted" TEST_LOADED="$loaded" \
        bash "$command_path" --status
    )"
  fi
  [[ $output == "$expected" ]] \
    || fail "$label returned '$output' for persisted=$persisted loaded=$loaded repair=$repair; expected '$expected'"
}

for target in helper fallback; do
  if [[ $target == helper ]]; then
    path="$helper_fixture"
  else
    path="$toggle_fixture"
  fi

  assert_state "$target" "$path" enabled enabled 1
  assert_state "$target" "$path" not-loaded enabled 0
  assert_state "$target" "$path" repair-required enabled 0 1
  assert_state "$target" "$path" disabled-pending disabled 1
  assert_state "$target" "$path" disabled disabled 0
done

contains "$TITLE_CARD" 'hyprbarsState === "not-loaded"' \
  'Quick Settings does not recognize the persisted-enabled/runtime-missing state'
contains "$TITLE_CARD" 'return "Enabled · Not loaded";' \
  'Quick Settings does not explain that hyprbars is enabled but not loaded'
contains "$TITLE_CARD" 'return "Load";' \
  'Quick Settings does not offer a Load action for enabled-but-not-loaded hyprbars'
contains "$TITLE_CARD" 'hyprbarsState === "repair-required"' \
  'Quick Settings does not recognize the repair-required state'
contains "$TITLE_CARD" 'return "Needs repair";' \
  'Quick Settings does not explain that Title Bars need repair'
contains "$TITLE_CARD" 'return "Repair";' \
  'Quick Settings does not offer a Repair action'
contains "$TITLE_CARD" '|| state === "repair-required"' \
  'Quick Settings status parser drops the repair-required state'
contains "$TITLE_CARD" 'hyprbars-repair' \
  'Quick Settings does not route repair through the trusted helper'

write_hyprpm_state() {
  local root="$1" commit="$2" abi="$3" persisted="$4" other_enabled="${5:-0}"
  mkdir -p "$root/headersRoot/include/hyprland/src" "$root/headersRoot/share/pkgconfig"
  cat >"$root/state.toml" <<EOF_STATE
[state]
hash = "$abi"
dont_warn_install = true
EOF_STATE
  cat >"$root/headersRoot/include/hyprland/src/version.h" <<EOF_HEADER
#define GIT_COMMIT_HASH "$commit"
EOF_HEADER
  cat >"$root/headersRoot/share/pkgconfig/hyprland.pc" <<EOF_PC
Name: Hyprland
Description: test fixture
Version: 1
Cflags: -I$root/headersRoot/include
EOF_PC

  if [[ $persisted != absent ]]; then
    mkdir -p "$root/hyprland-plugins"
    cat >"$root/hyprland-plugins/state.toml" <<EOF_PLUGIN
[repository]
name = "hyprland-plugins"
author = "hyprwm"
url = "https://github.com/hyprwm/hyprland-plugins"

[hyprbars]
enabled = $([[ $persisted == enabled ]] && printf true || printf false)
failed = false
filename = "hyprbars.so"
EOF_PLUGIN
    if [[ $other_enabled == 1 ]]; then
      cat >>"$root/hyprland-plugins/state.toml" <<'EOF_OTHER'

[hyprexpo]
enabled = true
failed = false
filename = "hyprexpo.so"
EOF_OTHER
    fi
  elif [[ $other_enabled == 1 ]]; then
    mkdir -p "$root/hyprland-plugins"
    cat >"$root/hyprland-plugins/state.toml" <<'EOF_PLUGIN'
[repository]
name = "hyprland-plugins"
author = "hyprwm"
url = "https://github.com/hyprwm/hyprland-plugins"

[hyprexpo]
enabled = true
failed = false
filename = "hyprexpo.so"
EOF_PLUGIN
  fi
}

run_session_probe() {
  local name="$1" signature="$2" persisted="$3" loaded="$4" header_commit="$5" header_abi="$6" reload_rc="$7"
  local reload_loads="${8:-1}" version_unavailable="${9:-0}"
  local other_enabled="${10:-0}" other_loaded="${11:-0}"
  local runtime="$TMPD/runtime-$name"
  local home="$TMPD/home-$name"
  local state="$TMPD/hyprpm-$name"
  local hyprpm_log="$TMPD/hyprpm-$name.log"
  local hyprctl_log="$TMPD/hyprctl-$name.log"
  local loaded_marker="$runtime/reloaded"
  mkdir -p -- "$runtime" "$home"
  : >"$hyprpm_log"
  : >"$hyprctl_log"
  write_hyprpm_state "$state" "$header_commit" "$header_abi" "$persisted" "$other_enabled"

  if [[ -n $signature ]]; then
    env \
      PATH="$fakebin:$PATH" \
      HOME="$home" \
      USER="tester" \
      XDG_RUNTIME_DIR="$runtime" \
      XDG_STATE_HOME="$home/.local/state" \
      HYPRLAND_INSTANCE_SIGNATURE="$signature" \
      HYPRPM_STATE_DIR="$state" \
      HYPRPM_AUTO_LOCK_FILE="$runtime/live.lock" \
      TEST_PERSISTED="$persisted" \
      TEST_LOADED="$loaded" \
      TEST_LOADED_MARKER="$loaded_marker" \
      TEST_RELOAD_LOADS="$reload_loads" \
      TEST_VERSION_UNAVAILABLE="$version_unavailable" \
      TEST_OTHER_ENABLED="$other_enabled" \
      TEST_OTHER_LOADED="$other_loaded" \
      TEST_RUNNING_COMMIT="running-commit" \
      TEST_RUNNING_ABI="running-abi" \
      TEST_RELOAD_RC="$reload_rc" \
      TEST_HYPRPM_LOG="$hyprpm_log" \
      TEST_HYPRCTL_LOG="$hyprctl_log" \
      bash "$AUTO_RELOAD"
  else
    env -u HYPRLAND_INSTANCE_SIGNATURE \
      PATH="$fakebin:$PATH" \
      HOME="$home" \
      USER="tester" \
      XDG_RUNTIME_DIR="$runtime" \
      XDG_STATE_HOME="$home/.local/state" \
      HYPRPM_STATE_DIR="$state" \
      HYPRPM_AUTO_LOCK_FILE="$runtime/live.lock" \
      TEST_PERSISTED="$persisted" \
      TEST_LOADED="$loaded" \
      TEST_LOADED_MARKER="$loaded_marker" \
      TEST_RELOAD_LOADS="$reload_loads" \
      TEST_VERSION_UNAVAILABLE="$version_unavailable" \
      TEST_OTHER_ENABLED="$other_enabled" \
      TEST_OTHER_LOADED="$other_loaded" \
      TEST_RUNNING_COMMIT="running-commit" \
      TEST_RUNNING_ABI="running-abi" \
      TEST_RELOAD_RC="$reload_rc" \
      TEST_HYPRPM_LOG="$hyprpm_log" \
      TEST_HYPRCTL_LOG="$hyprctl_log" \
      bash "$AUTO_RELOAD"
  fi

  CASE_RUNTIME="$runtime"
  CASE_HOME="$home"
  CASE_HYPRPM_LOG="$hyprpm_log"
  CASE_HYPRCTL_LOG="$hyprctl_log"
}

run_session_probe disabled session-disabled disabled 0 running-commit running-abi 0
[[ ! -s $CASE_HYPRPM_LOG ]] || fail 'disabled hyprbars triggered hyprpm work at login'

run_session_probe absent session-absent absent 0 running-commit running-abi 0
[[ ! -s $CASE_HYPRPM_LOG ]] || fail 'systems without hyprbars triggered hyprpm work at login'

run_session_probe loaded session-loaded enabled 1 running-commit running-abi 0
[[ ! -s $CASE_HYPRPM_LOG ]] || fail 'already-loaded hyprbars triggered an unnecessary reload'

run_session_probe other-loaded session-other-loaded disabled 0 running-commit running-abi 0 1 0 1 1
[[ ! -s $CASE_HYPRPM_LOG ]] || fail 'already-loaded non-Awtarchy plugin triggered an unnecessary reload'

run_session_probe other-healthy session-other disabled 0 running-commit running-abi 0 1 0 1 0
[[ $(grep -cFx reload "$CASE_HYPRPM_LOG" || true) -eq 1 ]] \
  || fail 'enabled non-Awtarchy hyprpm plugin was no longer reconciled at login'
[[ ! -f $CASE_HOME/.local/state/awtarchy/hyprbars-repair-required ]] \
  || fail 'non-Awtarchy plugin reconciliation created a false hyprbars repair marker'

run_session_probe healthy session-healthy enabled 0 running-commit running-abi 0
[[ $(grep -cFx reload "$CASE_HYPRPM_LOG" || true) -eq 1 ]] \
  || fail 'healthy enabled hyprbars was not reloaded exactly once'
[[ ! -s $CASE_HYPRCTL_LOG ]] || fail 'healthy startup generated an Awtarchy Hyprland notification'
[[ ! -f $CASE_HOME/.local/state/awtarchy/hyprbars-repair-required ]] \
  || fail 'successful healthy reload incorrectly left a repair marker'

# The same Hyprland session must not retry even if the script is invoked again.
env \
  PATH="$fakebin:$PATH" \
  HOME="$CASE_HOME" \
  USER="tester" \
  XDG_RUNTIME_DIR="$CASE_RUNTIME" \
  XDG_STATE_HOME="$CASE_HOME/.local/state" \
  HYPRLAND_INSTANCE_SIGNATURE="session-healthy" \
  HYPRPM_STATE_DIR="$TMPD/hyprpm-healthy" \
  HYPRPM_AUTO_LOCK_FILE="$CASE_RUNTIME/live.lock" \
  TEST_PERSISTED=enabled \
  TEST_LOADED=0 \
  TEST_LOADED_MARKER="$CASE_RUNTIME/reloaded" \
  TEST_RELOAD_LOADS=1 \
  TEST_VERSION_UNAVAILABLE=0 \
  TEST_OTHER_ENABLED=0 \
  TEST_OTHER_LOADED=0 \
  TEST_RUNNING_COMMIT=running-commit \
  TEST_RUNNING_ABI=running-abi \
  TEST_RELOAD_RC=0 \
  TEST_HYPRPM_LOG="$CASE_HYPRPM_LOG" \
  TEST_HYPRCTL_LOG="$CASE_HYPRCTL_LOG" \
  bash "$AUTO_RELOAD"
[[ $(grep -cFx reload "$CASE_HYPRPM_LOG" || true) -eq 1 ]] \
  || fail 'same Hyprland session performed a repeated automatic plugin reload'

run_session_probe abi-mismatch session-abi enabled 0 running-commit old-abi 0
[[ ! -s $CASE_HYPRPM_LOG ]] || fail 'ABI mismatch reached hyprpm reload instead of being contained'
repair_marker="$CASE_HOME/.local/state/awtarchy/hyprbars-repair-required"
[[ -f $repair_marker ]] || fail 'ABI mismatch did not mark hyprbars as needing repair'
grep -Fqx 'abi-mismatch' "$repair_marker" || fail 'ABI mismatch repair reason was not recorded'
[[ ! -s $CASE_HYPRCTL_LOG ]] || fail 'ABI mismatch generated an Awtarchy Hyprland notification'

run_session_probe commit-mismatch session-commit enabled 0 old-commit running-abi 0
[[ ! -s $CASE_HYPRPM_LOG ]] || fail 'header commit mismatch reached hyprpm reload instead of being contained'
repair_marker="$CASE_HOME/.local/state/awtarchy/hyprbars-repair-required"
[[ -f $repair_marker ]] || fail 'header commit mismatch did not mark hyprbars as needing repair'
grep -Fqx 'headers-mismatch' "$repair_marker" || fail 'header commit mismatch repair reason was not recorded'

run_session_probe other-abi-mismatch session-other-abi disabled 0 running-commit old-abi 0 1 0 1 0
[[ ! -s $CASE_HYPRPM_LOG ]] || fail 'stale headers for a non-Awtarchy plugin reached hyprpm reload'
repair_marker="$CASE_HOME/.local/state/awtarchy/hyprbars-repair-required"
[[ ! -f $repair_marker ]] || fail 'non-Awtarchy plugin mismatch created a false hyprbars repair marker'

run_session_probe reload-failure session-fail enabled 0 running-commit running-abi 5
[[ $(grep -cFx reload "$CASE_HYPRPM_LOG" || true) -eq 1 ]] \
  || fail 'healthy preflight did not attempt one reload before containing failure'
repair_marker="$CASE_HOME/.local/state/awtarchy/hyprbars-repair-required"
[[ -f $repair_marker ]] || fail 'reload failure did not mark hyprbars as needing repair'
grep -Fqx 'reload-failed' "$repair_marker" || fail 'reload failure repair reason was not recorded'
[[ ! -s $CASE_HYPRCTL_LOG ]] || fail 'reload failure emitted an extra Awtarchy Hyprland notification'

run_session_probe reload-not-loaded session-not-loaded enabled 0 running-commit running-abi 0 0
[[ $(grep -cFx reload "$CASE_HYPRPM_LOG" || true) -eq 1 ]] \
  || fail 'reload-not-loaded case did not attempt exactly one reload'
repair_marker="$CASE_HOME/.local/state/awtarchy/hyprbars-repair-required"
[[ -f $repair_marker ]] || fail 'successful hyprpm reload without a loaded plugin did not request repair'
grep -Fqx 'reload-not-loaded' "$repair_marker" \
  || fail 'reload-not-loaded repair reason was not recorded'
[[ ! -s $CASE_HYPRCTL_LOG ]] || fail 'reload-not-loaded emitted an extra Awtarchy Hyprland notification'

run_session_probe version-unavailable session-version enabled 0 running-commit running-abi 0 1 1
[[ ! -s $CASE_HYPRPM_LOG ]] || fail 'unknown running Hyprland version reached hyprpm reload'
repair_marker="$CASE_HOME/.local/state/awtarchy/hyprbars-repair-required"
[[ ! -f $repair_marker ]] || fail 'transient Hyprland version failure was mislabeled as a plugin repair'

run_session_probe live-base session-live enabled 1 running-commit running-abi 0
[[ ! -s $CASE_HYPRPM_LOG ]] || fail 'live-reload fixture unexpectedly reloaded during initial already-loaded state'
env \
  PATH="$fakebin:$PATH" \
  HOME="$CASE_HOME" \
  USER="tester" \
  XDG_RUNTIME_DIR="$CASE_RUNTIME" \
  XDG_STATE_HOME="$CASE_HOME/.local/state" \
  HYPRLAND_INSTANCE_SIGNATURE="session-live" \
  HYPRPM_STATE_DIR="$TMPD/hyprpm-live-base" \
  HYPRPM_AUTO_LOCK_FILE="$CASE_RUNTIME/live.lock" \
  HYPRPM_AUTO_LIVE_RELOAD=1 \
  TEST_PERSISTED=enabled \
  TEST_LOADED=1 \
  TEST_LOADED_MARKER="$CASE_RUNTIME/reloaded" \
  TEST_RELOAD_LOADS=1 \
  TEST_VERSION_UNAVAILABLE=0 \
  TEST_OTHER_ENABLED=0 \
  TEST_OTHER_LOADED=0 \
  TEST_RUNNING_COMMIT=running-commit \
  TEST_RUNNING_ABI=running-abi \
  TEST_RELOAD_RC=0 \
  TEST_HYPRPM_LOG="$CASE_HYPRPM_LOG" \
  TEST_HYPRCTL_LOG="$CASE_HYPRCTL_LOG" \
  bash "$AUTO_RELOAD"
[[ $(grep -cFx reload "$CASE_HYPRPM_LOG" || true) -eq 1 ]] \
  || fail 'explicit HYPRPM_AUTO_LIVE_RELOAD=1 behavior was not preserved'

run_session_probe no-session "" enabled 0 running-commit running-abi 0
[[ ! -s $CASE_HYPRPM_LOG ]] || fail 'invocation without a Hyprland session signature performed a live reload'

contains "$HELPER" 'hyprbars-repair)' \
  'trusted helper does not expose the repair operation'
contains "$HELPER" '["update", "-f"]' \
  'trusted helper repair does not force-refresh Hyprland headers/plugins'
contains "$HELPER" 'hyprbars-repair-required' \
  'trusted helper does not share the repair marker state'

printf '%s\n' 'PASS: hyprbars state, startup reconciliation, and repair flow stay synchronized.'
