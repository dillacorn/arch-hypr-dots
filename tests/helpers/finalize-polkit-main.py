#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_between(path: Path, start: str, end: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    start_i = text.index(start)
    end_i = text.index(end, start_i)
    path.write_text(text[:start_i] + replacement + text[end_i:], encoding="utf-8")


policy_section = '''### PolicyKit authentication

Awtarchy owns its desktop PolicyKit authentication agent instead of delegating that role to `polkit-gnome`.

Repository sources:

- `config/hypr/scripts/awtarchy-polkit-agent/agent.py`: persistent headless system-bus registration and the PolicyKit/PAM authentication conversation.
- `config/hypr/scripts/awtarchy-polkit-agent/tui.py`: short-lived real terminal authentication UI, keyboard/mouse handling, and exact-window Hyprland lifecycle.
- `config/hypr/scripts/awtarchy-polkit-agent/launcher.sh`: validates the trusted runtime, sanitizes current-user Alacritty appearance values, and starts the isolated headless Python backend.
- `config/hypr/scripts/awtarchy-polkit-agent/alacritty.toml`: root-owned fallback terminal configuration for transient authentication windows.
- `config/hypr/scripts/awtarchy-polkit-agent/awtarchy-polkit-agent.service`: supervised headless user service.

Installed trusted runtime:

- `/usr/local/libexec/awtarchy/polkit-agent/`
- `/usr/local/lib/systemd/user/awtarchy-polkit-agent.service`

Important invariants:

- `polkit` and `python-gobject` are explicit Arch package dependencies. `polkit-gnome` is retired and may exist only as a controlled migration fallback.
- The persistent service is a headless `python3 -I .../agent.py` backend. Alacritty must not exist merely because the PolicyKit agent is idle.
- The real authentication frontend is a dedicated transient Alacritty terminal. Quickshell/QML does not participate in authentication and must not be reintroduced as an authentication backend/frontend without an explicit architecture change.
- The Python backend exports `org.freedesktop.PolicyKit1.AuthenticationAgent` on the system bus and uses `PolkitAgent.Session` for the PAM conversation.
- Each active request creates one anonymous inherited `AF_UNIX` `SOCK_SEQPACKET` socketpair between the root-owned backend and root-owned TUI. It has no filesystem path, listener, or reusable endpoint. The submitted response travels TUI -> anonymous socketpair -> `PolkitAgent.Session.response()` and nowhere else.
- Never log, persist, shell-expand, write to temporary files, pass in argv/environment, send through `sudo -S`, expose through a named/filesystem socket, or otherwise duplicate authentication responses.
- Hyprland starts/restarts `awtarchy-polkit-agent.service` after the Wayland/Hyprland session environment exists. Do not globally enable the unit at `default.target` where it can race `WAYLAND_DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE`, or `XDG_SESSION_ID` setup.
- Authentication Python, launcher code, TUI code, and fallback Alacritty configuration must run from the root-owned, non-user-writable runtime under `/usr/local`. Do not execute the live agent from `~/.config`, and do not add user-controlled Python/library/plugin search paths to the agent process.
- User Alacritty configuration may influence only explicitly sanitized visual appearance values. Shell commands, bindings, environment entries, plugins, and other executable configuration must never enter the authentication runtime.
- During authentication, target/focus/resize only the exact `awtarchy-polkit-agent` window. On success, cancellation, final denial, frontend crash, or backend cancellation, the transient TUI/Alacritty process must terminate completely. Do not park it on a special workspace or expose it as a scratchpad/task window.
- Preserve the approved terminal behavior: fixed 900x520 geometry, Details collapsed initially, targeted password-field/status redraws, SGR mouse support, keyboard navigation, three password attempts, real PAM status/error messages, and an `Authenticating` spinner with no artificial success delay.
- Backend diagnostics belong in the user journal. Python warnings/tracebacks must not appear in the authentication terminal's normal buffer.
- Migration must stop only the exact retired GNOME agent binary, verify the supervised headless Python backend, and restore GNOME when activation fails.
- Automatic `polkit-gnome` package removal is allowed only when Awtarchy recorded ownership of that package, live activation succeeded, and every rollback-capable update validation/cleanup step has already completed.
- Changes to this architecture require the focused PolicyKit contracts under `tests/` and permanent CI validation to remain aligned with the implementation.

'''

replace_between(ROOT / "AGENTS.md", "### PolicyKit authentication\n", "### Runtime and integration helpers\n", policy_section)

secure = ROOT / "tests/test-polkit-agent-secure.sh"
secure_text = secure.read_text(encoding="utf-8")
secure_text = secure_text.replace('LIVE_TEST="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent-live-test.sh"\n', "")
secure_text = secure_text.replace('# The live-test controller is intentionally branch-only until the migration is validated.\nrequire_file "$LIVE_TEST"\n\n', "")
secure.write_text(secure_text, encoding="utf-8")

