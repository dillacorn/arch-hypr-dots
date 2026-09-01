#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTOR="${ROOT}/config/hypr/scripts/awtarchy_runtime_baseline.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -x "$COLLECTOR" ]] || fail 'runtime baseline collector is missing or not executable'

home="${TMP}/home"
fakebin="${TMP}/bin"
proc_root="${TMP}/proc"
state_home="${TMP}/state"
cache_home="${TMP}/cache"
network_marker="${TMP}/network-called"
mkdir -p \
    "$home" \
    "$fakebin" \
    "$proc_root/4242/task/4242" \
    "$proc_root/4242/task/4243" \
    "$state_home/awtarchy/logs" \
    "$cache_home/awtarchy"

printf '%s\n' \
    '4242 (quickshell) S 1 1 1 0 -1 0 0 0 0 0 100 25 0 0 20 0 2 0 0' \
    >"${proc_root}/4242/stat"
printf '%s\n' 'cpu 1000 0 500 8000 0 0 0 0 0 0' >"${proc_root}/stat"
printf '%s\n' 'fixture quickshell log line one' 'fixture quickshell log line two' \
    >"${cache_home}/awtarchy/quickshell.log"
printf '%s\n' '{"enabled":true,"monitors":{"DP-1":{"position":"top"}}}' \
    >"${cache_home}/awtarchy/quickshell-state.json"
printf '%s\n' 'tag=v3.4.6' >"${state_home}/awtarchy/config-version"
printf '%s\n' 'revision=fixture-runtime' >"${state_home}/awtarchy/command-version"
cat >"${state_home}/awtarchy/git-testing" <<'EOF_STATE'
branch=analysis/runtime-stress-optimization
revision=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
stable_release=v3.4.6
EOF_STATE

cat >"${fakebin}/ps" <<'EOF_PS'
#!/usr/bin/env bash
set -Eeuo pipefail
args="$*"
case "$args" in
    *"-eo pid=,ppid=,comm=,args="*)
        printf '%s\n' \
            '4242 100 qt-main /usr/bin/quickshell -c awtarchy' \
            '4244 4242 bash bash /home/test/.config/hypr/scripts/helper.sh' \
            '5000 1 other other-process'
        ;;
    *"-p 4242 -o etimes="*) printf '%s\n' '321' ;;
    *"-p 4242 -o rss="*) printf '%s\n' '65432' ;;
    *"-p 4242 -o %cpu="*)
        count_file="${TMPDIR:?}/awtarchy-test-ps-count"
        count=0
        [[ -f "$count_file" ]] && read -r count <"$count_file"
        count=$((count + 1))
        printf '%s\n' "$count" >"$count_file"
        if (( count == 1 )); then
            printf '%s\n' '1.2'
        else
            printf '%s\n' '2.4'
        fi
        ;;
    *"--ppid 4242"*)
        printf '%s\n' '4244 4242 bash bash /home/test/.config/hypr/scripts/helper.sh'
        ;;
    *) exit 1 ;;
esac
EOF_PS

cat >"${fakebin}/hyprctl" <<'EOF_HYPR'
#!/usr/bin/env bash
set -Eeuo pipefail
case "$*" in
    version) printf '%s\n' 'Hyprland 0.fixture' ;;
    "monitors -j") printf '%s\n' '[{"name":"DP-1","width":1920,"height":1080,"scale":1.25,"focused":true}]' ;;
    "activeworkspace -j") printf '%s\n' '{"id":2,"name":"2","monitor":"DP-1"}' ;;
    "clients -j") printf '%s\n' '[{"address":"0xabc","class":"Alacritty","title":"Fixture"}]' ;;
    *) exit 1 ;;
esac
EOF_HYPR

cat >"${fakebin}/qs" <<'EOF_QS'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ ${1:-} == --version ]]; then
    printf '%s\n' 'quickshell fixture'
    exit 0
fi
if [[ "$*" == '-c awtarchy list --json' ]]; then
    printf '%s\n' '[{"pid":4242,"id":"fixture"}]'
    exit 0
