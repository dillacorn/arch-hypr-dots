#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MOUSE_SCRIPT="${AWTARCHY_TEST_MOUSE_SCRIPT:-${ROOT}/config/hypr/scripts/toggle_mouse_submap.sh}"
VOLUME_SCRIPT="${AWTARCHY_TEST_VOLUME_SCRIPT:-${ROOT}/config/hypr/scripts/quickshell_volume.sh}"
TMP="$(mktemp -d)"
SUBMAP_FILE="/tmp/hypr-submap"
SUBMAP_BACKUP="${TMP}/hypr-submap.backup"
submap_existed=false
volume_pids=()

cleanup() {
  if [[ -n ${volume_release_marker:-} ]]; then
    : >"$volume_release_marker" 2>/dev/null || true
  fi
  for volume_pid in "${volume_pids[@]}"; do
    kill "$volume_pid" >/dev/null 2>&1 || true
    wait "$volume_pid" 2>/dev/null || true
  done
  rm -f -- "$SUBMAP_FILE"
  if [[ $submap_existed == true ]]; then
    cp -a -- "$SUBMAP_BACKUP" "$SUBMAP_FILE"
  fi
  rm -rf -- "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

if [[ -e $SUBMAP_FILE || -L $SUBMAP_FILE ]]; then
  cp -a -- "$SUBMAP_FILE" "$SUBMAP_BACKUP"
  submap_existed=true
fi
rm -f -- "$SUBMAP_FILE"

fakebin="${TMP}/mouse-bin"
config_home="${TMP}/config"
hyprctl_log="${TMP}/hyprctl.log"
runtime_marker="${TMP}/runtime-rules-ran"
mkdir -p "$fakebin" "${config_home}/hypr/scripts"

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

volume_bin="${TMP}/volume-bin"
volume_state="${TMP}/volume-state"
fallback_marker="${TMP}/volume-fallback-ran"
volume_runtime="${TMP}/runtime"
volume_first_writer="${TMP}/volume-first-writer"
volume_first_writer_ready="${TMP}/volume-first-writer-ready"
volume_release_marker="${TMP}/volume-release-first-writer"
volume_lock_file="${volume_runtime}/awtarchy/quickshell-volume.lock"
mkdir -p "$volume_bin" "${volume_runtime}/awtarchy"
printf '%s\n' '0.729000000' >"$volume_state"

cat >"${volume_bin}/wpctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  inspect)
    printf '%s\n' \
      '  * device.id = "42"' \
      '  * card.profile.device = "7"'
    ;;
  set-volume)
    : >"$VOLUME_FALLBACK_MARKER"
    exit 1
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod 0755 "${volume_bin}/wpctl"

cat >"${volume_bin}/pw-dump" <<'EOF'
#!/usr/bin/env bash
raw="$(<"$VOLUME_STATE_FILE")"
printf '[{"info":{"params":{"Route":[{"index":1,"device":7,"props":{"channelVolumes":[%s,%s],"mute":false}}]}}}]\n' \
  "$raw" "$raw"
EOF
chmod 0755 "${volume_bin}/pw-dump"

cat >"${volume_bin}/pw-cli" <<'EOF'
#!/usr/bin/env bash
raw="$(sed -nE 's/.*channelVolumes: \[ ([0-9.]+).*/\1/p' <<<"${4:-}")"
[[ -n $raw ]] || exit 2
if mkdir "$VOLUME_FIRST_WRITER" 2>/dev/null; then
  : >"$VOLUME_FIRST_WRITER_READY"
  for _ in {1..500}; do
    [[ -e $VOLUME_RELEASE_MARKER ]] && break
    sleep 0.01
  done
  [[ -e $VOLUME_RELEASE_MARKER ]] || exit 3
fi
printf '%s\n' "$raw" >"${VOLUME_STATE_FILE}.$$"
mv -f -- "${VOLUME_STATE_FILE}.$$" "$VOLUME_STATE_FILE"
EOF
chmod 0755 "${volume_bin}/pw-cli"

PATH="${volume_bin}:$PATH" \
  XDG_RUNTIME_DIR="$volume_runtime" \
  VOLUME_STATE_FILE="$volume_state" \
  VOLUME_FALLBACK_MARKER="$fallback_marker" \
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
  VOLUME_FALLBACK_MARKER="$fallback_marker" \
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

[[ $(<"$volume_state") == 1.000000000 ]] \
  || fail "concurrent volume-up events did not reach 100 percent"
[[ ! -e $fallback_marker ]] \
  || fail "route-aware volume control unexpectedly used its fallback"

printf '%s\n' "Bar control action regression test passed."
