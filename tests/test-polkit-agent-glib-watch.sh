#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
agent="$repo_root/config/hypr/scripts/awtarchy-polkit-agent/agent.py"

[[ -f "$agent" ]] || {
    printf 'missing agent: %s\n' "$agent" >&2
    exit 1
}

# The headless backend watches only the anonymous frontend socket. It must not
# own or poll /dev/tty; the transient frontend handles terminal input itself.
grep -Fq 'GLib.IOChannel.unix_new(parent_sock.fileno())' "$agent"
grep -Fq '.add_watch(conditions, self._on_frontend_io)' "$agent"

if grep -Fq 'self.ui.tty_fd' "$agent" || grep -Fq 'def _on_tty_ready' "$agent"; then
    printf '%s\n' 'headless agent still contains direct TTY watch state' >&2
    exit 1
fi
if grep -Fq 'GLib.unix_fd_add' "$agent"; then
    printf '%s\n' 'agent must not depend on GLib.unix_fd_add' >&2
    exit 1
fi

printf '%s\n' 'Polkit GLib frontend-socket watch contract passed.'