fi
exit 1
EOF_QS

cat >"${fakebin}/uname" <<'EOF_UNAME'
#!/usr/bin/env bash
printf '%s\n' 'Linux fixture 6.99.0-test x86_64 GNU/Linux'
EOF_UNAME

cat >"${fakebin}/date" <<'EOF_DATE'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
    +%Y%m%d-%H%M%S) printf '%s\n' '20260901-190000' ;;
    --iso-8601=seconds) printf '%s\n' '2026-09-01T19:00:00-04:00' ;;
    *) /usr/bin/date "$@" ;;
esac
EOF_DATE

cat >"${fakebin}/getconf" <<'EOF_GETCONF'
#!/usr/bin/env bash
[[ ${1:-} == _NPROCESSORS_ONLN ]] || exit 1
printf '%s\n' '8'
EOF_GETCONF

cat >"${fakebin}/curl" <<EOF_CURL
#!/usr/bin/env bash
: >"$network_marker"
exit 99
EOF_CURL
cat >"${fakebin}/wget" <<EOF_WGET
#!/usr/bin/env bash
: >"$network_marker"
exit 99
EOF_WGET
chmod +x "${fakebin}/"*

out="${TMP}/collector.out"
TMPDIR="$TMP" \
HOME="$home" \
USER="$(id -un)" \
XDG_STATE_HOME="$state_home" \
XDG_CACHE_HOME="$cache_home" \
AWTARCHY_PROC_ROOT="$proc_root" \
AWTARCHY_SAMPLE_SECONDS=0 \
PATH="${fakebin}:/usr/bin:/bin" \
    "$COLLECTOR" >"$out"

[[ ! -e "$network_marker" ]] || fail 'collector accessed the network'

grep -Fq 'Awtarchy runtime baseline' "$out" || fail 'missing report header'
grep -Fq 'Read-only collector: yes' "$out" || fail 'missing read-only statement'
grep -Fq 'Quickshell PID: 4242' "$out" || fail 'collector did not discover PID from qs instance list'
grep -Fq 'Quickshell uptime seconds: 321' "$out" || fail 'missing Quickshell uptime'
grep -Fq 'Quickshell RSS KiB: 65432' "$out" || fail 'missing Quickshell RSS'
grep -Fq 'Quickshell threads: 2' "$out" || fail 'missing Quickshell thread count'
grep -Fq 'Quickshell CPU sample 1: 1.2%' "$out" || fail 'missing first CPU sample'
grep -Fq 'Quickshell CPU sample 2: 2.4%' "$out" || fail 'missing second CPU sample'
grep -Fq 'Hyprland 0.fixture' "$out" || fail 'missing Hyprland version'
grep -Fq 'quickshell fixture' "$out" || fail 'missing Quickshell version'
grep -Fq '"name":"DP-1"' "$out" || fail 'missing monitor JSON'
grep -Fq '"monitor":"DP-1"' "$out" || fail 'missing active workspace JSON'
grep -Fq '"class":"Alacritty"' "$out" || fail 'missing clients JSON'
grep -Fq '"position":"top"' "$out" || fail 'missing Quickshell state'
grep -Fq 'branch=analysis/runtime-stress-optimization' "$out" || fail 'missing git-testing state'
grep -Fq 'tag=v3.4.6' "$out" || fail 'missing config-version state'
grep -Fq 'revision=fixture-runtime' "$out" || fail 'missing command-version state'
grep -Fq 'fixture quickshell log line two' "$out" || fail 'missing Quickshell log tail'
grep -Fq '4244 4242 bash bash /home/test/.config/hypr/scripts/helper.sh' "$out" \
    || fail 'missing Quickshell child/helper process listing'

auto_report="${state_home}/awtarchy/logs/runtime-baseline-20260901-190000.log"
[[ -f "$auto_report" ]] || fail 'timestamped baseline report was not written'
cmp -s "$out" "$auto_report" || fail 'saved report differs from stdout report'

printf '%s\n' 'PASS: runtime baseline collector records read-only session evidence without network access.'