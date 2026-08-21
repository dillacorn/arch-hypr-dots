#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHER="${AWTARCHY_TEST_BRIGHTNESS_WATCHER:-${ROOT}/config/hypr/scripts/ddc_brightness.sh}"
TMP="$(mktemp -d)"
watch_pid=""
child_pid=""

cleanup() {
  if [[ -n ${watch_pid:-} ]]; then
    kill "$watch_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n ${child_pid:-} ]]; then
    kill "$child_pid" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || fail "python3 is required"
command -v pgrep >/dev/null 2>&1 || fail "pgrep is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"

fakebin="${TMP}/fakebin"
cache_dir="${TMP}/cache/hypr-ddc-brightness"
mkdir -p "$fakebin" "$cache_dir"

cat >"${fakebin}/jq" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{}'
EOF
chmod 0755 "${fakebin}/jq"

printf '50\t100\t%s\n' "$(date +%s%3N)" \
  >"${cache_dir}/state_LVDS-1.tsv"

PATH="${fakebin}:$PATH" \
  XDG_CACHE_HOME="${TMP}/cache" \
  AWTARCHY_OUTPUT_NAME="LVDS-1" \
  "$WATCHER" watch >"${TMP}/watch.out" 2>"${TMP}/watch.err" &
watch_pid=$!

for _ in {1..100}; do
  child_pid="$(pgrep -f -x \
    "python3 - ${cache_dir} state_LVDS-1.tsv preview_LVDS-1.tsv 10000 ${watch_pid}" \
    | head -n1 || true)"
  [[ -n $child_pid ]] && break
  kill -0 "$watch_pid" >/dev/null 2>&1 \
    || fail "DDC watcher exited before starting its Python child"
  sleep 0.05
done
[[ -n $child_pid ]] || fail "DDC watcher did not start its Python child"

kill "$watch_pid"
wait "$watch_pid" 2>/dev/null || true
watch_pid=""

for _ in {1..100}; do
  if ! kill -0 "$child_pid" >/dev/null 2>&1; then
    child_pid=""
    break
  fi
  sleep 0.05
done

[[ -z $child_pid ]] \
  || fail "Python DDC watcher survived after its parent exited"

retry_cache_dir="${TMP}/retry-cache/hypr-ddc-brightness"
retry_runtime_dir="${TMP}/retry-runtime"
retry_attempts="${TMP}/retry-attempts"
retry_controller="${TMP}/retry-brightness-controller"
mkdir -p "$retry_cache_dir" "$retry_runtime_dir"

cat >"$retry_controller" <<'EOF'
#!/usr/bin/env bash
attempt=0
if [[ -r $FAKE_BRIGHTNESS_ATTEMPTS ]]; then
  IFS= read -r attempt <"$FAKE_BRIGHTNESS_ATTEMPTS" || attempt=0
fi
attempt=$((attempt + 1))
printf '%s\n' "$attempt" >"$FAKE_BRIGHTNESS_ATTEMPTS"

if [[ ${FAKE_BRIGHTNESS_ALWAYS_FAIL:-0} == 1 ]] || (( attempt == 1 )); then
  exit 1
fi

printf '60\t100\t%s\n' "$(date +%s%3N)" \
  >"${FAKE_BRIGHTNESS_CACHE_DIR}/state_LVDS-1.tsv"
printf '%s\n' 'conn=LVDS-1' 'cur=60' 'max=100'
EOF
chmod 0755 "$retry_controller"

XDG_CACHE_HOME="${TMP}/retry-cache" \
  XDG_RUNTIME_DIR="$retry_runtime_dir" \
  AWTARCHY_OUTPUT_NAME="LVDS-1" \
  AWTARCHY_DDC_WATCH_STARTUP_ATTEMPTS=3 \
  AWTARCHY_DDC_WATCH_STARTUP_INTERVAL=0.05 \
  HYPR_BRIGHTNESS_SCRIPT="$retry_controller" \
  FAKE_BRIGHTNESS_ATTEMPTS="$retry_attempts" \
  FAKE_BRIGHTNESS_CACHE_DIR="$retry_cache_dir" \
  "$WATCHER" watch >"${TMP}/retry-watch.out" 2>"${TMP}/retry-watch.err" &
watch_pid=$!

initialized=false
for _ in {1..100}; do
  if [[ -r ${TMP}/retry-watch.out ]] \
    && grep -Fq '"percentage":60' "${TMP}/retry-watch.out"; then
    initialized=true
    break
  fi
  kill -0 "$watch_pid" >/dev/null 2>&1 \
    || fail "DDC watcher exited while retrying startup brightness"
  sleep 0.05
done

[[ $initialized == true ]] \
  || fail "DDC watcher did not retry brightness initialization"
[[ $(<"$retry_attempts") -ge 2 ]] \
  || fail "DDC watcher did not make a second startup query"

initialized_attempts="$(<"$retry_attempts")"
sleep 0.2
[[ $(<"$retry_attempts") == "$initialized_attempts" ]] \
  || fail "DDC watcher kept polling after brightness initialized"

kill "$watch_pid"
wait "$watch_pid" 2>/dev/null || true
watch_pid=""

bounded_cache_dir="${TMP}/bounded-cache/hypr-ddc-brightness"
bounded_runtime_dir="${TMP}/bounded-runtime"
bounded_attempts="${TMP}/bounded-attempts"
mkdir -p "$bounded_cache_dir" "$bounded_runtime_dir"

XDG_CACHE_HOME="${TMP}/bounded-cache" \
  XDG_RUNTIME_DIR="$bounded_runtime_dir" \
  AWTARCHY_OUTPUT_NAME="LVDS-1" \
  AWTARCHY_DDC_WATCH_STARTUP_ATTEMPTS=3 \
  AWTARCHY_DDC_WATCH_STARTUP_INTERVAL=0.02 \
  HYPR_BRIGHTNESS_SCRIPT="$retry_controller" \
  FAKE_BRIGHTNESS_ATTEMPTS="$bounded_attempts" \
  FAKE_BRIGHTNESS_CACHE_DIR="$bounded_cache_dir" \
  FAKE_BRIGHTNESS_ALWAYS_FAIL=1 \
  "$WATCHER" watch >"${TMP}/bounded-watch.out" 2>"${TMP}/bounded-watch.err" &
watch_pid=$!

bounded=false
for _ in {1..100}; do
  if [[ -r $bounded_attempts ]] && (( $(<"$bounded_attempts") >= 3 )); then
    bounded=true
    break
  fi
  kill -0 "$watch_pid" >/dev/null 2>&1 \
    || fail "DDC watcher exited during bounded startup retries"
  sleep 0.02
done

[[ $bounded == true ]] \
  || fail "DDC watcher did not perform its configured startup attempts"
sleep 0.2
[[ $(<"$bounded_attempts") == 3 ]] \
  || fail "DDC watcher continued polling after bounded startup retries"

kill "$watch_pid"
wait "$watch_pid" 2>/dev/null || true
watch_pid=""

printf '%s\n' "DDC brightness watcher lifecycle and startup retry tests passed."
