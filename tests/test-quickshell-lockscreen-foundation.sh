#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_DIR="${ROOT}/config/quickshell/awtarchy-lock"
SHELL_QML="${LOCK_DIR}/shell.qml"
SURFACE_QML="${LOCK_DIR}/LockSurface.qml"
SCENE_QML="${LOCK_DIR}/LockScene.qml"
AUTH_QML="${LOCK_DIR}/LockAuth.qml"
THEME_QML="${LOCK_DIR}/LockTheme.qml"
PAM_CONFIG="${LOCK_DIR}/pam/password.conf"
MANAGER="${ROOT}/config/hypr/scripts/awtarchy_lock.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || fail "missing $1"
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

reject_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

require_file "$SHELL_QML"
require_file "$SURFACE_QML"
require_file "$SCENE_QML"
require_file "$AUTH_QML"
require_file "$THEME_QML"
require_file "$PAM_CONFIG"
require_file "$MANAGER"

require_text "$SHELL_QML" 'import Quickshell.Wayland' \
    'lock shell does not import Quickshell.Wayland'
require_text "$SHELL_QML" 'import Quickshell.Io' \
    'lock shell does not import Quickshell.Io for IpcHandler'
require_text "$SHELL_QML" 'WlSessionLock {' \
    'lock shell does not own a WlSessionLock'
require_text "$SHELL_QML" 'locked: true' \
    'production lock does not start with WlSessionLock locked'
require_text "$SHELL_QML" 'target: "lock"' \
    'lock shell does not expose the dedicated lock IPC target'
require_text "$SHELL_QML" 'sessionLock.secure ? "secure"' \
    'IPC secure state is not derived from WlSessionLock.secure'
require_text "$SHELL_QML" 'sessionLock.locked = false' \
    'successful authentication does not request compositor unlock'

# Security remains on LockSurface even though presentation is shared with the
# unlocked editor through LockScene.
require_text "$SURFACE_QML" 'WlSessionLockSurface {' \
    'lock surface is not a real WlSessionLockSurface'
require_text "$SURFACE_QML" 'color: "#000000"' \
    'lock surface does not use an opaque black compositor-surface base'
require_text "$SURFACE_QML" 'LockScene {' \
    'secure lock surface does not embed the shared presentation scene'
reject_text "$SCENE_QML" 'WlSessionLock' \
    'shared presentation scene owns session-lock authority'
reject_text "$SCENE_QML" 'LockAuth' \
    'shared presentation scene references PAM ownership'
reject_text "$SCENE_QML" 'auth.submit' \
    'shared presentation scene can submit authentication'
reject_text "$SCENE_QML" '/fastfetch/ascii/awtarchy.txt' \
    'shared lock scene still references the retired Fastfetch ASCII mark'
require_text "$SCENE_QML" '▄▄▄      ██     █ ▄▄▄█████ ▄▄▄      ██▀███  ▄████▄  ██  ██ ██   ██' \
    'shared lock scene does not use the approved large Awtarchy ASCII wordmark'
reject_text "$SCENE_QML" 'text: "── AWTARCHY ──"' \
    'shared lock scene still uses the retired compact Awtarchy heading'

require_text "$SURFACE_QML" 'echoMode: TextInput.Password' \
    'password field is not always masked for the password-only PAM service'
require_text "$SURFACE_QML" 'inputMethodHints: Qt.ImhSensitiveData' \
    'password field is not marked as sensitive input'
require_text "$SURFACE_QML" 'color: "transparent"' \
    'native password glyphs are still directly visible instead of using the custom mask'
require_text "$SURFACE_QML" 'readonly property int maskedCount: Math.min(password.text.length, 10)' \
    'custom password mask does not cap displayed password length'
require_text "$SURFACE_QML" 'model: root.maskedCount' \
    'custom block mask is not driven by the capped password length'
require_text "$SURFACE_QML" 'readonly property real maskSpread:' \
    'password mask has no progressive blocky spread effect'
require_text "$SURFACE_QML" 'enabled: !auth.busy || auth.responseRequired' \
    'lock input is disabled when an active PAM conversation asks for another response'
require_text "$SURFACE_QML" 'if ((auth.busy && !auth.responseRequired) || password.text.length === 0)' \
    'lock surface cannot submit a later PAM response while authentication remains active'
require_text "$SURFACE_QML" 'function onResponseRequiredChanged()' \
    'lock surface does not restore input focus for later PAM response prompts'
