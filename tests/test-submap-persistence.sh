#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/config/hypr/scripts/submap_state.sh"
READY_SOUND="${ROOT}/config/hypr/scripts/quickshell_ready_sound.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$HELPER" ]] || fail 'submap persistence helper is missing'
grep -Fq 'submap_state.sh" init' "$READY_SOUND" \
    || fail 'login startup does not initialize persistent submap state'

fakebin="${TMP}/bin"
mkdir -p -- "$fakebin"
log="${TMP}/hyprctl.log"
cat >"${fakebin}/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${SUBMAP_TEST_HYPRCTL_LOG:?}"
EOF
chmod 0755 "${fakebin}/hyprctl"

runtime_dir="${TMP}/runtime"
state_dir="${TMP}/state"
runtime_file="${runtime_dir}/awtarchy-hypr-submap"
persist_file="${state_dir}/awtarchy/hypr-submap"
mkdir -p -- "$(dirname -- "$persist_file")"
printf '%s\n' noalt >"$persist_file"

run_helper() {
    PATH="${fakebin}:$PATH" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    XDG_STATE_HOME="$state_dir" \
    SUBMAP_TEST_HYPRCTL_LOG="$log" \
        bash "$HELPER" "$@"
}

run_helper init
[[ -L "$runtime_file" ]] || fail 'runtime submap state is not a symlink after init'
[[ "$(readlink -f -- "$runtime_file")" == "$(readlink -f -- "$persist_file")" ]] \
    || fail 'runtime submap state does not point at persistent state'
grep -Fxq 'dispatch hl.dsp.submap("noalt")' "$log" \
    || fail 'remembered noalt submap was not restored on a new session'

# Existing Awtarchy submap writers continue to target the runtime file. Once it
# is linked, their writes must transparently update the persistent preference.
printf '%s\n' mouse >"$runtime_file"
[[ "$(cat "$persist_file")" == mouse ]] \
    || fail 'runtime submap write did not persist through the compatibility link'

# Simulate another login: runtime state is new, persistent preference survives.
rm -f -- "$runtime_file"
: >"$log"
run_helper init
[[ -L "$runtime_file" ]] || fail 'runtime compatibility link was not recreated on next login'
grep -Fxq 'dispatch hl.dsp.submap("mouse")' "$log" \
    || fail 'remembered mouse submap was not restored on next login'

# A current-session regular runtime file from older Awtarchy is migrated once
# without dispatching over the already-active submap.
rm -f -- "$runtime_file"
mkdir -p -- "$runtime_dir"
printf '%s\n' vm >"$runtime_file"
printf '%s\n' noalt >"$persist_file"
: >"$log"
run_helper init
[[ -L "$runtime_file" ]] || fail 'legacy runtime file was not converted to compatibility link'
[[ "$(cat "$persist_file")" == vm ]] \
    || fail 'legacy active submap was not adopted as persistent preference'
[[ ! -s "$log" ]] || fail 'legacy in-session migration unexpectedly redispatched a submap'

# Off / Normal clears the remembered preference and resets the compositor.
run_helper reset
[[ ! -s "$persist_file" ]] || fail 'reset did not clear persistent submap preference'
grep -Fxq 'dispatch hl.dsp.submap("reset")' "$log" \
    || fail 'reset did not dispatch the normal submap'

# Invalid persisted values must fail closed to normal mode.
printf '%s\n' garbage >"$persist_file"
rm -f -- "$runtime_file"
: >"$log"
run_helper init
[[ ! -s "$persist_file" ]] || fail 'invalid persisted submap value was not cleared'
[[ ! -s "$log" ]] || fail 'invalid persisted submap value was dispatched'

printf 'PASS: submap preference persists safely across sessions\n'
