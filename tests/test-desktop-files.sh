#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APPLICATIONS_DIR="${ROOT}/local/share/applications"
AWTWALL_DESKTOP="${APPLICATIONS_DIR}/awtwall.desktop"
AWTWALL_LAUNCHER="${ROOT}/config/hypr/scripts/awtwall_launcher.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

command -v desktop-file-validate >/dev/null 2>&1 \
    || fail "desktop-file-validate is required for this test"

[[ -d "$APPLICATIONS_DIR" ]] \
    || fail "managed desktop-entry directory is missing"
[[ -f "$AWTWALL_DESKTOP" ]] \
    || fail "awtwall desktop entry is missing"
[[ -f "$AWTWALL_LAUNCHER" ]] \
    || fail "awtwall launcher is missing"

bash -n "$AWTWALL_LAUNCHER"

grep -Fxq 'Exec=/bin/sh -c "exec ~/.config/hypr/scripts/awtwall_launcher.sh"' \
    "$AWTWALL_DESKTOP" \
    || fail "awtwall desktop entry does not use the managed launcher"

# shellcheck disable=SC2016
grep -Fq 'exec "$launch_handler"' "$AWTWALL_LAUNCHER" \
    || fail "awtwall launcher does not preserve launch_handler behavior"
grep -Fq 'alacritty --class wallpicker -e awtwall --resume' "$AWTWALL_LAUNCHER" \
    || fail "awtwall launcher does not preserve the wallpicker command"

mapfile -d '' desktop_files < <(
    find "$APPLICATIONS_DIR" -type f -name '*.desktop' -print0 | sort -z
)
(( ${#desktop_files[@]} > 0 )) \
    || fail "no managed desktop entries were found"

validation_failed=0
for desktop_file in "${desktop_files[@]}"; do
    if ! desktop-file-validate "$desktop_file"; then
        validation_failed=1
    fi
done

(( validation_failed == 0 )) \
    || fail "one or more managed desktop entries failed validation"

printf 'Managed desktop-entry tests passed.\n'
