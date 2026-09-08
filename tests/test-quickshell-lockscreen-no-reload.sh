#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_QML="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"

[[ -f "$SHELL_QML" ]] || {
    printf 'FAIL: lock shell is missing: %s\n' "$SHELL_QML" >&2
    exit 1
}

grep -Fq 'Quickshell.watchFiles = false' "$SHELL_QML" || {
    printf 'FAIL: secure lock process still allows automatic source reloads\n' >&2
    exit 1
}

printf 'PASS: lockscreen automatic source reloads are disabled\n'
