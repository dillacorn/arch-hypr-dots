#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTOR="${ROOT}/config/hypr/scripts/awtarchy_ui_latency.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -x "$COLLECTOR" ]] || fail 'UI latency collector is missing or not executable'

fakebin="${TMP}/bin"
state_home="${TMP}/state"
runtime_state="${TMP}/active-surface"
clock_state="${TMP}/clock"
mkdir -p "$fakebin" "${state_home}/awtarchy/logs"
printf '%s\n' '1000000000' >"$clock_state"

cat >"${fakebin}/qs" <<EOF_QS
#!/usr/bin/env bash
set -Eeuo pipefail
state='$runtime_state'
mode="\${AWTARCHY_UI_TEST_MODE:-success}"
if [[ "\$*" == '-c awtarchy ipc call control ping' ]]; then
    printf '%s\n' 'ok'
    exit 0
fi
if [[ \${1:-} == -c && \${2:-} == awtarchy && \${3:-} == ipc && \${4:-} == call ]]; then
    target="\${5:-}"
    action="\${6:-}"
    case "\$action" in
        open)
            if [[ "\$mode" == failures && "\$target" == network ]]; then
                exit 7
            fi
            printf '%s\n' "\$target" >"\$state"
            ;;
        close)
            if [[ -r "\$state" ]] && [[ \$(cat "\$state") == "\$target" ]]; then
                rm -f -- "\$state"
            fi
            ;;
        *) exit 1 ;;
    esac
    exit 0
fi
exit 1
EOF_QS

cat >"${fakebin}/hyprctl" <<EOF_HYPR
#!/usr/bin/env bash
set -Eeuo pipefail
state='$runtime_state'
mode="\${AWTARCHY_UI_TEST_MODE:-success}"
if [[ "\$*" == '-j monitors' || "\$*" == 'monitors -j' ]]; then
    printf '%s\n' '[{"name":"DP-1","focused":true}]'
    exit 0
fi
if [[ "\$*" == '-j clients' || "\$*" == 'clients -j' ]]; then
    if [[ ! -r "\$state" ]]; then
        printf '%s\n' '[]'
        exit 0
    fi
    target="\$(cat "\$state")"
    if [[ "\$mode" == failures && "\$target" == bluetooth ]]; then
        printf '%s\n' '[]'
        exit 0
    fi
    case "\$target" in
        launcher) title='Awtarchy Application Search' ;;
        clipboard) title='Awtarchy Clipboard History' ;;
        quicksettings) title='Awtarchy Quick Settings' ;;
        network) title='Awtarchy Network' ;;
        bluetooth) title='Awtarchy Bluetooth' ;;
        *) title='Unknown' ;;
    esac
    printf '[{"mapped":true,"title":"%s"}]\n' "\$title"
    exit 0
fi
exit 1
EOF_HYPR

cat >"${fakebin}/jq" <<'EOF_JQ'
#!/usr/bin/env python3
import json
import sys

args = sys.argv[1:]
data = json.load(sys.stdin)
if 'select(.focused == true)' in ' '.join(args):
    for item in data:
        if item.get('focused') is True:
            print(item.get('name', ''))
            break
    sys.exit(0)

title = ''
if '--arg' in args:
    idx = args.index('--arg')
    title = args[idx + 2]
matched = any(item.get('mapped', True) is True and item.get('title', '') == title for item in data)
sys.exit(0 if matched else 1)
EOF_JQ

cat >"${fakebin}/date" <<EOF_DATE
#!/usr/bin/env bash
set -Eeuo pipefail
clock='$clock_state'
case "\${1:-}" in
    +%s%N)
        value="\$(cat "\$clock")"
        printf '%s\n' "\$value"
        printf '%s\n' "\$((value + 10000000))" >"\$clock"
        ;;
    +%Y%m%d-%H%M%S) printf '%s\n' '20260901-191000' ;;
    --iso-8601=seconds) printf '%s\n' '2026-09-01T19:10:00-04:00' ;;
    *) /usr/bin/date "\$@" ;;
esac
EOF_DATE

cat >"${fakebin}/sleep" <<'EOF_SLEEP'
#!/usr/bin/env bash
exit 0
EOF_SLEEP
chmod +x "${fakebin}/"*

out="${TMP}/collector.out"
HOME="${TMP}/home" \
XDG_STATE_HOME="$state_home" \
AWTARCHY_UI_LATENCY_CYCLES=2 \
AWTARCHY_UI_LATENCY_TIMEOUT_MS=100 \
AWTARCHY_UI_LATENCY_POLL_MS=1 \
AWTARCHY_UI_LATENCY_SETTLE_MS=0 \
PATH="${fakebin}:/usr/bin:/bin" \
    "$COLLECTOR" >"$out"

grep -Fq 'Awtarchy UI latency baseline' "$out" || fail 'missing report header'
grep -Fq 'Focused monitor: DP-1' "$out" || fail 'missing focused monitor'
for surface in launcher clipboard quicksettings network bluetooth; do
    grep -Fq "=== ${surface} ===" "$out" || fail "missing ${surface} section"
    [[ $(grep -c "^${surface} cycle" "$out") -eq 2 ]] || fail "wrong ${surface} cycle count"
    grep -Fq "${surface} summary: min=10.00ms median=10.00ms avg=10.00ms max=10.00ms" "$out" \
        || fail "missing deterministic ${surface} summary"
done
[[ ! -e "$runtime_state" ]] || fail 'collector left a flyout open after successful run'
report="${state_home}/awtarchy/logs/ui-latency-20260901-191000.log"
[[ -f "$report" ]] || fail 'timestamped UI latency report was not written'
cmp -s "$out" "$report" || fail 'saved UI latency report differs from stdout'

printf '%s\n' '2000000000' >"$clock_state"
failure_out="${TMP}/failures.out"
AWTARCHY_UI_TEST_MODE=failures \
HOME="${TMP}/home" \
XDG_STATE_HOME="$state_home" \
AWTARCHY_UI_LATENCY_CYCLES=1 \
AWTARCHY_UI_LATENCY_TIMEOUT_MS=20 \
AWTARCHY_UI_LATENCY_POLL_MS=1 \
AWTARCHY_UI_LATENCY_SETTLE_MS=0 \
PATH="${fakebin}:/usr/bin:/bin" \
    "$COLLECTOR" >"$failure_out"

grep -Fq 'network failures: timeouts=0 ipc_errors=1' "$failure_out" \
    || fail 'network IPC failure was not reported separately'
grep -Fq 'bluetooth failures: timeouts=1 ipc_errors=0' "$failure_out" \
    || fail 'bluetooth timeout was not reported separately'
[[ ! -e "$runtime_state" ]] || fail 'collector left a flyout open after failure run'

printf '%s\n' 'PASS: UI latency collector measures mapped-open latency, reports failures separately, and restores closed state.'