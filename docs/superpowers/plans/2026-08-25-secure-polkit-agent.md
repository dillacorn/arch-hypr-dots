# Secure Polkit Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a real, securely installed Awtarchy PolicyKit authentication agent using Quickshell's native Polkit backend while preserving the approved terminal-like interface.

**Architecture:** A root-owned dedicated Quickshell configuration under `/usr/local/libexec/awtarchy/polkit-agent` registers `PolkitAgent` as the desktop user's authentication agent. A root-owned launcher sanitizes the process environment and a system-installed user service supervises it; a user-facing testing controller performs secure installation, temporarily swaps out GNOME's agent, and restores GNOME on failure/rollback.

**Tech Stack:** Bash, Quickshell/QML, `Quickshell.Services.Polkit`, systemd user services, Hyprland `hyprctl`, PolicyKit/pkaction.

**Spec:** `docs/superpowers/specs/2026-08-25-secure-polkit-agent-design.md`

## Global Constraints

- Keep work on `polkit-agent-concept-testing`; do not modify `main`.
- Keep `polkit-gnome` installed and its permanent Awtarchy autostart unchanged during this live-test phase.
- Authentication responses must only travel through `AuthFlow.submit()`/libpolkit-agent; never custom IPC, files, shell stdin, or logging.
- Real executable QML/launcher/service files must be root-owned and outside `$HOME` before real-password testing.
- Do not claim caller application identity because Quickshell 0.3.1 does not expose Polkit's details dictionary.
- Fixed review geometry remains 900x520, floating and centered.
- `Details:` starts collapsed.

---

### Task 1: Secure Agent UI

**Files:**
- Create: `config/hypr/scripts/awtarchy-polkit-agent/shell.qml`
- Test: `tests/test-polkit-agent-secure.sh`

**Interfaces:**
- Consumes: Quickshell `PolkitAgent.flow`/`AuthFlow` and `/usr/bin/pkaction` metadata.
- Produces: a self-contained QML config that registers Polkit and submits/cancels authentication directly.

- [ ] **Step 1: Write static failing tests**

Assert that the future QML imports `Quickshell.Services.Polkit`, owns a `PolkitAgent`, uses `flow.submit`, uses `flow.cancelAuthenticationRequest`, masks according to `responseVisible`, starts details collapsed, renders request-controlled text as `Text.PlainText`, and contains no custom password IPC/shell authentication path.

- [ ] **Step 2: Verify the focused test fails**

Run `bash tests/test-polkit-agent-secure.sh`; expected failure because `shell.qml` does not exist.

- [ ] **Step 3: Implement the QML**

Create a fixed 900x520 terminal-like authentication window with magenta headers, dynamic Polkit message/prompt/action/identity, red Cancel and green Authenticate controls, collapsed Details, multi-turn prompt handling, immediate input clearing, and action metadata loaded with `Process.command` arrays using `/usr/bin/pkaction`.

- [ ] **Step 4: Run static tests**

Run `bash tests/test-polkit-agent-secure.sh`; expected PASS for QML security/behavior assertions.

- [ ] **Step 5: Commit**

Commit the QML and focused tests as one independently reviewable change.

### Task 2: Root-Owned Runtime and Window Guard

**Files:**
- Create: `config/hypr/scripts/awtarchy-polkit-agent/launcher.sh`
- Create: `config/hypr/scripts/awtarchy-polkit-agent/window-guard.sh`
- Extend: `tests/test-polkit-agent-secure.sh`

**Interfaces:**
- Consumes: root-owned installed QML directory, user session variables, Hyprland client state.
- Produces: a sanitized dedicated Quickshell process plus exact-window geometry enforcement.

- [ ] **Step 1: Add failing launcher/guard tests**

Assert fixed absolute executables, root-owner/mode checks, rejection of symlink/writable runtime files, cleared loader/QML import variables, no `eval`, no credential handling in the guard, exact `awtarchy-polkit-agent` matching, and 900x520 floating/center dispatch.

- [ ] **Step 2: Verify tests fail**

Run the focused test and confirm missing launcher/guard assertions fail.

- [ ] **Step 3: Implement launcher and guard**

The launcher validates `/usr/local/libexec/awtarchy/polkit-agent`, requires a non-root desktop user, starts the geometry guard, then replaces itself with `/usr/bin/quickshell -n -p /usr/local/libexec/awtarchy/polkit-agent` under a minimal environment. The guard only queries/manipulates the exact authentication window.

- [ ] **Step 4: Run tests**

Run `bash tests/test-polkit-agent-secure.sh`; expected PASS.

- [ ] **Step 5: Commit**

Commit the root-owned runtime boundary implementation.

### Task 3: Root-Owned User Service and Live-Test Controller

**Files:**
- Create: `config/hypr/scripts/awtarchy-polkit-agent/awtarchy-polkit-agent.service`
- Create: `config/hypr/scripts/awtarchy-polkit-agent-live-test.sh`
- Extend: `tests/test-polkit-agent-secure.sh`

**Interfaces:**
- Consumes: managed source files under `~/.config/hypr/scripts/awtarchy-polkit-agent/` after `awtarchy git update`.
- Produces: root-owned installed runtime files, `/usr/local/lib/systemd/user/awtarchy-polkit-agent.service`, safe GNOME/Awtarchy agent switching, status/test/restore commands.

- [ ] **Step 1: Add failing controller/service tests**

Assert root-owned destination paths, source/destination symlink rejection, atomic/fixed-mode installation, `systemctl --user daemon-reload`, exact GNOME process matching, rollback-on-start-failure, harmless real test action, and no permanent GNOME package/autostart modification.

- [ ] **Step 2: Verify tests fail**

Run `bash tests/test-polkit-agent-secure.sh`; expected failure while service/controller are absent.

- [ ] **Step 3: Implement service and controller**

Provide `install`, `start`, `test`, `status`, `stop`, and `restore-gnome` actions. `start` stops only the exact GNOME agent and starts the Awtarchy user service; failure restores GNOME. `test` revokes temporary authorizations then invokes `pkexec /usr/bin/true` so the real dialog is guaranteed to be exercised.

- [ ] **Step 4: Run static/simulated tests**

Run `bash -n` on all new shell scripts and `bash tests/test-polkit-agent-secure.sh`.

- [ ] **Step 5: Commit**

Commit the live-test deployment/switching layer.

### Task 4: Branch-Level Verification

**Files:**
- Verify all branch changes; no new implementation file required unless validation exposes a defect.

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: evidence that the branch is ready for live desktop testing without claiming runtime authentication success.

- [ ] **Step 1: Re-read exact changed files from branch head**

Confirm paths/content/modes and ensure only intended testing-branch files changed.

- [ ] **Step 2: Run available static checks**

Run/inspect equivalent evidence for `bash -n`, focused tests, `git diff --check`, and branch comparison. QML runtime behavior remains explicitly unverified until the user's machine runs Quickshell.

- [ ] **Step 3: Security review**

Check that no real credential passes through Bash, files, custom sockets, logs, or user-writable executable code after secure install; verify GNOME rollback remains available.

- [ ] **Step 4: Provide live test commands**

Give the minimal commands to refresh the branch, install root-owned files, start the real agent, trigger `/usr/bin/true`, inspect status if needed, and restore GNOME immediately if anything is wrong.
