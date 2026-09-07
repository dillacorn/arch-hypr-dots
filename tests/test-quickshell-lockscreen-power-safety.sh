#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="${ROOT}/config/hypr/scripts/awtarchy_lock.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

FAKE_QS="${TMP}/qs"
FAKE_SYSTEMCTL="${TMP}/systemctl"
FAKE_LOGINCTL="${TMP}/loginctl"
COUNTER="${TMP}/counter"
POWER_LOG="${TMP}/power.log"

cat >"$FAKE_QS" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_QS_COUNTER:?}"
: "${FAKE_QS_SEQUENCE:?}"
[[ ${1:-} == -c && ${2:-} == awtarchy-lock ]] || exit 64
shift 2

if (( $# == 0 )); then
    exit 0
fi

[[ $* == 'ipc call lock state' ]] || exit 65
IFS=',' read -r -a states <<<"$FAKE_QS_SEQUENCE"
index="$(cat "$FAKE_QS_COUNTER" 2>/dev/null || printf '0')"
[[ $index =~ ^[0-9]+$ ]] || index=0
if (( index >= ${#states[@]} )); then
    index=$((${#states[@]} - 1))
fi
printf '%s\n' "${states[$index]}"
printf '%s\n' "$((index + 1))" >"$FAKE_QS_COUNTER"
EOF

cat >"$FAKE_SYSTEMCTL" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${POWER_LOG:?}"
printf 'systemctl %s\n' "$*" >>"$POWER_LOG"
EOF

cat >"$FAKE_LOGINCTL" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${POWER_LOG:?}"
printf 'loginctl %s\n' "$*" >>"$POWER_LOG"
EOF
chmod 0755 "$FAKE_QS" "$FAKE_SYSTEMCTL" "$FAKE_LOGINCTL"

run_power() {
    local sequence="$1" action="$2"
    rm -f -- "$COUNTER"
    FAKE_QS_COUNTER="$COUNTER" \
    FAKE_QS_SEQUENCE="$sequence" \
    POWER_LOG="$POWER_LOG" \
    QS_BIN="$FAKE_QS" \
    SYSTEMCTL_BIN="$FAKE_SYSTEMCTL" \
    LOGINCTL_BIN="$FAKE_LOGINCTL" \
    AWTARCHY_LOCK_POLL_INTERVAL=0.01 \
        bash "$MANAGER" "$action"
}

: >"$POWER_LOG"
run_power 'unlocked,starting,secure' hibernate \
    || fail 'hibernate did not proceed after compositor-secure confirmation'
grep -Fxq 'systemctl hibernate' "$POWER_LOG" \
    || fail 'hibernate command was not issued after secure confirmation'

: >"$POWER_LOG"
run_power 'unlocked,starting,secure' suspend \
    || fail 'suspend did not proceed after compositor-secure confirmation'
grep -Fxq 'systemctl suspend -i' "$POWER_LOG" \
    || fail 'suspend command was not issued after secure confirmation'

: >"$POWER_LOG"
if run_power 'unlocked,starting,starting' hibernate >/dev/null 2>&1; then
    fail 'hibernate proceeded without compositor-secure confirmation'
fi
[[ ! -s "$POWER_LOG" ]] \
    || fail 'power transition was attempted before compositor-secure confirmation'

printf 'PASS: lockscreen power transitions require compositor-secure confirmation\n'
