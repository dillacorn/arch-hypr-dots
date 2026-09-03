#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
README="${ROOT}/README.md"
TIPS="${ROOT}/config/hypr/scripts/awtarchy-tips-tui.sh"
UPSTREAM='https://github.com/KiefStudioMA/ks-aur-scanner'

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

for file in "$README" "$TIPS"; do
  [[ -f "$file" ]] || fail "missing user-facing documentation: $file"
  if grep -Eqi 'AUR Guard|AurGuard|aurguard|aurverify|aurinstall' "$file"; then
    fail "retired AurGuard instructions remain in ${file#"$ROOT"/}"
  fi
  grep -Fq 'aur-scan install' "$file" \
    || fail "${file#"$ROOT"/} does not direct AUR installs to aur-scan install"
  grep -Fq 'aur-scan -h' "$file" \
    || fail "${file#"$ROOT"/} does not direct local command discovery to aur-scan -h"
done

grep -Fq "$UPSTREAM" "$README" \
  || fail 'README does not link to the upstream aur-scanner repository'
grep -Fq 'yay' "$README" \
  || fail 'README does not explain the retained yay query/search role'

while IFS= read -r file; do
  if grep -Eq '(^|[^[:alnum:]_-])yay[[:space:]]+-S([[:space:]]|$)' "$file"; then
    fail "stale yay -S installation instruction remains in ${file#"$ROOT"/}"
  fi
done < <(
  find "$ROOT" -type f -name '*.md' \
    ! -path '*/.git/*' \
    -print | LC_ALL=C sort
)

printf '%s\n' 'PASS: user-facing AUR documentation delegates installation and command reference to upstream aur-scanner.'
