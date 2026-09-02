#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/config/hypr/scripts/awtarchy_runtime_stress.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -x "$RUNNER" ]] || fail 'runtime stress runner is missing or not executable'

fakebin="${TMP}/bin"
state_home="${TMP}/state"
count_file="${TMP}/baseline-count"
mkdir -p "$fakebin" "$state_home/awtarchy/logs"
printf '%s\n' 0 >"$count_file"

cat >"${fakebin}/baseline" <<EOF_BASELINE
#!/usr/bin/env bash
set -Eeuo pipefail
count_file='$count_file'
count="\$(cat "\$count_file")"
count=\$((count + 1))
printf '%s\n' "\$count" >"\$count_file"
case "\$count" in
    1) rss=100000; threads=20 ;;
    2) rss=120000; threads=40 ;;
    *) rss=121024; threads=40 ;;
esac
printf '%s\n' \
    'Awtarchy runtime baseline' \
    "Quickshell uptime seconds: \$((count * 10))" \
    "Quickshell RSS KiB: \$rss" \
    "Quickshell threads: \$threads" \
    '=== Quickshell direct children/helpers ===' \
    '111 1 helper helper-one' \
    '' \
    '=== Versions ==='
EOF_BASELINE

cat >"${fakebin}/latency" <<'EOF_LATENCY'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' 'Awtarchy UI latency baseline'
EOF_LATENCY

cat >"${fakebin}/readiness" <<'EOF_READINESS'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' 'Awtarchy content readiness baseline'
EOF_READINESS

cat >"${fakebin}/qs" <<'EOF_QS'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$*" == '-c awtarchy ipc call control ping' ]]; then
    printf '%s\n' ok
    exit 0
fi
if [[ ${1:-} == -c && ${2:-} == awtarchy && ${3:-} == ipc && ${4:-} == call ]]; then
    exit 0
fi
exit 1
EOF_QS

cat >"${fakebin}/date" <<'EOF_DATE'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
    +%Y%m%d-%H%M%S) printf '%s\n' '20260901-194000' ;;
    --iso-8601=seconds) printf '%s\n' '2026-09-01T19:40:00-04:00' ;;
    *) /usr/bin/date "$@" ;;
esac
EOF_DATE

cat >"${fakebin}/sleep" <<'EOF_SLEEP'
#!/usr/bin/env bash
exit 0
EOF_SLEEP
chmod +x "${fakebin}/"*

HOME="${TMP}/home" \
XDG_STATE_HOME="$state_home" \
AWTARCHY_BASELINE_COLLECTOR="${fakebin}/baseline" \
AWTARCHY_UI_LATENCY_COLLECTOR="${fakebin}/latency" \
AWTARCHY_CONTENT_READINESS_COLLECTOR="${fakebin}/readiness" \
AWTARCHY_STRESS_OPEN_CLOSE_CYCLES=1 \
AWTARCHY_STRESS_SETTLE_SECONDS=0 \
PATH="${fakebin}:/usr/bin:/bin" \
    "$RUNNER" run >/dev/null

run_dir="${state_home}/awtarchy/logs/runtime-stress-20260901-194000"
[[ -f "${run_dir}/baseline-cold.log" ]] || fail 'cold-start baseline artifact is missing'
[[ -f "${run_dir}/baseline-pre.log" ]] || fail 'warmed pre-stress baseline artifact is missing'
[[ -f "${run_dir}/baseline-post.log" ]] || fail 'post-stress baseline artifact is missing'
[[ $(cat "$count_file") -eq 3 ]] || fail 'runner did not collect exactly three baselines'

grep -Fq 'Quickshell RSS cold KiB: 100000' "${run_dir}/summary.log" \
    || fail 'summary does not preserve cold-start RSS'
grep -Fq 'Quickshell RSS pre KiB: 120000' "${run_dir}/summary.log" \
    || fail 'summary does not use warmed pre-stress RSS'
grep -Fq 'Quickshell RSS post KiB: 121024' "${run_dir}/summary.log" \
    || fail 'summary does not report post-stress RSS'
grep -Fq 'Quickshell RSS delta KiB: 1024' "${run_dir}/summary.log" \
    || fail 'stress RSS delta is not based on warmed pre-stress state'
grep -Fq 'Quickshell threads cold: 20' "${run_dir}/summary.log" \
    || fail 'summary does not preserve cold-start thread count'
grep -Fq 'Quickshell threads pre: 40' "${run_dir}/summary.log" \
    || fail 'summary does not use warmed pre-stress thread count'
grep -Fq 'Cold-start to warmed change is initialization evidence, not stress growth.' "${run_dir}/summary.log" \
    || fail 'summary does not explain cold-start initialization'

printf '%s\n' 'PASS: runtime stress summary separates cold initialization from warmed stress growth.'
