#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MOUSE_SCRIPT="${AWTARCHY_TEST_MOUSE_SCRIPT:-${ROOT}/config/hypr/scripts/toggle_mouse_submap.sh}"
VOLUME_SCRIPT="${AWTARCHY_TEST_VOLUME_SCRIPT:-${ROOT}/config/hypr/scripts/quickshell_volume.sh}"
SYSTEM_STATE="${ROOT}/config/quickshell/awtarchy/SystemState.qml"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
TMP="$(mktemp -d)"
SUBMAP_RUNTIME="${TMP}/submap-runtime"
SUBMAP_FILE="${SUBMAP_RUNTIME}/awtarchy-hypr-submap"
volume_pids=()

cleanup() {
  if [[ -n ${volume_release_marker:-} ]]; then
    : >"$volume_release_marker" 2>/dev/null || true
  fi
  for volume_pid in "${volume_pids[@]}"; do
    kill "$volume_pid" >/dev/null 2>&1 || true
    wait "$volume_pid" 2>/dev/null || true
  done
  rm -rf -- "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

fakebin="${TMP}/mouse-bin"
config_home="${TMP}/config"
hyprctl_log="${TMP}/hyprctl.log"
runtime_marker="${TMP}/runtime-rules-ran"
mkdir -p "$fakebin" "${config_home}/hypr/scripts" "$SUBMAP_RUNTIME"

cat >"${fakebin}/hyprctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
if [[ ${1:-} == submap ]]; then
  printf '%s\n' reset
fi
EOF
chmod 0755 "${fakebin}/hyprctl"

cat >"${fakebin}/notify-send" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 0755 "${fakebin}/notify-send"

cat >"${config_home}/hypr/scripts/quickshell_runtime_rules.sh" <<'EOF'
#!/usr/bin/env bash
: >"$RUNTIME_RULES_MARKER"
EOF
chmod 0755 "${config_home}/hypr/scripts/quickshell_runtime_rules.sh"

for submap_source in \
  "$MOUSE_SCRIPT" \
  "${ROOT}/config/hypr/scripts/hypr_quicksettings_core.sh" \
  "${ROOT}/config/hypr/hyprland.lua" \
  "${ROOT}/config/quickshell/awtarchy/Bar.qml" \
  "${ROOT}/local/share/applications/vm_submap.desktop" \
  "${ROOT}/local/share/applications/noalt_submap.desktop"
do
  ! grep -Fq '/tmp/hypr-submap' "$submap_source" \
    || fail "${submap_source#"${ROOT}/"} still uses shared /tmp submap state"
  grep -Fq 'awtarchy-hypr-submap' "$submap_source" \
    || fail "${submap_source#"${ROOT}/"} does not use the per-user submap state"
done

if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate \
    "${ROOT}/local/share/applications/vm_submap.desktop" \
    "${ROOT}/local/share/applications/noalt_submap.desktop"
fi

XDG_RUNTIME_DIR="$SUBMAP_RUNTIME" \
PATH="${fakebin}:$PATH" \
  XDG_CONFIG_HOME="$config_home" \
  HYPRCTL_LOG="$hyprctl_log" \
  RUNTIME_RULES_MARKER="$runtime_marker" \
  bash "$MOUSE_SCRIPT" on

[[ $(<"$SUBMAP_FILE") == mouse ]] \
  || fail "mouse mode did not record its active submap"

if grep -q '^eval ' "$hyprctl_log"; then
  fail "mouse mode mutated live Hyprland bindings"
fi

grep -Fxq 'dispatch hl.dsp.submap("mouse")' "$hyprctl_log" \
  || fail "mouse mode did not dispatch the declared mouse submap"

XDG_RUNTIME_DIR="$SUBMAP_RUNTIME" \
  PATH="${fakebin}:$PATH" \
  XDG_CONFIG_HOME="$config_home" \
  HYPRCTL_LOG="$hyprctl_log" \
  RUNTIME_RULES_MARKER="$runtime_marker" \
  bash "$MOUSE_SCRIPT" reset

[[ ! -s $SUBMAP_FILE ]] \
  || fail "reset did not clear the recorded mouse submap"

grep -Fxq 'dispatch hl.dsp.submap("reset")' "$hyprctl_log" \
  || fail "reset did not dispatch the declared reset submap"

if grep -q '^eval ' "$hyprctl_log"; then
  fail "reset mutated live Hyprland bindings"
fi

[[ ! -e $runtime_marker ]] \
  || fail "reset reinstalled runtime pointer bindings during the click"

grep -Fq 'property bool idleReconcilePending: false' "$SYSTEM_STATE" \
  || fail "idle inhibitor does not track pending backend reconciliation"
grep -Fq 'root.idleInhibited = !root.idleInhibited;' "$SYSTEM_STATE" \
  || fail "idle inhibitor click does not update the existing UI state immediately"
grep -Fq 'idleToggleProcess.exec([idleScript, "toggle"]);' "$SYSTEM_STATE" \
  || fail "idle inhibitor toggle is not managed by a QML Process"
grep -Fq 'if (idleReconcilePending)' "$SYSTEM_STATE" \
  || fail "idle status does not reject stale results during reconciliation"
grep -Fq 'root.refreshIdleAfterToggle();' "$SYSTEM_STATE" \
  || fail "idle toggle completion does not reconcile with authoritative backend status"
! grep -Fq 'refreshIdleTimer' "$SYSTEM_STATE" \
  || fail "idle inhibitor still waits on the fixed refresh timer"
! grep -Fq 'interval: 350' "$SYSTEM_STATE" \
  || fail "idle inhibitor still contains the 350 ms visual delay"

grep -Fq 'repair_v347_idle_inhibitor_feedback_target()' "$RUNTIME" \
  || fail "runtime is missing the v3.4.7 idle-inhibitor post-release repair"
# Match literal runtime source; $tag must not expand in this test pattern.
# shellcheck disable=SC2016
grep -Fq '[[ "$tag" == "v3.4.7" ]] || return 0' "$RUNTIME" \
  || fail "v3.4.7 idle-inhibitor repair is not scoped to the published release"
# Match literal runtime source; $target_home and $tag must remain literal.
# shellcheck disable=SC2016
grep -Fq 'repair_v347_idle_inhibitor_feedback_target "$target_home" "$tag"' "$RUNTIME" \
  || fail "runtime does not apply the v3.4.7 idle-inhibitor repair to the generated target"

# Locate literal runtime source calls; these variables belong to the inspected source.
# shellcheck disable=SC2016
prepare_line="$(grep -nF 'prepare_quickshell_update_target "$target_home"' "$RUNTIME" | head -n1 | cut -d: -f1)"
# shellcheck disable=SC2016
repair_line="$(grep -nF 'repair_v347_idle_inhibitor_feedback_target "$target_home" "$tag"' "$RUNTIME" | head -n1 | cut -d: -f1)"
# shellcheck disable=SC2016
baseline_line="$(grep -nF 'bootstrap_previous_baseline "$active_theme"' "$RUNTIME" | head -n1 | cut -d: -f1)"
[[ "$prepare_line" =~ ^[0-9]+$ && "$repair_line" =~ ^[0-9]+$ && "$baseline_line" =~ ^[0-9]+$ ]] \
  || fail "could not locate v3.4.7 idle-inhibitor target-repair ordering"
(( prepare_line < repair_line && repair_line < baseline_line )) \
  || fail "v3.4.7 idle-inhibitor target repair must run before baseline comparison"

v347_target_home="${TMP}/v347-target"
v346_target_home="${TMP}/v346-control-target"
v347_rel='.config/quickshell/awtarchy/SystemState.qml'
v347_original="${TMP}/v347-original-SystemState.qml"
mkdir -p "${v347_target_home}/$(dirname "$v347_rel")" "${v346_target_home}/$(dirname "$v347_rel")"
git -C "$ROOT" show v3.4.7:config/quickshell/awtarchy/SystemState.qml >"$v347_original" \
  || fail "v3.4.7 SystemState fixture is unavailable"
cp -- "$v347_original" "${v347_target_home}/${v347_rel}"
cp -- "$v347_original" "${v346_target_home}/${v347_rel}"

repair_definition="$(
  sed -n '/^repair_v347_idle_inhibitor_feedback_target() {/,/^prepare_quickshell_update_target() {/p' "$RUNTIME" |
    sed '$d'
)"
[[ -n "$repair_definition" ]] || fail "could not extract v3.4.7 idle-inhibitor repair function"
log() { :; }
die() { fail "$*"; }
eval "$repair_definition"

