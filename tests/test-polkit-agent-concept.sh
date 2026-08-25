#!/usr/bin/env bash
# Focused geometry checks for the PolicyKit terminal UI concept.

set -u
set -o pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent-concept.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/hyprctl" <<'FAKE'
#!/usr/bin/env bash
set -u

if [[ ${1:-} == -j && ${2:-} == clients ]]; then
    cat "$HYPR_CLIENTS_JSON"
    exit 0
fi

if [[ ${1:-} == eval ]]; then
    printf '%s\n' "${2:-}" >> "$HYPR_EVAL_LOG"
    exit 0
fi

exit 1
FAKE
chmod +x "$TMP/hyprctl"

cat > "$TMP/wrong.json" <<'JSON'
[
  {
    "address": "0xabc123",
    "mapped": true,
    "visible": true,
    "at": [12, 24],
    "size": [700, 300],
    "floating": false,
    "class": "awtarchy-polkit-agent-concept",
    "title": "awtarchy-polkit-agent-concept",
    "initialClass": "awtarchy-polkit-agent-concept",
    "initialTitle": "awtarchy-polkit-agent-concept",
    "focusHistoryID": 0
  }
]
JSON

cat > "$TMP/correct.json" <<'JSON'
[
  {
    "address": "0xabc123",
    "mapped": true,
    "visible": true,
    "at": [100, 100],
    "size": [900, 520],
    "floating": true,
    "class": "awtarchy-polkit-agent-concept",
    "title": "awtarchy-polkit-agent-concept",
    "initialClass": "awtarchy-polkit-agent-concept",
    "initialTitle": "awtarchy-polkit-agent-concept",
    "focusHistoryID": 0
  }
]
JSON

export HYPRLAND_INSTANCE_SIGNATURE=test
export HYPRCTL_BIN="$TMP/hyprctl"
export HYPR_EVAL_LOG="$TMP/eval.log"
export HYPR_CLIENTS_JSON="$TMP/wrong.json"

# shellcheck source=/dev/null
source "$SCRIPT"

state="$(query_concept_window_state)"
[[ $state == $'0xabc123\tfalse\t700\t300\t12\t24\ttrue' ]] || {
    printf 'unexpected state: %q\n' "$state" >&2
    exit 1
}

: > "$HYPR_EVAL_LOG"
correct_window_geometry_if_needed
rc=$?
[[ $rc -eq 0 ]] || {
    printf 'wrong-state correction rc=%s\n' "$rc" >&2
    exit 1
}

grep -Fq 'window.float({ action = "set", window = w })' "$HYPR_EVAL_LOG"
grep -Fq 'window.resize({ x = 900, y = 520, relative = false, window = w })' "$HYPR_EVAL_LOG"
grep -Fq 'window.center({ window = w })' "$HYPR_EVAL_LOG"
grep -Fq 'local w="address:0xabc123"' "$HYPR_EVAL_LOG"

export HYPR_CLIENTS_JSON="$TMP/correct.json"
: > "$HYPR_EVAL_LOG"
correct_window_geometry_if_needed
rc=$?
[[ $rc -eq 2 ]] || {
    printf 'correct-state rc=%s\n' "$rc" >&2
    exit 1
}
[[ ! -s $HYPR_EVAL_LOG ]] || {
    printf 'correct geometry unexpectedly dispatched changes\n' >&2
    exit 1
}

printf '%s\n' 'polkit concept geometry tests passed'
