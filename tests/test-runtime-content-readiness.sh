#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTOR="${ROOT}/config/hypr/scripts/awtarchy_content_readiness.sh"
LAUNCHER="${ROOT}/config/quickshell/awtarchy/Launcher.qml"
CLIPBOARD="${ROOT}/config/quickshell/awtarchy/ClipboardMenu.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

for needle in \
    'readonly property int diagnosticResultCount:' \
    'readonly property bool diagnosticReady:'; do
    grep -Fq "$needle" "$LAUNCHER" || fail "launcher diagnostic is missing: $needle"
done
for needle in \
    'readonly property int diagnosticEntryCount:' \
    'readonly property bool diagnosticFirstRowReady:' \
    'readonly property int diagnosticThumbnailCandidateCount:' \
    'readonly property int diagnosticThumbnailReadyCount:' \
    'readonly property bool diagnosticListLoading:'; do
    grep -Fq "$needle" "$CLIPBOARD" || fail "clipboard diagnostic is missing: $needle"
done
[[ -x "$COLLECTOR" ]] || fail 'content readiness collector is missing or not executable'
grep -Fq 'ipc prop get "$target" "$property"' "$COLLECTOR" \
    || fail 'collector does not use read-only Quickshell IPC property reads'

fakebin="${TMP}/bin"
state_home="${TMP}/state"
runtime_state="${TMP}/active-surface"
clock_state="${TMP}/clock"
thumb_mode="${TMP}/thumbnail-mode"
mkdir -p "$fakebin" "${state_home}/awtarchy/logs"
printf '%s\n' '1000000000' >"$clock_state"
printf '%s\n' 'with-thumbnails' >"$thumb_mode"

cat >"${fakebin}/qs" <<EOF_QS
#!/usr/bin/env bash
set -Eeuo pipefail
state='$runtime_state'
thumb_mode='$thumb_mode'
if [[ "\$*" == '-c awtarchy ipc call control ping' ]]; then
    printf '%s\n' ok
    exit 0
fi
if [[ \${1:-} == -c && \${2:-} == awtarchy && \${3:-} == ipc && \${4:-} == call ]]; then
    target="\${5:-}"
    action="\${6:-}"
    case "\$action" in
        open) printf '%s\n' "\$target" >"\$state" ;;
        close)
            if [[ -r "\$state" ]] && [[ \$(cat "\$state") == "\$target" ]]; then
                rm -f -- "\$state"
            fi
            ;;
        *) exit 1 ;;
    esac
    exit 0
fi
if [[ \${1:-} == -c && \${2:-} == awtarchy && \${3:-} == ipc \
        && \${4:-} == prop && \${5:-} == get ]]; then
    target="\${6:-}"
    property="\${7:-}"
    active=''
    [[ -r "\$state" ]] && active="\$(cat "\$state")"
    mode="\$(cat "\$thumb_mode")"
    case "\$target:\$property" in
        launcher:diagnosticResultCount) [[ "\$active" == launcher ]] && printf '%s\n' 12 || printf '%s\n' 0 ;;
        launcher:diagnosticReady) [[ "\$active" == launcher ]] && printf '%s\n' true || printf '%s\n' false ;;
        clipboard:diagnosticEntryCount) [[ "\$active" == clipboard ]] && printf '%s\n' 8 || printf '%s\n' 0 ;;
        clipboard:diagnosticFirstRowReady) [[ "\$active" == clipboard ]] && printf '%s\n' true || printf '%s\n' false ;;
        clipboard:diagnosticThumbnailCandidateCount)
            if [[ "\$active" != clipboard ]]; then printf '%s\n' 0
            elif [[ "\$mode" == no-thumbnails ]]; then printf '%s\n' 0
            else printf '%s\n' 2; fi
            ;;
        clipboard:diagnosticThumbnailReadyCount)
            if [[ "\$active" == clipboard && "\$mode" != no-thumbnails ]]; then printf '%s\n' 1
            else printf '%s\n' 0; fi
            ;;
        clipboard:diagnosticListLoading) printf '%s\n' false ;;
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
if [[ "\$*" == '-j monitors' || "\$*" == 'monitors -j' ]]; then
    printf '%s\n' '[{"name":"DP-1","focused":true}]'
    exit 0
fi
if [[ "\$*" == '-j clients' || "\$*" == 'clients -j' ]]; then
    if [[ ! -r "\$state" ]]; then printf '%s\n' '[]'; exit 0; fi
    case "\$(cat "\$state")" in
        launcher) title='Awtarchy Application Search' ;;
        clipboard) title='Awtarchy Clipboard History' ;;
        *) title='Unknown' ;;
    esac
    printf '[{"mapped":true,"title":"%s"}]\n' "\$title"
    exit 0
