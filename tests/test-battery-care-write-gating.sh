#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CARD="${ROOT}/config/quickshell/awtarchy/BatteryCareCard.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_source() {
    local needle="$1" message="$2"
    grep -Fq -- "$needle" "$CARD" || fail "$message"
}

require_absent() {
    local needle="$1" message="$2"
    ! grep -Fq -- "$needle" "$CARD" || fail "$message"
}

[[ -f "$CARD" ]] || fail 'BatteryCareCard.qml is missing'
require_source 'writable: false' 'Battery Care empty status does not default writes to disabled'
require_source 'compatibility: "unsupported"' 'Battery Care empty status has no compatibility classification'
require_source '&& Boolean(statusData.writable)' 'Battery Care controls do not require writable TLP capability'
require_source 'root.hasNumericControl()' 'Battery Care controls do not require a generic numeric interface'
require_source 'function targetReadbackDiffers()' 'Battery Care UI does not distinguish configured and reported charge targets'
require_source 'Configured: ' 'Battery Care UI does not expose the configured target when readback differs'
require_source 'reported: ' 'Battery Care UI does not expose the reported target when readback differs'
require_source 'TLP accepted the configured target, but the reported hardware value differs.' 'Battery Care UI does not explain non-fatal hardware readback differences'
require_absent 'fixedUnknownTarget' 'Battery Care UI still owns a vendor-specific fixed-mode exception'
require_absent 'battery-enable-fixed' 'Battery Care UI still invokes the retired vendor selector action'
require_absent 'pluginName ===' 'Battery Care UI still gates behavior on a TLP plugin name'
require_absent 'hardware state verified after every change' 'Battery Care UI still claims Awtarchy performs hardware verification'

sync_body="$(awk '/function syncTargetDraft\(\)/,/^    }/' "$CARD")"
managed_line="$(grep -nF 'if (Boolean(statusData.managed_config) && Number.isFinite(managed)' <<<"$sync_body" | cut -d: -f1)"
observed_line="$(grep -nF 'if (Number.isFinite(observed)' <<<"$sync_body" | cut -d: -f1)"
[[ -n "$managed_line" ]] || fail 'Battery Care target editor does not explicitly prefer a valid managed target'
[[ -n "$observed_line" ]] || fail 'Battery Care target editor no longer falls back to observed hardware state'
(( managed_line < observed_line )) \
    || fail 'Battery Care target editor prefers hardware readback over the configured managed target'

printf '%s\n' 'PASS: Battery Care QML exposes generic writable TLP percentage controls, surfaces readback mismatches, and keeps the configured target authoritative in the editor.'
