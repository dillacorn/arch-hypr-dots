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
sequence="${TMP}/sequence"
baseline_count="${TMP}/baseline-count"
qs_calls="${TMP}/qs-calls"
mkdir -p "$fakebin" "$state_home/awtarchy/logs"
printf '%s\n' 0 >"$baseline_count"
: >"$sequence"
: >"$qs_calls"

cat >"${fakebin}/baseline" <<EOF_BASELINE
#!/usr/bin/env bash
set -Eeuo pipefail
count_file='$baseline_count'
sequence='$sequence'
count="\$(cat "\$count_file")"
count=\$((count + 1))
printf '%s\n' "\$count" >"\$count_file"
if (( count == 1 )); then
    printf '%s\n' baseline-pre >>"\$sequence"
    rss=100000
    threads=12
else
    printf '%s\n' baseline-post >>"\$sequence"
    rss=101024
    threads=12
fi
printf '%s\n' \
    'Awtarchy runtime baseline' \
    "Quickshell RSS KiB: \$rss" \
    "Quickshell threads: \$threads" \
    '=== Quickshell direct children/helpers ===' \
    '111 1 helper helper-one' \
    '112 1 helper helper-two' \
    '' \
    '=== Versions ==='
EOF_BASELINE

cat >"${fakebin}/latency" <<EOF_LATENCY
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' ui-latency >>'$sequence'
printf '%s\n' \
    'Awtarchy UI latency baseline' \
    'launcher cycle 1: 10.00ms' \
    'network failures: timeouts=1 ipc_errors=0'
EOF_LATENCY

cat >"${fakebin}/readiness" <<EOF_READINESS
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' content-readiness >>'$sequence'
printf '%s\n' \
    'Awtarchy content readiness baseline' \
    'launcher cycle 1: mapped=10.00ms ready=20.00ms results=12' \
    'clipboard cycle 1: mapped=10.00ms first_entry=20.00ms first_visible=30.00ms first_thumbnail=n/a candidates=0'
EOF_READINESS

cat >"${fakebin}/qs" <<EOF_QS
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "\$*" >>'$qs_calls'
if [[ "\$*" == '-c awtarchy ipc call control ping' ]]; then
    printf '%s\n' ok
    exit 0
fi
if [[ \${1:-} == -c && \${2:-} == awtarchy && \${3:-} == ipc && \${4:-} == call ]]; then
    exit 0
fi
exit 1
EOF_QS

cat >"${fakebin}/date" <<'EOF_DATE'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
    +%Y%m%d-%H%M%S) printf '%s\n' '20260901-193000' ;;
    --iso-8601=seconds) printf '%s\n' '2026-09-01T19:30:00-04:00' ;;
    *) /usr/bin/date "$@" ;;
esac
EOF_DATE

cat >"${fakebin}/sleep" <<'EOF_SLEEP'
#!/usr/bin/env bash
exit 0
EOF_SLEEP
chmod +x "${fakebin}/"*

out="${TMP}/run.out"
HOME="${TMP}/home" \
XDG_STATE_HOME="$state_home" \
AWTARCHY_BASELINE_COLLECTOR="${fakebin}/baseline" \
AWTARCHY_UI_LATENCY_COLLECTOR="${fakebin}/latency" \
AWTARCHY_CONTENT_READINESS_COLLECTOR="${fakebin}/readiness" \
AWTARCHY_STRESS_OPEN_CLOSE_CYCLES=2 \
PATH="${fakebin}:/usr/bin:/bin" \
    "$RUNNER" run >"$out"

run_dir="${state_home}/awtarchy/logs/runtime-stress-20260901-193000"
[[ -d "$run_dir" ]] || fail 'run directory was not created'
for file in baseline-pre.log ui-latency.log content-readiness.log transient-stress.log baseline-post.log summary.log; do
    [[ -f "${run_dir}/${file}" ]] || fail "missing run artifact: ${file}"
done

mapfile -t sequence_lines <"$sequence"
[[ ${sequence_lines[0]:-} == baseline-pre ]] || fail 'baseline pre did not run first'
[[ ${sequence_lines[1]:-} == ui-latency ]] || fail 'UI latency did not run second'
[[ ${sequence_lines[2]:-} == content-readiness ]] || fail 'content readiness did not run third'
[[ ${sequence_lines[3]:-} == baseline-post ]] || fail 'baseline post did not run after transient stress'

grep -Fq 'Quickshell RSS pre KiB: 100000' "${run_dir}/summary.log" || fail 'missing pre RSS summary'
grep -Fq 'Quickshell RSS post KiB: 101024' "${run_dir}/summary.log" || fail 'missing post RSS summary'
grep -Fq 'Quickshell RSS delta KiB: 1024' "${run_dir}/summary.log" || fail 'missing RSS delta'
grep -Fq 'Quickshell threads pre: 12' "${run_dir}/summary.log" || fail 'missing pre thread count'
grep -Fq 'Quickshell threads post: 12' "${run_dir}/summary.log" || fail 'missing post thread count'
grep -Fq 'Quickshell direct helpers pre: 2' "${run_dir}/summary.log" || fail 'missing pre helper count'
grep -Fq 'Quickshell direct helpers post: 2' "${run_dir}/summary.log" || fail 'missing post helper count'
grep -Fq 'network failures: timeouts=1 ipc_errors=0' "${run_dir}/summary.log" \
    || fail 'collector failure line was not propagated to summary'
grep -Fq 'Short-run RSS change is not a memory-leak determination.' "${run_dir}/summary.log" \
    || fail 'missing memory-leak caution'
grep -Fq 'Run directory:' "$out" || fail 'runner did not print run directory'

for target in launcher clipboard quicksettings network bluetooth; do
    [[ $(grep -c -- "-c awtarchy ipc call ${target} open" "$qs_calls") -eq 2 ]] \
        || fail "wrong transient open count for ${target}"
    [[ $(grep -c -- "-c awtarchy ipc call ${target} close" "$qs_calls") -ge 2 ]] \
        || fail "missing transient closes for ${target}"
done

grep -Eq 'systemctl|loginctl|hyprctl[[:space:]]+dispatch[[:space:]]+dpms' "$RUNNER" \
    && fail 'runner contains disruptive host actions'

snapshot_out="${TMP}/snapshot.out"
HOME="${TMP}/home" \
XDG_STATE_HOME="$state_home" \
AWTARCHY_BASELINE_COLLECTOR="${fakebin}/baseline" \
PATH="${fakebin}:/usr/bin:/bin" \
    "$RUNNER" snapshot fullscreen-before >"$snapshot_out"
snapshot="${state_home}/awtarchy/logs/runtime-stress-snapshot-20260901-193000-fullscreen-before.log"
[[ -f "$snapshot" ]] || fail 'snapshot report was not created'
grep -Fq 'Snapshot label: fullscreen-before' "$snapshot" || fail 'snapshot label missing from report'

after_snapshot_qs_count="$(wc -l <"$qs_calls")"
HOME="${TMP}/home" \
XDG_STATE_HOME="$state_home" \
AWTARCHY_BASELINE_COLLECTOR="${fakebin}/baseline" \
PATH="${fakebin}:/usr/bin:/bin" \
    "$RUNNER" snapshot monitor/unsafe >/dev/null 2>&1 && fail 'unsafe snapshot label was accepted'
[[ $(wc -l <"$qs_calls") -eq $after_snapshot_qs_count ]] || fail 'snapshot mode ran UI stress'

printf '%s\n' 'PASS: runtime stress runner orchestrates safe session stress and read-only checkpoints.'