repair_v347_idle_inhibitor_feedback_target "$v347_target_home" v3.4.7
grep -Fq 'property bool idleReconcilePending: false' "${v347_target_home}/${v347_rel}" \
  || fail "v3.4.7 post-release repair does not add pending backend reconciliation"
grep -Fq 'root.idleInhibited = !root.idleInhibited;' "${v347_target_home}/${v347_rel}" \
  || fail "v3.4.7 post-release repair does not add immediate visual feedback"
grep -Fq 'idleToggleProcess.exec([idleScript, "toggle"]);' "${v347_target_home}/${v347_rel}" \
  || fail "v3.4.7 post-release repair does not use the managed toggle process"
! grep -Fq 'property string idleMode:' "${v347_target_home}/${v347_rel}" \
  || fail "v3.4.7 post-release repair unexpectedly backports later idle-mode behavior"

repair_v347_idle_inhibitor_feedback_target "$v346_target_home" v3.4.6
cmp -s "${v346_target_home}/${v347_rel}" "$v347_original" \
  || fail "v3.4.7 post-release repair changed another release target"

volume_bin="${TMP}/volume-bin"
volume_state="${TMP}/volume-state"
volume_runtime="${TMP}/runtime"
volume_first_writer="${TMP}/volume-first-writer"
volume_first_writer_ready="${TMP}/volume-first-writer-ready"
volume_release_marker="${TMP}/volume-release-first-writer"
volume_lock_file="${volume_runtime}/awtarchy/quickshell-volume.lock"
mkdir -p "$volume_bin" "${volume_runtime}/awtarchy"
printf '%s\n' '90' >"$volume_state"

