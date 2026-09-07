#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file_text() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || fail "$file is missing: $text"
}

[[ -f INSTALL.md ]] || fail 'INSTALL.md is missing'
[[ -f UPDATING.md ]] || fail 'UPDATING.md is missing'

require_file_text INSTALL.md 'Awtarchy is an Arch Linux overlay/environment, not a Linux distribution'
require_file_text INSTALL.md 'https://archlinux.org/download/'
require_file_text INSTALL.md 'archinstall'
require_file_text INSTALL.md 'Minimal'
require_file_text INSTALL.md 'https://wiki.archlinux.org/title/Installation_guide'
require_file_text INSTALL.md 'sudo pacman -S git --noconfirm'
require_file_text INSTALL.md 'git clone https://github.com/dillacorn/awtarchy'
require_file_text INSTALL.md 'sudo ./awtarchy-install.sh'
require_file_text INSTALL.md './awtarchy-install.sh --dry-run'
require_file_text INSTALL.md 'sudo ./awtarchy-install.sh --reinstall'

require_file_text UPDATING.md 'awtarchy update'
require_file_text UPDATING.md 'awtarchy review'
require_file_text UPDATING.md 'awtarchy reset'
require_file_text UPDATING.md 'awtarchy version'
require_file_text UPDATING.md 'awtarchy git'
require_file_text UPDATING.md 'published release'
require_file_text UPDATING.md 'Git-testing'
require_file_text UPDATING.md 'backup'

require_file_text README.md '[Installation guide](INSTALL.md)'
require_file_text README.md '[Updating guide](UPDATING.md)'
if grep -Fq 'See the [Release Page](https://github.com/dillacorn/awtarchy/releases) for install directions.' README.md; then
  fail 'README still treats release pages as the installation source of truth'
fi
if grep -Fq 'sudo ./awtarchy-install.sh' README.md; then
  fail 'README still duplicates canonical installation commands'
fi

printf '%s\n' 'PASS: installation and update documentation have one canonical source of truth'
