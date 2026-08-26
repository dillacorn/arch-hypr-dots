# Transient PolicyKit Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the PolicyKit backend registered while idle with zero Alacritty/Hyprland auth window, spawning the existing terminal TUI only for an active authentication request.

**Architecture:** Convert `agent.py` into the persistent headless systemd process and make `tui.py` a short-lived frontend. The two processes communicate over one anonymous inherited `AF_UNIX/SOCK_SEQPACKET` socketpair per authentication request; no named socket or credential persistence is introduced.

**Tech Stack:** Python 3, PyGObject/Gio/GLib/Polkit/PolkitAgent, Alacritty, Hyprland Lua dispatch, systemd --user, Bash runtime/install tooling, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-25-polkit-transient-terminal-design.md`

## Global Constraints

- Trusted runtime remains `/usr/local/libexec/awtarchy/polkit-agent` and root-owned/non-user-writable.
- Persistent backend remains `python3 -I` and exports `org.freedesktop.PolicyKit1.AuthenticationAgent`.
- No Alacritty process or auth Hyprland client may exist while idle.
- Passwords may exist only in process memory, anonymous socketpair buffers, and `PolkitAgent.Session.response()`; never logs/files/argv/environment/named sockets.
- Preserve fixed 900x520 TUI geometry, current-theme visual sanitization, Details behavior, mouse/keyboard support, spinner, three-attempt retry behavior, and GNOME fallback during testing/migration.
- Hyprland startup remains responsible for restarting the service after graphical environment import.

---

### Task 1: Pin the transient frontend contract

**Files:**
- Create: `tests/test-polkit-agent-transient-frontend.py`
- Modify: `.github/workflows/polkit-agent-testing.yml`

**Interfaces:**
- Consumes: current branch agent/TUI/launcher/service source.
- Produces: failing assertions that require a headless idle backend, anonymous socketpair frontend transport, and no special-workspace parking.

- [ ] **Step 1: Write failing tests** that assert `agent.py` imports/uses `socket.socketpair`, owns frontend process/socket state, does not instantiate `TerminalUI`, and `tui.py` provides an IPC-driven standalone frontend entrypoint.
- [ ] **Step 2: Add the test to branch CI** immediately after the parser/auth-feedback tests.
- [ ] **Step 3: Run CI and verify RED** specifically because the current backend directly creates `TerminalUI` and keeps Alacritty persistent.

### Task 2: Split backend and terminal frontend

**Files:**
- Modify: `config/hypr/scripts/awtarchy-polkit-agent/agent.py`
- Modify: `config/hypr/scripts/awtarchy-polkit-agent/tui.py`
- Test: `tests/test-polkit-agent-transient-frontend.py`
- Test: `tests/test-polkit-agent-tui.py`
- Test: `tests/test-polkit-agent-auth-feedback.py`
- Test: `tests/test-polkit-agent-password-retry.sh`

**Interfaces:**
- Produces backend helpers for spawning/closing one transient frontend and receiving `submit`, `cancel`, `identity-cycle`, and `ready` packets.
- Produces TUI `run_frontend(ipc_fd: int) -> int` that receives backend state packets, writes rendering only to `/dev/tty`, and sends input packets back over the inherited FD.

- [ ] **Step 1: Implement bounded JSON packet helpers** using `AF_UNIX/SOCK_SEQPACKET`, a fixed maximum packet size, and fail-closed decode/validation.
- [ ] **Step 2: Move spinner ownership fully into the TUI** so submit starts feedback immediately, wrong password/status stops it, and success closes with no delay.
- [ ] **Step 3: Replace direct `TerminalUI` calls in the backend** with frontend messages while keeping PAM/session retry state in `agent.py`.
- [ ] **Step 4: Spawn Alacritty only from `BeginAuthentication`** with one explicitly inherited socketpair FD; close the backend copy of the child endpoint immediately after spawn.
- [ ] **Step 5: Add frontend child-exit handling** so unexpected exit cancels the active PolicyKit request; expected close does not stop the backend.
- [ ] **Step 6: Run focused tests until GREEN** and verify no password value appears in logs/argv/environment/static diagnostic paths.

### Task 3: Make the service genuinely headless while idle

**Files:**
- Modify: `config/hypr/scripts/awtarchy-polkit-agent/launcher.sh`
- Modify: `config/hypr/scripts/awtarchy-polkit-agent/awtarchy-polkit-agent.service`
- Test: `tests/test-polkit-agent-secure.sh`
- Test: `tests/test-polkit-agent-alacritty-appearance.sh`

**Interfaces:**
- Launcher produces a sanitized environment for the persistent backend, including newline-separated visual-only Alacritty overrides for later frontend spawn.
- Service MainPID resolves to `/usr/bin/python3 -I /usr/local/libexec/awtarchy/polkit-agent/agent.py` after launcher exec replacement.

- [ ] **Step 1: Change launcher final exec** from Alacritty to isolated Python backend.
- [ ] **Step 2: Preserve appearance sanitizer output** in a dedicated backend environment value rather than applying it at service startup.
- [ ] **Step 3: Ensure systemd owns stdout/stderr/journal diagnostics** and the TUI renders only through `/dev/tty`.
- [ ] **Step 4: Update static security/appearance contracts** for the new process tree and anonymous socket exception.
- [ ] **Step 5: Run focused launcher/service/security tests GREEN**.

### Task 4: Remove hidden-workspace parking and align desktop integration

**Files:**
- Modify: `config/hypr/hyprland.lua`
- Modify: `config/quickshell/awtarchy/Bar.qml` only as needed to remove obsolete scratchpad-specific service handling while retaining task-strip suppression during active auth.
- Test: `tests/test-polkit-agent-internal-window-ui.sh`
- Test: `tests/test-polkit-agent-hypr-dispatch.sh`

**Interfaces:**
- Hyprland rule may identify/float the exact auth class but never routes it to `special:awtarchy-polkit-agent`.
- TUI exact-window positioning targets the active workspace only while a request exists.

- [ ] **Step 1: Update failing UI contract** to reject `special:awtarchy-polkit-agent` and private parking behavior.
- [ ] **Step 2: Remove the special-workspace rule/state from Hyprland and TUI**; retain exact-class float/focus sizing behavior.
- [ ] **Step 3: Remove obsolete scratchpad-count workaround if it is no longer needed** while keeping the active auth window out of the normal task strip.
- [ ] **Step 4: Run focused Hyprland/Quickshell tests GREEN**.

### Task 5: Align testing controller and production runtime process verification

**Files:**
- Modify: `config/hypr/scripts/awtarchy-polkit-agent-live-test.sh`
- Modify: `local/share/awtarchy/awtarchy-runtime.sh`
- Modify: `tests/test-polkit-agent-production-integration.sh`
- Modify: `tests/test-polkit-agent-runtime-rebuild.sh`
- Modify: `tests/test-polkit-agent-startup-diagnostics.sh`

**Interfaces:**
- Idle verification expects the service MainPID to be the isolated Python backend and explicitly rejects an idle `awtarchy-polkit-agent` Alacritty client/process.
- During a live request, transient Alacritty/TUI may exist; after completion it must disappear while the backend service remains active.

- [ ] **Step 1: Update failing process-verification tests** from persistent Alacritty parent + Python child to direct Python backend.
- [ ] **Step 2: Change live-test and production activation verification** to validate exact Python argv/root-owned runtime and zero restarts.
- [ ] **Step 3: Add a post-auth idle check to the live test** that waits for the transient Alacritty client/process to disappear.
- [ ] **Step 4: Keep GNOME fallback and package-removal ordering unchanged** except for the new service verification shape.
- [ ] **Step 5: Run runtime rebuild/production/startup tests GREEN**.

### Task 6: Update repository architecture guidance and clean generated artifacts

**Files:**
- Modify: `AGENTS.md`
- Modify: `.gitignore` if needed
- Delete: tracked `config/hypr/scripts/awtarchy-polkit-agent/__pycache__/agent.cpython-312.pyc`
- Delete: tracked `config/hypr/scripts/awtarchy-polkit-agent/__pycache__/tui.cpython-312.pyc`
- Modify: branch CI syntax checks to avoid regenerating tracked source-tree bytecode.

**Interfaces:**
- Documentation reflects headless backend + transient terminal and narrowly permits only the anonymous inherited socketpair for credential transport.

- [ ] **Step 1: Update AGENTS.md PolicyKit invariants** to remove persistent terminal/special-workspace assumptions and document the anonymous socketpair exception.
- [ ] **Step 2: Remove tracked bytecode and prevent regeneration** using a temporary `PYTHONPYCACHEPREFIX` or compile-based syntax check.
- [ ] **Step 3: Run full branch CI and `git diff --check` GREEN**.

### Task 7: Final branch verification

**Files:**
- Modify: `.github/workflows/polkit-agent-testing.yml` only to remove any temporary write-capable implementation job and leave read-only validation.

**Interfaces:**
- Produces final testable branch head for user live validation; no merge to `main`.

- [ ] **Step 1: Restore workflow permissions to `contents: read` only.**
- [ ] **Step 2: Run the complete Polkit contract suite on the exact final head.**
- [ ] **Step 3: Verify branch head, no helper files, no tracked `__pycache__`, and no `special:awtarchy-polkit-agent` runtime parking references.**
- [ ] **Step 4: Provide the user one pull/install/live-test command and a separate real-world PolicyKit command.**