cat >"${volume_bin}/wpctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  inspect)
    printf '%s\n' \
      '  * device.id = "42"' \
      '  * card.profile.device = "7"'
    ;;
  set-volume)
    [[ ${2:-} == @DEFAULT_AUDIO_SINK@ ]] || exit 3
    [[ ${4:-} == --limit ]] || exit 4
    case "${5:-}" in
      1.0) limit_percent=100 ;;
      2.0) limit_percent=200 ;;
      *) exit 5 ;;
    esac

    if mkdir "$VOLUME_FIRST_WRITER" 2>/dev/null; then
      : >"$VOLUME_FIRST_WRITER_READY"
      for _ in {1..500}; do
        [[ -e $VOLUME_RELEASE_MARKER ]] && break
        sleep 0.01
      done
      [[ -e $VOLUME_RELEASE_MARKER ]] || exit 6
    fi

    current="$(<"$VOLUME_STATE_FILE")"
    case "${3:-}" in
      5%+) target=$((current + 5)) ;;
      *%) target="${3%%%}" ;;
      *) exit 7 ;;
    esac
    ((target > limit_percent)) && target=$limit_percent
    printf '%s\n' "$target" >"${VOLUME_STATE_FILE}.$$"
    mv -f -- "${VOLUME_STATE_FILE}.$$" "$VOLUME_STATE_FILE"
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod 0755 "${volume_bin}/wpctl"

