#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="${REPO_ROOT}/config/hypr/scripts/awtarchy-tips-tui.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

(
    source "$SCRIPT"

    sample=$'Docs: https://example.com/one.\nMarkdown: [two](https://example.com/two?x=1&y=2)\nAgain: https://example.com/one.'
    mapfile -t urls < <(extract_urls "$sample")

    [[ ${#urls[@]} -eq 2 ]] || fail "expected 2 unique URLs, got ${#urls[@]}"
    [[ ${urls[0]} == 'https://example.com/one' ]] || fail 'first URL was not normalized'
    [[ ${urls[1]} == 'https://example.com/two?x=1&y=2' ]] || fail 'Markdown URL was not extracted correctly'
)

grep -Fq 'o = open link' "$SCRIPT" || fail 'text viewer does not advertise the open-link action'
grep -Fq 'o|O)' "$SCRIPT" || fail 'text viewer does not bind the open-link action'
grep -Fq 'xdg-open "$url"' "$SCRIPT" || fail 'links are not opened with xdg-open as a direct argument'

if grep -Eq 'eval[^\n]*xdg-open|sh[[:space:]]+-c[^\n]*xdg-open' "$SCRIPT"; then
    fail 'link opening must not route URLs through shell evaluation'
fi

printf 'PASS: Awtarchy Tips URL extraction and open-link behavior are present.\n'
