#!/usr/bin/env bash
# Regression checks for safely replacing an untrusted pre-existing Polkit test runtime.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent-live-test.sh"

[[ -f $SCRIPT ]]
bash -n "$SCRIPT"

grep -Fq 'RUNTIME_PARENT="/usr/local/libexec/awtarchy"' "$SCRIPT"
grep -Fq 'stage_runtime_tree()' "$SCRIPT"
grep -Fq '.polkit-agent.stage.' "$SCRIPT"
grep -Fq 'replace_runtime_tree()' "$SCRIPT"
grep -Fq 'verify_runtime_tree "$RUNTIME_DIR"' "$SCRIPT"
grep -Fq "IFS=' ' read -r uid mode type" "$SCRIPT"

# A pre-existing user-owned runtime must not simply be chowned/adopted in place.
if grep -Eq 'chown[^\n]*\$RUNTIME_DIR|chown[^\n]*/polkit-agent' "$SCRIPT"; then
    printf '%s\n' 'FAIL: installer adopts an existing runtime directory with chown' >&2
    exit 1
fi

# Replacement must stage trusted files first and preserve rollback if activation fails.
grep -Fq '/usr/bin/sudo /usr/bin/mv -Tf -- "$RUNTIME_DIR" "$previous"' "$SCRIPT"
grep -Fq '/usr/bin/sudo /usr/bin/mv -Tf -- "$stage" "$RUNTIME_DIR"' "$SCRIPT"
grep -Fq '/usr/bin/sudo /usr/bin/mv -Tf -- "$previous" "$RUNTIME_DIR"' "$SCRIPT"

printf '%s\n' 'polkit runtime rebuild tests passed'