cat >"${volume_bin}/pw-dump" <<'EOF'
#!/usr/bin/env bash
case "$(<"$VOLUME_STATE_FILE")" in
  90) raw='0.729000000' ;;
  95) raw='0.857375000' ;;
  100) raw='1.000000000' ;;
  *) exit 2 ;;
esac
printf '[{"info":{"params":{"Route":[{"index":1,"device":7,"props":{"channelVolumes":[%s,%s],"mute":false}}]}}}]\n' \
  "$raw" "$raw"
EOF
chmod 0755 "${volume_bin}/pw-dump"

cat >"${volume_bin}/pw-cli" <<'EOF'
#!/usr/bin/env bash
if mkdir "$VOLUME_FIRST_WRITER" 2>/dev/null; then
  : >"$VOLUME_FIRST_WRITER_READY"
  for _ in {1..500}; do
    [[ -e $VOLUME_RELEASE_MARKER ]] && break
    sleep 0.01
  done
  [[ -e $VOLUME_RELEASE_MARKER ]] || exit 3
fi
# The attached iFi/PipeWire trace accepts direct Route writes with exit 0,
# but silently ignores writes that raise channelVolumes.
exit 0
EOF
chmod 0755 "${volume_bin}/pw-cli"

PATH="${volume_bin}:$PATH" \
  XDG_RUNTIME_DIR="$volume_runtime" \
  VOLUME_STATE_FILE="$volume_state" \
  VOLUME_FIRST_WRITER="$volume_first_writer" \
  VOLUME_FIRST_WRITER_READY="$volume_first_writer_ready" \
  VOLUME_RELEASE_MARKER="$volume_release_marker" \
  "$VOLUME_SCRIPT" up 100 &
first_volume_pid=$!
volume_pids+=("$first_volume_pid")

for _ in {1..500}; do
  [[ -e $volume_first_writer_ready ]] && break
  kill -0 "$first_volume_pid" >/dev/null 2>&1 \
    || fail "first volume adjustment exited before reaching its writer"
  sleep 0.01
done
[[ -e $volume_first_writer_ready ]] \
  || fail "first volume adjustment did not reach its writer"

if flock -n "$volume_lock_file" true; then
  : >"$volume_release_marker"
  wait "$first_volume_pid" 2>/dev/null || true
  volume_pids=()
  fail "volume adjustment did not hold its read/modify/write lock"
fi

PATH="${volume_bin}:$PATH" \
  XDG_RUNTIME_DIR="$volume_runtime" \
  VOLUME_STATE_FILE="$volume_state" \
  VOLUME_FIRST_WRITER="$volume_first_writer" \
  VOLUME_FIRST_WRITER_READY="$volume_first_writer_ready" \
  VOLUME_RELEASE_MARKER="$volume_release_marker" \
  "$VOLUME_SCRIPT" up 100 &
second_volume_pid=$!
volume_pids+=("$second_volume_pid")

: >"$volume_release_marker"

wait "$first_volume_pid" \
  || fail "first concurrent volume adjustment failed"
wait "$second_volume_pid" \
  || fail "second concurrent volume adjustment failed"
volume_pids=()

[[ $(<"$volume_state") == 100 ]] \
  || fail "concurrent volume-up events did not reach 100 percent"

PATH="${volume_bin}:$PATH" \
  XDG_RUNTIME_DIR="$volume_runtime" \
  VOLUME_STATE_FILE="$volume_state" \
  VOLUME_FIRST_WRITER="$volume_first_writer" \
  VOLUME_FIRST_WRITER_READY="$volume_first_writer_ready" \
  VOLUME_RELEASE_MARKER="$volume_release_marker" \
  "$VOLUME_SCRIPT" set 250

[[ $(<"$volume_state") == 200 ]] \
  || fail "absolute volume set did not preserve the 200 percent safety cap"

printf '%s\n' "Bar control action regression test passed."
