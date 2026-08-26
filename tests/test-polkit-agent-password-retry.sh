#!/usr/bin/bash
set -euo pipefail

AGENT="config/hypr/scripts/awtarchy-polkit-agent/agent.py"

[[ -f $AGENT ]]

grep -Fq 'MAX_AUTH_ATTEMPTS = 3' "$AGENT"
grep -Fq 'self.auth_attempts = 0' "$AGENT"
grep -Fq 'self.last_session_error = ""' "$AGENT"
grep -Fq 'self.auth_attempts += 1' "$AGENT"
grep -Fq 'def _friendly_auth_error(' "$AGENT"
grep -Fq 'Incorrect password. Try again.' "$AGENT"
grep -Fq 'if gained_authorization:' "$AGENT"
grep -Fq 'if self.cancel_requested:' "$AGENT"
grep -Fq 'if self.auth_attempts < MAX_AUTH_ATTEMPTS:' "$AGENT"
grep -Fq 'self.active_session = None' "$AGENT"
grep -Fq '"type": "error"' "$AGENT"
grep -Fq 'GLib.timeout_add(' "$AGENT"
grep -Fq 'def _finish_denied_after_retry_limit(' "$AGENT"

# A failed PolkitAgent.Session must not be treated the same as success.
if grep -A16 -F 'def _on_session_completed(' "$AGENT" | grep -Fq 'del gained_authorization'; then
    echo 'completed(false) is still being discarded instead of retried' >&2
    exit 1
fi

# Retry feedback must go to the transient frontend, never an in-process TerminalUI.
if grep -Fq 'self.ui.set_error(' "$AGENT"; then
    echo 'backend still owns terminal retry UI directly' >&2
    exit 1
fi

echo 'Polkit password retry contract passed.'