require_text "$SURFACE_QML" 'Keys.onEscapePressed' \
    'lock surface does not handle Escape safely'
require_text "$SURFACE_QML" 'auth.clearStatus()' \
    'Escape does not clear only transient authentication UI state'

require_text "$AUTH_QML" 'import Quickshell.Services.Pam' \
    'lock authentication does not import Quickshell.Services.Pam'
require_text "$AUTH_QML" 'PamContext {' \
    'lock authentication does not use PamContext'
require_text "$AUTH_QML" 'configDirectory: "pam"' \
    'lock authentication does not use the dedicated password-only PAM directory'
require_text "$AUTH_QML" 'config: "password.conf"' \
    'lock authentication does not use the dedicated password-only PAM service'
reject_text "$AUTH_QML" 'config: "login"' \
    'lock authentication still uses the general login PAM stack'
require_text "$AUTH_QML" 'readonly property bool responseRequired: pam.responseRequired' \
    'lock authentication does not expose active PAM response demand to the input surface'
require_text "$AUTH_QML" 'pam.start();' \
    'lock authentication never starts PAM'
reject_text "$AUTH_QML" 'if (!pam.start())' \
    'lock authentication incorrectly treats PamContext.start as a boolean result'
require_text "$AUTH_QML" 'if (responseRequired && root.pendingResponse.length > 0)' \
    'lock authentication does not answer the password prompt from PAM message delivery'
require_text "$AUTH_QML" 'pam.respond(root.pendingResponse)' \
    'lock authentication does not answer PAM in process memory'
require_text "$AUTH_QML" 'root.pendingResponse = ""' \
    'lock authentication does not clear the pending response'
require_text "$AUTH_QML" 'PamResult.Success' \
    'lock authentication does not gate success on PAM success'
reject_text "$AUTH_QML" 'Process {' \
    'authentication must not send secrets through a shell Process'
reject_text "$AUTH_QML" 'Quickshell.execDetached' \
    'authentication must not send secrets through detached commands'
reject_text "$AUTH_QML" 'console.log' \
    'authentication must not log PAM conversation data'

[[ "$(tr -d '\r' <"$PAM_CONFIG")" == 'auth required pam_unix.so' ]] \
    || fail 'dedicated lock PAM service is not password-only pam_unix authentication'

require_text "$THEME_QML" '/quickshell/awtarchy/theme.json' \
    'lock theme does not consume the existing local Awtarchy theme state'
require_text "$THEME_QML" '"#000000"' \
    'lock theme has no safe black fallback'
reject_text "$THEME_QML" 'function data() {' \
    'LockTheme shadows the inherited read-only Item.data property'
require_text "$THEME_QML" 'function themeData() {' \
    'LockTheme does not use a non-conflicting JSON reader name'

require_text "$MANAGER" 'CONFIG_NAME="awtarchy-lock"' \
    'lock manager does not target only awtarchy-lock'
# The expansion syntax below is intentionally matched as literal shell source.
# shellcheck disable=SC2016
require_text "$MANAGER" 'QS_BIN="${QS_BIN:-qs}"' \
    'lock manager does not provide a testable exact qs command boundary'
require_text "$MANAGER" 'wait-secure)' \
    'lock manager has no wait-secure command'
require_text "$MANAGER" 'stop-test)' \
    'lock manager has no stop-test command'
reject_text "$MANAGER" 'killall' \
    'lock manager must not broadly kill processes'
reject_text "$MANAGER" 'pkill' \
    'lock manager must not use generic pkill'
reject_text "$MANAGER" 'CONFIG_NAME="awtarchy"' \
    'lock manager must not target the normal Awtarchy shell'

FAKE_QS="$TMP/qs"
FAKE_STATE="$TMP/state"
FAKE_LOG="$TMP/qs.log"
FAKE_COUNTER="$TMP/counter"
cat >"$FAKE_QS" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

: "${FAKE_QS_STATE:?}"
: "${FAKE_QS_LOG:?}"
: "${FAKE_QS_COUNTER:?}"
printf '%s\n' "$*" >>"$FAKE_QS_LOG"

[[ ${1:-} == -c && ${2:-} == awtarchy-lock ]] || exit 64
shift 2

