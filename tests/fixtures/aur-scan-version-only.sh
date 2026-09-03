#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# == 1 )) && [[ $1 == --version ]]; then
  printf '%s\n' 'aur-scan test fixture'
  exit 0
fi

printf 'FAIL: unexpected aur-scan fixture invocation:' >&2
printf ' %q' "$@" >&2
printf '\n' >&2
exit 97
