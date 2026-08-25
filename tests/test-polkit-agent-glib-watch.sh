#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
agent="$repo_root/config/hypr/scripts/awtarchy-polkit-agent/agent.py"

[[ -f "$agent" ]] || {
    printf 'missing agent: %s\n' "$agent" >&2
    exit 1
}

# PyGObject does not consistently expose g_unix_fd_add() as
# GLib.unix_fd_add. Use the long-standing IOChannel API instead.
grep -Fq 'GLib.IOChannel.unix_new(self.ui.tty_fd)' "$agent"
grep -Fq '.add_watch(conditions, self._on_tty_ready)' "$agent"

if grep -Fq 'GLib.unix_fd_add' "$agent"; then
    printf '%s\n' 'agent must not depend on GLib.unix_fd_add' >&2
    exit 1
fi

printf '%s\n' 'Polkit GLib TTY watch contract passed.'
