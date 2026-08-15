#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHER="${ROOT}/config/hypr/scripts/ddc_brightness.sh"
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

printf '%s\n' "DDC brightness watcher lifecycle test passed."
