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

Awtarchy is an Arch Linux overlay/environment, not a Linux distribution or an Arch Linux installer. Install it onto a working minimal Arch Linux system.

If you are starting from zero:

1. Download the official Arch Linux ISO from the [Arch Linux download page](https://archlinux.org/download/).
2. Boot the Arch Linux ISO.
3. Install a working minimal Arch Linux system first.
   - For most users, Awtarchy recommends the official `archinstall` guided installer included with the Arch ISO as the easiest path.
   - A normal manual Arch installation using the [ArchWiki Installation Guide](https://wiki.archlinux.org/title/Installation_guide) is also fine.
4. Boot into the installed Arch system.

Once you have a working minimal Arch installation, install Awtarchy:

```bash
sudo pacman -S git --noconfirm
git clone https://github.com/dillacorn/awtarchy
cd awtarchy
sudo ./awtarchy-install.sh
```

## Existing Awtarchy users

```bash
awtarchy update
```

## Validation

- Previous validation evidence.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.5.5._
EOF

sed 's/v3\.5\.5/v3.5.6/g; s/Previous stable release\./New stable release./; s/Previous validation evidence\./New validation evidence./' \
  "${TMP_DIR}/previous.md" >"${TMP_DIR}/valid.md"

[[ -f "$VALIDATOR" ]] || fail "stable release notes validator is missing"
run_validator "${TMP_DIR}/valid.md" "${TMP_DIR}/previous.md" >/dev/null \
  || fail "complete stable release notes were rejected"

grep -v '^## Getting started$' "${TMP_DIR}/valid.md" >"${TMP_DIR}/missing-getting-started.md"
if run_validator "${TMP_DIR}/missing-getting-started.md" "${TMP_DIR}/previous.md" >/dev/null 2>&1; then
  fail "release without Getting started was accepted"
fi

grep -v '^sudo ./awtarchy-install\.sh$' "${TMP_DIR}/valid.md" >"${TMP_DIR}/missing-install-command.md"
if run_validator "${TMP_DIR}/missing-install-command.md" "${TMP_DIR}/previous.md" >/dev/null 2>&1; then
  fail "release without the current install command was accepted"
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

printf '%s\n' 'PASS: stable release notes validator enforces the release contract'
