#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SAFETY="$ROOT/config/hypr/scripts/protected_idle_safety.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

bin="$TMP/bin"
mkdir -p -- "$bin"
action_log="$TMP/actions.log"
: >"$action_log"

cat >"$bin/idle-inhibitor" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
    is-active|is-always-awake) exit 1 ;;
    *) exit 2 ;;
esac
EOF
chmod 0755 "$bin/idle-inhibitor"

# Deliberately leave this guard non-executable. protected_idle_safety.sh must
# invoke the authoritative Bash guard without depending on repository mode bits.
cat >"$bin/hypridle-guard" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
    game-active) exit 0 ;;
    teams-inhibit-active|obs-active|video-active) exit 1 ;;
    *) exit 2 ;;
esac
EOF
chmod 0644 "$bin/hypridle-guard"

cat >"$bin/loginctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'loginctl %s\n' "$*" >>"${ACTION_LOG:?}"
EOF
chmod 0755 "$bin/loginctl"

cat >"$bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'hyprctl %s\n' "$*" >>"${ACTION_LOG:?}"
EOF
chmod 0755 "$bin/hyprctl"

INHIBITOR_SH="$bin/idle-inhibitor" \
HYPRIDLE_ACTION_SCRIPT="$bin/hypridle-guard" \
LOGINCTL_BIN="$bin/loginctl" \
HYPRCTL_BIN="$bin/hyprctl" \
ACTION_LOG="$action_log" \
HYPRIDLE_ACTION_LOG="$TMP/protected-idle.log" \
    bash "$SAFETY"

grep -Fxq 'loginctl lock-session' "$action_log" \
    || fail 'automatically detected game did not lock after four protected idle hours'
grep -Fxq 'hyprctl dispatch hl.dsp.dpms({ action = "disable" })' "$action_log" \
    || fail 'automatically detected game did not power displays off after the safety lock'

printf '%s\n' 'PASS: automatic game protection reaches the four-hour lock + DPMS safety path.'
