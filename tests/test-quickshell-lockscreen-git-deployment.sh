#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
MANAGER="${ROOT}/config/hypr/scripts/awtarchy_lock.sh"
LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$RUNTIME" ]] || fail "missing runtime: $RUNTIME"
[[ -f "$MANAGER" ]] || fail "missing lock manager: $MANAGER"
[[ -f "$LOCK_SHELL" ]] || fail "missing lock shell: $LOCK_SHELL"

# Fresh installs copy the complete hypr and quickshell config trees, so the
# dedicated lock config is included without a second installer source of truth.
grep -Fq 'local -a config_dirs=(hypr quickshell ' "$RUNTIME" \
    || fail 'installer config tree no longer includes both hypr and quickshell'
# The expansions below are intentionally matched as literal runtime source.
# shellcheck disable=SC2016
grep -Fq 'cp -r -- "${REPO_DIR}/config/${dir}" "${HOME_DIR}/.config/"' "$RUNTIME" \
    || fail 'installer no longer copies the complete selected config tree'

# The installer normalizes config files and then restores executability for all
# managed Hypr helper scripts, including awtarchy_lock.sh.
# shellcheck disable=SC2016
grep -Fq 'find "${HOME_DIR}/.config/hypr/scripts" -type f -exec chmod +x {} +' "$RUNTIME" \
    || fail 'installer no longer restores executable mode for Hypr helper scripts'

# Git-testing/update staging also treats any managed .config/quickshell subtree
# as deployable and restores executable mode for .config/hypr/scripts entries.
grep -Fq '.config/hypr/*|.config/quickshell/*|.config/alacritty/*' "$RUNTIME" \
    || fail 'managed update path no longer includes the full Quickshell subtree'
grep -Fq '.config/hypr/scripts/*|.config/hypr/themes/*|.config/waybar/scripts/*)' "$RUNTIME" \
    || fail 'Git-testing staging no longer recognizes executable Hypr scripts'
# shellcheck disable=SC2016
grep -Fq 'chmod 0755 "${augmented_home}/${rel}"' "$RUNTIME" \
    || fail 'Git-testing staging no longer restores executable mode'

printf 'PASS: lockscreen install and Git-testing deployment contracts\n'