fi
exit 1
EOF_HYPR

cat >"${fakebin}/jq" <<'EOF_JQ'
#!/usr/bin/env python3
import json, sys
args = sys.argv[1:]
data = json.load(sys.stdin)
joined = ' '.join(args)
if 'select(.focused == true)' in joined:
    for item in data:
        if item.get('focused') is True:
            print(item.get('name', ''))
            break
    sys.exit(0)
title = ''
if '--arg' in args:
    i = args.index('--arg')
    title = args[i + 2]
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
    +%Y%m%d-%H%M%S) printf '%s\n' '20260901-192000' ;;
    --iso-8601=seconds) printf '%s\n' '2026-09-01T19:20:00-04:00' ;;
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
AWTARCHY_CONTENT_READINESS_CYCLES=2 \
AWTARCHY_CONTENT_READINESS_TIMEOUT_MS=100 \
AWTARCHY_CONTENT_READINESS_POLL_MS=1 \
AWTARCHY_CONTENT_READINESS_SETTLE_MS=0 \
PATH="${fakebin}:/usr/bin:/bin" \
    "$COLLECTOR" >"$out"

grep -Fq 'Awtarchy content readiness baseline' "$out" || fail 'missing report header'
grep -Fq 'Focused monitor: DP-1' "$out" || fail 'missing focused monitor'
[[ $(grep -c '^launcher cycle ' "$out") -eq 2 ]] || fail 'wrong launcher cycle count'
[[ $(grep -c '^clipboard cycle ' "$out") -eq 2 ]] || fail 'wrong clipboard cycle count'
grep -Eq '^launcher cycle 1: mapped=[0-9.]+ms ready=[0-9.]+ms results=12$' "$out" \
    || fail 'launcher cycle does not report mapped and readiness timing'
grep -Eq '^clipboard cycle 1: mapped=[0-9.]+ms first_entry=[0-9.]+ms first_visible=[0-9.]+ms first_thumbnail=[0-9.]+ms candidates=2$' "$out" \
    || fail 'clipboard cycle does not report entry, visible-row, and thumbnail timing'
grep -Fq 'launcher mapped summary:' "$out" || fail 'missing launcher mapped summary'
grep -Fq 'launcher ready summary:' "$out" || fail 'missing launcher readiness summary'
grep -Fq 'clipboard mapped summary:' "$out" || fail 'missing clipboard mapped summary'
grep -Fq 'clipboard first entry summary:' "$out" || fail 'missing clipboard first-entry summary'
grep -Fq 'clipboard first visible summary:' "$out" || fail 'missing clipboard first-visible summary'
grep -Fq 'clipboard first thumbnail summary:' "$out" || fail 'missing clipboard thumbnail summary'
[[ ! -e "$runtime_state" ]] || fail 'collector left a measured surface open'
report="${state_home}/awtarchy/logs/content-readiness-20260901-192000.log"
[[ -f "$report" ]] || fail 'timestamped content-readiness report was not written'
cmp -s "$out" "$report" || fail 'saved content-readiness report differs from stdout'

printf '%s\n' 'no-thumbnails' >"$thumb_mode"
printf '%s\n' '3000000000' >"$clock_state"
no_thumb_out="${TMP}/no-thumb.out"
HOME="${TMP}/home" \
XDG_STATE_HOME="$state_home" \
AWTARCHY_CONTENT_READINESS_CYCLES=1 \
AWTARCHY_CONTENT_READINESS_TIMEOUT_MS=100 \
AWTARCHY_CONTENT_READINESS_POLL_MS=1 \
AWTARCHY_CONTENT_READINESS_SETTLE_MS=0 \
PATH="${fakebin}:/usr/bin:/bin" \
    "$COLLECTOR" >"$no_thumb_out"
grep -Eq '^clipboard cycle 1: mapped=[0-9.]+ms first_entry=[0-9.]+ms first_visible=[0-9.]+ms first_thumbnail=n/a candidates=0$' "$no_thumb_out" \
    || fail 'zero-thumbnail clipboard path did not report n/a'
! grep -Fq 'clipboard cycle 1: TIMEOUT' "$no_thumb_out" \
    || fail 'zero-thumbnail clipboard path timed out'
[[ ! -e "$runtime_state" ]] || fail 'collector left a surface open after zero-thumbnail run'

printf '%s\n' 'PASS: content readiness collector measures usable launcher and clipboard content without changing runtime state.'