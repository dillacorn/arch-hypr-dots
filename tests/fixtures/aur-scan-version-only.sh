#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# == 1 )) && [[ $1 == --version ]]; then
  printf '%s\n' 'aur-scan test fixture'
  exit 0
fi

if (( $# == 3 )) \
  && [[ $1 == install ]] \
  && [[ $2 == bibata-cursor-theme-bin ]] \
  && [[ $3 == --noconfirm ]]; then
  state="${AWTARCHY_TEST_PACKAGE_STATE:-}"
  [[ -n $state && -f $state ]] || {
    printf '%s\n' 'FAIL: Bibata install fixture requires AWTARCHY_TEST_PACKAGE_STATE.' >&2
    exit 98
  }
  grep -Fxq bibata-cursor-theme-bin "$state" \
    || printf '%s\n' bibata-cursor-theme-bin >>"$state"
  exit 0
fi

printf 'FAIL: unexpected aur-scan fixture invocation:' >&2
printf ' %q' "$@" >&2
printf '\n' >&2
exit 97
