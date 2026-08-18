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
if [[ -n ${TEST_HYPRPM_LOG:-} ]]; then
  printf '%s\n' "$*" >>"$TEST_HYPRPM_LOG"
fi
exit 0
EOF_HYPRPM

cat >"$fakebin/hyprctl" <<'EOF_HYPRCTL'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == plugin && ${2:-} == list ]]; then
  if [[ ${TEST_LOADED:-0} == 1 ]]; then
    cat <<'EOF_STATE'
Plugin hyprbars by Vaxry:
    Version: 1.0
EOF_STATE
  else
    printf '%s\n' 'no plugins loaded'
  fi
fi
exit 0
EOF_HYPRCTL
chmod 0755 "$fakebin/hyprpm" "$fakebin/hyprctl"

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
  local label="$1" command_path="$2" expected="$3" persisted="$4" loaded="$5"
  local output
  if [[ $label == helper ]]; then
    output="$(
      env TEST_PERSISTED="$persisted" TEST_LOADED="$loaded" \
        "$command_path" hyprbars-status
    )"
  else
    output="$(
      env PATH="$fakebin:$PATH" TEST_PERSISTED="$persisted" TEST_LOADED="$loaded" \
        bash "$command_path" --status
    )"
  fi
  [[ $output == "$expected" ]] \
    || fail "$label returned '$output' for persisted=$persisted loaded=$loaded; expected '$expected'"
}

for target in helper fallback; do
  if [[ $target == helper ]]; then
    path="$helper_fixture"
  else
    path="$toggle_fixture"
  fi

  assert_state "$target" "$path" enabled enabled 1
  assert_state "$target" "$path" not-loaded enabled 0
  assert_state "$target" "$path" disabled-pending disabled 1
  assert_state "$target" "$path" disabled disabled 0
done

contains "$TITLE_CARD" 'hyprbarsState === "not-loaded"' \
  'Quick Settings does not recognize the persisted-enabled/runtime-missing state'
contains "$TITLE_CARD" 'return "Enabled · Not loaded";' \
  'Quick Settings does not explain that hyprbars is enabled but not loaded'
contains "$TITLE_CARD" 'return "Load";' \
  'Quick Settings does not offer a Load action for enabled-but-not-loaded hyprbars'
contains "$TITLE_CARD" '|| state === "not-loaded"' \
  'Quick Settings status parser drops the not-loaded state'

session_runtime="$TMPD/runtime"
session_home="$TMPD/home"
hyprpm_log="$TMPD/hyprpm.log"
mkdir -p -- "$session_runtime" "$session_home"
: >"$hyprpm_log"

run_session_probe() {
  local signature="${1:-}"
  if [[ -n $signature ]]; then
    env \
      PATH="$fakebin:$PATH" \
      HOME="$session_home" \
      XDG_RUNTIME_DIR="$session_runtime" \
      HYPRLAND_INSTANCE_SIGNATURE="$signature" \
      HYPRPM_AUTO_LOCK_TTL_SECONDS=0 \
      TEST_HYPRPM_LOG="$hyprpm_log" \
      bash "$AUTO_RELOAD"
  else
    env -u HYPRLAND_INSTANCE_SIGNATURE \
      PATH="$fakebin:$PATH" \
      HOME="$session_home" \
      XDG_RUNTIME_DIR="$session_runtime" \
      HYPRPM_AUTO_LOCK_TTL_SECONDS=0 \
      TEST_HYPRPM_LOG="$hyprpm_log" \
      bash "$AUTO_RELOAD"
  fi
}

run_session_probe session-a
[[ $(grep -cFx 'reload' "$hyprpm_log" || true) -eq 1 ]] \
  || fail 'fresh Hyprland session did not reconcile enabled plugin load state exactly once'

run_session_probe session-a
[[ $(grep -cFx 'reload' "$hyprpm_log" || true) -eq 1 ]] \
  || fail 'same Hyprland session performed an unsafe repeated automatic plugin reload'

run_session_probe session-b
[[ $(grep -cFx 'reload' "$hyprpm_log" || true) -eq 2 ]] \
  || fail 'new Hyprland session did not reconcile plugin load state'

run_session_probe ""
[[ $(grep -cFx 'reload' "$hyprpm_log" || true) -eq 2 ]] \
  || fail 'manual/default invocation without a session signature performed a live reload'

printf '%s\n' 'PASS: hyprbars distinguishes persisted and runtime state and reconciles once per Hyprland session.'