(ROOT / "tests/test-polkit-agent-headless-idle.sh").write_text('''#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNTIME="${ROOT_DIR}/local/share/awtarchy/awtarchy-runtime.sh"
AGENT="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/agent.py"
BAR="${ROOT_DIR}/config/quickshell/awtarchy/Bar.qml"
HYPR="${ROOT_DIR}/config/hypr/hyprland.lua"

fail() { printf 'FAIL: %s\\n' "$*" >&2; return 1; }
require_contains() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }
reject_contains() { ! grep -Fq -- "$2" "$1" || fail "$1 still contains: $2"; }

require_contains "$RUNTIME" 'expected_python="$(/usr/bin/readlink -f -- /usr/bin/python3 2>/dev/null)"'
require_contains "$RUNTIME" '[[ "$resolved" == "$expected_python" ]] || return 1'
reject_contains "$RUNTIME" '[[ "$resolved" == "$expected_alacritty" ]] || return 1'

require_contains "$AGENT" 'socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)'
require_contains "$AGENT" 'self.frontend_process: Optional[subprocess.Popen] = None'
require_contains "$AGENT" 'def _spawn_frontend(self, request: dict) -> None:'
require_contains "$AGENT" 'def _close_frontend(self) -> None:'

reject_contains "$HYPR" 'special:awtarchy-polkit-agent'
reject_contains "$BAR" 'internalServiceWindow'
require_contains "$BAR" 'toplevel.workspace && toplevel.workspace.id < 0).length'

printf '%s\\n' 'headless Polkit idle contract passed'
''', encoding="utf-8")

(ROOT / "tests/test-polkit-agent-startup-diagnostics.sh").write_text('''#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
AGENT="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/agent.py"
LAUNCHER="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/launcher.sh"
SERVICE="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/awtarchy-polkit-agent.service"

fail() { printf 'FAIL: %s\\n' "$*" >&2; return 1; }
require_contains() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }
reject_contains() { ! grep -Fq -- "$2" "$1" || fail "$1 still contains: $2"; }

require_contains "$AGENT" 'SYSTEMD_CAT = "/usr/bin/systemd-cat"'
require_contains "$AGENT" 'def journal_message(priority: str, message: str) -> None:'
require_contains "$AGENT" 'startup: PolicyKit authentication agent registered; terminal idle'
require_contains "$AGENT" 'authentication terminal exited before request completion'
require_contains "$AGENT" 'fatal startup:'
require_contains "$AGENT" 'except Exception as exc:'
reject_contains "$AGENT" 'startup: authentication terminal hidden and ready'
require_contains "$LAUNCHER" 'PolicyKit Python bindings are unavailable; install polkit and python-gobject.'
require_contains "$LAUNCHER" '"$PYTHON" -I "$AGENT"'
require_contains "$SERVICE" 'StandardOutput=journal'
require_contains "$SERVICE" 'StandardError=journal'

printf '%s\\n' 'headless Polkit startup diagnostics contract passed'
''', encoding="utf-8")

(ROOT / "tests/test-polkit-agent-runtime-rebuild.sh").write_text('''#!/usr/bin/env bash
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
    printf '%s\\n' 'FAIL: production PolicyKit staging references obsolete Quickshell runtime files' >&2
    exit 1
fi
grep -Fq 'awtarchy_polkit_restore_install_transaction()' "$RUNTIME"
grep -Fq 'awtarchy_polkit_root /usr/bin/mv -Tf -- "$AWTARCHY_POLKIT_RUNTIME_DIR" "$previous_runtime"' "$RUNTIME"
grep -Fq 'awtarchy_polkit_root /usr/bin/mv -Tf -- "$stage" "$AWTARCHY_POLKIT_RUNTIME_DIR"' "$RUNTIME"
grep -Fq 'awtarchy_polkit_root /usr/bin/mv -Tf -- "$previous_runtime" "$AWTARCHY_POLKIT_RUNTIME_DIR"' "$RUNTIME"
grep -Fq 'awtarchy_polkit_restore_install_transaction "$previous_runtime" "$failed_runtime" "$previous_service"' "$RUNTIME"

printf '%s\\n' 'terminal Polkit production runtime rebuild tests passed'
''', encoding="utf-8")

for relative in (
    "config/hypr/scripts/awtarchy-polkit-agent-live-test.sh",
    "docs/superpowers/plans/2026-08-25-polkit-transient-terminal.md",
    "docs/superpowers/specs/2026-08-25-polkit-transient-terminal-design.md",
):
    path = ROOT / relative
    if path.exists() or path.is_symlink():
        path.unlink()
