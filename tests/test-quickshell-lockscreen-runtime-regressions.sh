#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_QML="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
SURFACE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

reject_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

# Runtime regression: a LockSurface property named `auth` must not be bound as
# `auth: auth` from the Component body. In QML that self-shadows the outer id,
# leaving every surface with an undefined authentication object.
require_text "$SHELL_QML" 'id: lockAuth' \
    'lock shell does not use a non-shadowing authentication id'
require_text "$SHELL_QML" 'auth: lockAuth' \
    'lock surface is not bound to the real LockAuth object'
reject_text "$SHELL_QML" 'auth: auth' \
    'lock surface still self-binds auth and loses the authentication object'

# Simplified lockscreen presentation: no Fastfetch mark, one small TUI-style
# Awtarchy heading, and uniform password blocks.
reject_text "$SURFACE_QML" '/fastfetch/ascii/awtarchy.txt' \
    'lockscreen still loads the Fastfetch ASCII mark'
reject_text "$SURFACE_QML" 'id: logoFile' \
    'lockscreen still owns the removed Fastfetch FileView'
require_text "$SURFACE_QML" 'text: "── AWTARCHY ──"' \
    'lockscreen does not use the approved compact TUI-style Awtarchy heading'
require_text "$SURFACE_QML" 'readonly property int maskedCount: Math.min(password.text.length, 10)' \
    'lockscreen does not cap visible password length'
require_text "$SURFACE_QML" 'width: Math.round(7 * root.uiScale)' \
    'password blocks do not use one fixed width'
require_text "$SURFACE_QML" 'height: Math.round(10 * root.uiScale)' \
    'password blocks do not use one fixed height'
reject_text "$SURFACE_QML" 'index % 3' \
    'password blocks still vary in height by index'
reject_text "$SURFACE_QML" 'index % 4' \
    'password blocks still vary in opacity by index'

printf 'PASS: lockscreen runtime regressions\n'
