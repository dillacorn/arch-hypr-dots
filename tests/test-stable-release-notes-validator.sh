#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="${ROOT_DIR}/.github/scripts/validate-stable-release-notes.py"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run_validator() {
  python3 "$VALIDATOR" --version v3.5.6 --notes "$1" --previous "$2"
}

cat >"${TMP_DIR}/previous.md" <<'EOF'
# Awtarchy v3.5.5 Quickshell

Previous stable release.

## Getting started

Legacy duplicated installation directions lived here.

## Existing Awtarchy users

Legacy duplicated update directions lived here.

## Validation

- Previous validation evidence.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.5.5._
EOF

cat >"${TMP_DIR}/valid.md" <<'EOF'
# Awtarchy v3.5.6 Quickshell

New stable release with release-specific changes and canonical documentation links.

## Install and update

- New installation: [INSTALL.md](https://github.com/dillacorn/awtarchy/blob/main/INSTALL.md)
- Existing Awtarchy users: [UPDATING.md](https://github.com/dillacorn/awtarchy/blob/main/UPDATING.md) or run `awtarchy update`.

## Changes

- New release-specific behavior.

## Validation

- New validation evidence.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.5.6._
EOF

[[ -f "$VALIDATOR" ]] || fail "stable release notes validator is missing"
run_validator "${TMP_DIR}/valid.md" "${TMP_DIR}/previous.md" >/dev/null \
  || fail "canonical-guide stable release notes were rejected"

sed '/INSTALL\.md/d' "${TMP_DIR}/valid.md" >"${TMP_DIR}/missing-install-link.md"
if run_validator "${TMP_DIR}/missing-install-link.md" "${TMP_DIR}/previous.md" >/dev/null 2>&1; then
  fail "release without canonical INSTALL.md link was accepted"
fi

sed '/UPDATING\.md/d' "${TMP_DIR}/valid.md" >"${TMP_DIR}/missing-update-link.md"
if run_validator "${TMP_DIR}/missing-update-link.md" "${TMP_DIR}/previous.md" >/dev/null 2>&1; then
  fail "release without canonical UPDATING.md link was accepted"
fi

sed 's#blob/main/INSTALL\.md#blob/v3.5.5/INSTALL.md#' \
  "${TMP_DIR}/valid.md" >"${TMP_DIR}/stale-install-link.md"
if run_validator "${TMP_DIR}/stale-install-link.md" "${TMP_DIR}/previous.md" >/dev/null 2>&1; then
  fail "release with non-canonical INSTALL.md link was accepted"
fi

python3 - "${TMP_DIR}/valid.md" "${TMP_DIR}/overlong.md" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
insert = "## Exhaustive implementation detail\n\n" + ("detail " * 700).strip() + "\n\n"
Path(sys.argv[2]).write_text(source.replace("## Validation\n", insert + "## Validation\n", 1))
PY
if run_validator "${TMP_DIR}/overlong.md" "${TMP_DIR}/previous.md" >/dev/null 2>&1; then
  fail "release above the 650-word default budget was accepted"
fi

sed 's/_Placeholder for possible tested post-release patches to v3\.5\.6\._/_Placeholder for possible tested post-release patches to v3.5.5._/' \
  "${TMP_DIR}/valid.md" >"${TMP_DIR}/wrong-placeholder.md"
if run_validator "${TMP_DIR}/wrong-placeholder.md" "${TMP_DIR}/previous.md" >/dev/null 2>&1; then
  fail "release with a stale post-release placeholder was accepted"
fi

sed '/^## Validation$/,/^## Post-release updates$/ { /^## Validation$/d; }' \
  "${TMP_DIR}/valid.md" >"${TMP_DIR}/missing-validation.md"
if run_validator "${TMP_DIR}/missing-validation.md" "${TMP_DIR}/previous.md" >/dev/null 2>&1; then
  fail "release without Validation was accepted"
fi

printf '%s\n' 'PASS: stable release notes validator enforces canonical guide links, concise notes, and release structure'
