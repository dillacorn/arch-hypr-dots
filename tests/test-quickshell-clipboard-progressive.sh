#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${ROOT}/config/hypr/scripts/quickshell_clipboard.sh"
TMPD="$(mktemp -d)"
LIST_PID=""

cleanup() {
  if [[ -n "$LIST_PID" ]] && kill -0 "$LIST_PID" 2>/dev/null; then
    kill "$LIST_PID" 2>/dev/null || true
    wait "$LIST_PID" 2>/dev/null || true
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
    printf '200\tnewest clipboard entry\n'
    sleep 1
    printf '199\tolder clipboard entry\n'
    ;;
  decode)
    sed -E 's/^[0-9]+\t//'
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

for _ in {1..25}; do
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

printf '%s\n' 'PASS: clipboard history streams newest-first before listing completes.'
