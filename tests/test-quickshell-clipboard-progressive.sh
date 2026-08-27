#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${ROOT}/config/hypr/scripts/quickshell_clipboard.sh"
TMPD="$(mktemp -d)"
LIST_PID=""
CLIPHIST_PID=""

cleanup() {
  if [[ -n "$LIST_PID" ]] && kill -0 "$LIST_PID" 2>/dev/null; then
    kill "$LIST_PID" 2>/dev/null || true
    wait "$LIST_PID" 2>/dev/null || true
  fi
  if [[ -n "$CLIPHIST_PID" ]] && kill -0 "$CLIPHIST_PID" 2>/dev/null; then
    kill "$CLIPHIST_PID" 2>/dev/null || true
    wait "$CLIPHIST_PID" 2>/dev/null || true
  fi
  rm -rf -- "$TMPD"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p -- "${TMPD}/bin" "${TMPD}/runtime"

cat >"${TMPD}/bin/cliphist" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  list)
    if [[ -n "${AWTARCHY_CLIPBOARD_PID_FILE:-}" ]]; then
      printf '%s\n' "$$" >"$AWTARCHY_CLIPBOARD_PID_FILE"
    fi
    if [[ "${AWTARCHY_CLIPBOARD_FAIL_LIST:-0}" == 1 ]]; then
      printf 'cliphist fixture: database unavailable\n' >&2
      exit 23
    fi
    printf '200\tnewest clipboard entry\n'
    if [[ "${AWTARCHY_CLIPBOARD_HANG_LIST:-0}" == 1 ]]; then
      while true; do
        sleep 1
      done
    fi
    sleep 3
    printf '199\tolder clipboard entry\n'
    ;;
  decode)
    sed -E 's/^[0-9]+\t//'
    ;;
  delete)
    [[ -n "${AWTARCHY_CLIPBOARD_DELETE_FILE:-}" ]] || exit 24
    cat >"$AWTARCHY_CLIPBOARD_DELETE_FILE"
    ;;
  *)
    exit 2
    ;;
esac
EOF

cat >"${TMPD}/bin/wl-copy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
EOF

chmod 0755 "${TMPD}/bin/cliphist" "${TMPD}/bin/wl-copy"

output="${TMPD}/list.jsonl"
env \
  PATH="${TMPD}/bin:${PATH}" \
  XDG_RUNTIME_DIR="${TMPD}/runtime" \
  LIST_LIMIT=10 \
  "$BACKEND" list >"$output" &
LIST_PID=$!

for _ in {1..200}; do
  [[ -s "$output" ]] && break
  sleep 0.01
done

[[ -s "$output" ]] \
  || fail 'newest clipboard entry was not emitted while cliphist was still listing'
kill -0 "$LIST_PID" 2>/dev/null \
  || fail 'clipboard list completed before the progressive-output assertion'

first_line="$(head -n 1 "$output")"
jq -e \
  '.index == 0 and .label == "newest clipboard entry" and .binary == false and .thumb == ""' \
  <<<"$first_line" >/dev/null \
  || fail 'first progressive clipboard record was malformed or out of order'

wait "$LIST_PID"
LIST_PID=""

[[ "$(wc -l <"$output")" -eq 2 ]] \
  || fail 'clipboard backend did not emit exactly one JSON record per history entry'
jq -s -e \
  'map(.label) == ["newest clipboard entry", "older clipboard entry"]' \
  "$output" >/dev/null \
  || fail 'clipboard history was not streamed newest-first'

delete_capture="${TMPD}/deleted.raw"
delete_raw=$'199\tolder clipboard entry'
delete_key="$(printf '%s' "$delete_raw" | sha1sum | awk '{print $1}')"
delete_thumb="${TMPD}/runtime/awtarchy-quickshell/clipboard-thumbs/${delete_key}.png"
mkdir -p -- "$(dirname -- "$delete_thumb")"
printf 'cached thumbnail\n' >"$delete_thumb"

env \
  PATH="${TMPD}/bin:${PATH}" \
  XDG_RUNTIME_DIR="${TMPD}/runtime" \
  AWTARCHY_CLIPBOARD_DELETE_FILE="$delete_capture" \
  "$BACKEND" delete 1

[[ -f "$delete_capture" ]] \
  || fail 'clipboard delete action did not invoke cliphist delete'
[[ "$(<"$delete_capture")" == "$delete_raw" ]] \
  || fail 'clipboard delete action targeted the wrong raw cliphist entry'
[[ ! -e "$delete_thumb" ]] \
  || fail 'clipboard delete action left the deleted entry thumbnail cached'

set +e
env \
  PATH="${TMPD}/bin:${PATH}" \
  XDG_RUNTIME_DIR="${TMPD}/runtime" \
  AWTARCHY_CLIPBOARD_DELETE_FILE="$delete_capture" \
  "$BACKEND" delete 99 >/dev/null 2>&1
invalid_delete_status=$?
set -e
[[ "$invalid_delete_status" -ne 0 ]] \
  || fail 'clipboard delete accepted an index outside the captured list'

failure_output="${TMPD}/failure.jsonl"
failure_error="${TMPD}/failure.stderr"
set +e
env \
  PATH="${TMPD}/bin:${PATH}" \
  XDG_RUNTIME_DIR="${TMPD}/runtime" \
  AWTARCHY_CLIPBOARD_FAIL_LIST=1 \
  LIST_LIMIT=10 \
  "$BACKEND" list >"$failure_output" 2>"$failure_error"
failure_status=$?
set -e

[[ "$failure_status" -eq 23 ]] \
  || fail "clipboard backend swallowed cliphist list failure (status ${failure_status})"
grep -Fq 'cliphist fixture: database unavailable' "$failure_error" \
  || fail 'clipboard backend swallowed cliphist list diagnostics'

slow_output="${TMPD}/slow.jsonl"
cliphist_pid_file="${TMPD}/cliphist.pid"
env \
  PATH="${TMPD}/bin:${PATH}" \
  XDG_RUNTIME_DIR="${TMPD}/runtime" \
  AWTARCHY_CLIPBOARD_HANG_LIST=1 \
  AWTARCHY_CLIPBOARD_PID_FILE="$cliphist_pid_file" \
  LIST_LIMIT=10 \
  "$BACKEND" list >"$slow_output" &
LIST_PID=$!

for _ in {1..200}; do
  [[ -s "$cliphist_pid_file" && -s "$slow_output" ]] && break
  sleep 0.01
done
[[ -s "$cliphist_pid_file" && -s "$slow_output" ]] \
  || fail 'slow clipboard fixture did not start for termination test'
CLIPHIST_PID="$(<"$cliphist_pid_file")"
kill "$LIST_PID"
wait "$LIST_PID" 2>/dev/null || true
LIST_PID=""

if kill -0 "$CLIPHIST_PID" 2>/dev/null; then
  fail 'terminating clipboard backend left the cliphist producer running'
fi
CLIPHIST_PID=""

printf '%s\n' \
  'PASS: clipboard history streams, deletes exact entries, reports failures, and cleans up its producer.'
