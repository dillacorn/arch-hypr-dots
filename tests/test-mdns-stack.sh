#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

function_body() {
  local name="$1"
  awk -v signature="${name}() {" '
    $0 == signature { active=1; depth=0 }
    active {
      print
      opens=gsub(/\{/, "{")
      closes=gsub(/\}/, "}")
      depth += opens - closes
      if (depth == 0) exit
    }
  ' "$RUNTIME"
}

body="$(function_body configure_mdns_stack)"
[[ -n "$body" ]] || fail 'configure_mdns_stack is missing'

[[ "$RUNTIME" == "$ROOT"/* ]] || fail 'runtime path escaped repository root'

grep -Fq 'ffmpeg avahi nss-mdns mpv' "$RUNTIME" \
  || fail 'nss-mdns is not included with the Avahi multimedia packages'
[[ "$body" == *'MulticastDNS=no'* ]] \
  || fail 'systemd-resolved mDNS is not disabled when Avahi owns mDNS'
[[ "$body" == *'mdns_minimal'* ]] \
  || fail 'Avahi NSS integration does not install mdns_minimal'
[[ "$body" == *'[NOTFOUND=return]'* ]] \
  || fail 'Avahi NSS integration is missing the NOTFOUND return guard'
[[ "$body" == *'/etc/nsswitch.conf'* ]] \
  || fail 'nsswitch.conf is not reconciled'
[[ "$body" == *'backup'* ]] \
  || fail 'nsswitch.conf changes are not backed up'
[[ "$body" == *'90-awtarchy-mdns.conf'* ]] \
  || fail 'Awtarchy does not use a dedicated resolved drop-in'
[[ "$body" == *'pacman -S --needed --noconfirm nss-mdns'* ]] \
  || fail 'existing installs do not receive nss-mdns automatically'

service_block="$(grep -A12 -F 'Configuring system services...' "$RUNTIME")"
[[ "$service_block" == *'configure_mdns_stack'* ]] \
  || fail 'fresh installs do not reconcile the mDNS stack'

hardware_body="$(function_body hardware_reconcile)"
[[ "$hardware_body" == *'configure_mdns_stack'* ]] \
  || fail 'updates do not reconcile the mDNS stack'

printf '%s\n' 'PASS: Awtarchy keeps Avahi as the single mDNS stack and configures NSS resolution.'
