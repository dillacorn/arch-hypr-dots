#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNTIME="${ROOT_DIR}/local/share/awtarchy/awtarchy-runtime.sh"

[[ -f $RUNTIME ]]
bash -n "$RUNTIME"

grep -Fq 'AWTARCHY_POLKIT_RUNTIME_PARENT="/usr/local/libexec/awtarchy"' "$RUNTIME"
grep -Fq 'install_awtarchy_polkit_agent_runtime()' "$RUNTIME"
grep -Fq '.polkit-agent.stage.XXXXXX' "$RUNTIME"
grep -Fq 'awtarchy_polkit_verify_runtime_tree "$AWTARCHY_POLKIT_RUNTIME_DIR"' "$RUNTIME"
grep -Fq "IFS=' ' read -r uid mode type" "$RUNTIME"
grep -Fq '"${stage}/agent.py"' "$RUNTIME"
grep -Fq '"${stage}/tui.py"' "$RUNTIME"
grep -Fq '"${stage}/alacritty.toml"' "$RUNTIME"
grep -Fq '"${stage}/launcher"' "$RUNTIME"
if grep -Fq 'shell.qml' "$RUNTIME" || grep -Fq 'window-guard.sh' "$RUNTIME"; then
    printf '%s\n' 'FAIL: production PolicyKit staging references obsolete Quickshell runtime files' >&2
    exit 1
fi
grep -Fq 'awtarchy_polkit_restore_install_transaction()' "$RUNTIME"
grep -Fq 'awtarchy_polkit_root /usr/bin/mv -Tf -- "$AWTARCHY_POLKIT_RUNTIME_DIR" "$previous_runtime"' "$RUNTIME"
grep -Fq 'awtarchy_polkit_root /usr/bin/mv -Tf -- "$stage" "$AWTARCHY_POLKIT_RUNTIME_DIR"' "$RUNTIME"
grep -Fq 'awtarchy_polkit_root /usr/bin/mv -Tf -- "$previous_runtime" "$AWTARCHY_POLKIT_RUNTIME_DIR"' "$RUNTIME"
grep -Fq 'awtarchy_polkit_restore_install_transaction "$previous_runtime" "$failed_runtime" "$previous_service"' "$RUNTIME"

printf '%s\n' 'terminal Polkit production runtime rebuild tests passed'