if [[ $# -eq 0 ]]; then
    printf 'starting\n' >"$FAKE_QS_STATE"
    exit 0
fi

if [[ $* == 'ipc call lock state' ]]; then
    if [[ -n ${FAKE_QS_SEQUENCE:-} ]]; then
        IFS=',' read -r -a states <<<"$FAKE_QS_SEQUENCE"
        index="$(cat "$FAKE_QS_COUNTER" 2>/dev/null || printf '0')"
        [[ $index =~ ^[0-9]+$ ]] || index=0
        if (( index >= ${#states[@]} )); then
            index=$((${#states[@]} - 1))
        fi
        printf '%s\n' "${states[$index]}"
        printf '%s\n' "$((index + 1))" >"$FAKE_QS_COUNTER"
        exit 0
    fi
    [[ -f "$FAKE_QS_STATE" ]] || exit 1
    cat "$FAKE_QS_STATE"
    exit 0
fi

if [[ $* == 'ipc call lock stopTest' ]]; then
    printf 'unlocked\n' >"$FAKE_QS_STATE"
    printf 'true\n'
    exit 0
fi

exit 65
FAKE
chmod 0755 "$FAKE_QS"

run_manager() {
    FAKE_QS_STATE="$FAKE_STATE" \
    FAKE_QS_LOG="$FAKE_LOG" \
    FAKE_QS_COUNTER="$FAKE_COUNTER" \
    QS_BIN="$FAKE_QS" \
    AWTARCHY_LOCK_POLL_INTERVAL=0.01 \
        bash "$MANAGER" "$@"
}

reset_fake() {
    rm -f -- "$FAKE_STATE" "$FAKE_LOG" "$FAKE_COUNTER"
}

reset_fake
[[ "$(run_manager status)" == unlocked ]] \
    || fail 'status without lock IPC did not report unlocked'

printf 'starting\n' >"$FAKE_STATE"
[[ "$(run_manager status)" == starting ]] \
    || fail 'status did not report starting from lock IPC'

printf 'secure\n' >"$FAKE_STATE"
[[ "$(run_manager status)" == secure ]] \
    || fail 'status did not report secure from lock IPC'

reset_fake
FAKE_QS_SEQUENCE='starting,secure' \
FAKE_QS_STATE="$FAKE_STATE" \
FAKE_QS_LOG="$FAKE_LOG" \
FAKE_QS_COUNTER="$FAKE_COUNTER" \
QS_BIN="$FAKE_QS" \
AWTARCHY_LOCK_POLL_INTERVAL=0.01 \
    bash "$MANAGER" wait-secure 1 >/dev/null \
    || fail 'wait-secure did not wait for exact secure state'

reset_fake
if FAKE_QS_SEQUENCE='starting' \
   FAKE_QS_STATE="$FAKE_STATE" \
   FAKE_QS_LOG="$FAKE_LOG" \
   FAKE_QS_COUNTER="$FAKE_COUNTER" \
   QS_BIN="$FAKE_QS" \
   AWTARCHY_LOCK_POLL_INTERVAL=0.01 \
       bash "$MANAGER" wait-secure 1 >/dev/null 2>&1; then
    fail 'wait-secure accepted a permanently starting lock'
fi

reset_fake
printf 'secure\n' >"$FAKE_STATE"
if run_manager stop-test >/dev/null 2>&1; then
    fail 'stop-test allowed termination of a secure compositor lock'
fi
if grep -Fq 'ipc call lock stopTest' "$FAKE_LOG"; then
    fail 'stop-test invoked the stop IPC while secure'
fi

reset_fake
printf 'starting\n' >"$FAKE_STATE"
run_manager stop-test >/dev/null \
    || fail 'stop-test refused a non-secure development lock'
grep -Fq 'ipc call lock stopTest' "$FAKE_LOG" \
    || fail 'stop-test did not use the dedicated lock IPC'

reset_fake
printf 'secure\n' >"$FAKE_STATE"
run_manager lock >/dev/null \
    || fail 'lock command failed when the dedicated lock was already secure'
if grep -Fxq -- '-c awtarchy-lock' "$FAKE_LOG"; then
    fail 'lock command launched a duplicate dedicated shell'
fi

reset_fake
run_manager lock >/dev/null \
    || fail 'lock command could not start the dedicated shell'
grep -Fxq -- '-c awtarchy-lock' "$FAKE_LOG" \
    || fail 'lock command did not start exactly the awtarchy-lock config'

printf 'PASS: native Quickshell lockscreen foundation contracts\n'
