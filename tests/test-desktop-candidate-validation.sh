#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_SOURCE="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

awk '
    /^validate_candidate\(\) \{/ { capture=1 }
    capture { print }
    capture && /^}$/ { exit }
' "$RUNTIME_SOURCE" > "$TMP/validate_candidate.sh"

# shellcheck source=/dev/null
source "$TMP/validate_candidate.sh"

shell_launcher="$TMP/shell-launcher.desktop"
broken_desktop="$TMP/broken.desktop"

cat > "$shell_launcher" <<'EOF_DESKTOP'
[Desktop Entry]
Type=Application
Name=Intentional shell launcher
Exec=/bin/sh -c 'command -v example >/dev/null 2>&1 && example || true'
EOF_DESKTOP

cat > "$broken_desktop" <<'EOF_BROKEN'
Type=Application
Name=Missing desktop entry header
Exec=example
EOF_BROKEN

if command -v desktop-file-validate >/dev/null 2>&1; then
    if desktop-file-validate "$shell_launcher" >/dev/null 2>&1; then
        fail "regression fixture no longer reproduces strict desktop validator rejection"
    fi
fi

validate_candidate "$shell_launcher" '.local/share/applications/shell-launcher.desktop' \
    || fail "intentional shell-based desktop launcher was rejected"

if validate_candidate "$broken_desktop" '.local/share/applications/broken.desktop'; then
    fail "desktop file without [Desktop Entry] passed validation"
fi

printf 'Desktop candidate validation tests passed.\n'
