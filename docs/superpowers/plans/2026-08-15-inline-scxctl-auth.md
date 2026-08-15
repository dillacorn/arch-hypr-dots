# Inline sched-ext Authorization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the temporary terminal-based sched-ext authorization with a masked password prompt inside Quick Settings while preserving the restricted root-owned `scxctl-helper` boundary and repairing stale `/usr/bin/scxctl` sudoers rules.

**Architecture:** Keep the existing session-wide `polkit-gnome` agent untouched. Quick Settings sends the entered password only through a Quickshell `Process` stdin channel to the Awtarchy backend; the backend feeds that stdin directly to `sudo -S`, installs the exact restricted helper sudoers rule, invalidates cached credentials, and cold-verifies `sudo -n /usr/local/libexec/awtarchy/scxctl-helper list`. No password is passed in argv, files, or logs.

**Tech Stack:** QML/Quickshell 0.3, Bash, sudo/visudo, GitHub Actions.

## Global Constraints

- Work only on `scxctl-auth-testing` until Dillon tests it.
- Do not modify the existing release.
- Do not replace or disable `polkit-gnome`.
- Never grant `NOPASSWD` to `/usr/bin/scxctl`; only the fixed root-owned Awtarchy helper is permitted.
- Do not store the entered password in a file, command argument, log, or persistent state.

---

### Task 1: Lock the inline-auth behavior with regression tests

**Files:**
- Modify: `tests/test-scxctl-auth-ui.sh`
- Modify: `tests/test-scxctl-auth-stale-rule.sh`

**Interfaces:**
- Consumes: current Quick Settings scheduler section and `ensure_scxctl_nopasswd_rule`.
- Produces: assertions requiring an inline masked input, stdin transport, forced stale-rule repair, and removal of the terminal auth launcher.

- [ ] Replace terminal-auth assertions with inline password/stdi​n assertions.
- [ ] Require the explicit authorization path to invalidate cached sudo before authenticating.
- [ ] Run both tests and verify they fail against the existing branch implementation.

### Task 2: Add forced stdin authorization to the Bash backend

**Files:**
- Modify: `config/hypr/scripts/hypr_quicksettings_core.sh`
- Modify: `config/hypr/scripts/hypr_quicksettings.sh`

**Interfaces:**
- Consumes: password bytes on stdin for the explicit `--authorize-scheduler-stdin` entrypoint.
- Produces: the exact rule `<user> ALL=(root) NOPASSWD: /usr/local/libexec/awtarchy/scxctl-helper`, then a cold helper verification.

- [ ] Add a forced authorization mode that does not trust a warm sudo timestamp.
- [ ] Authenticate with `sudo -S -p '' -v` from inherited stdin.
- [ ] Reuse the existing root-owned staging + `visudo` validation path.
- [ ] Run Bash syntax and the stale-rule regression.

### Task 3: Render and drive the inline Quick Settings prompt

**Files:**
- Modify: `config/quickshell/awtarchy/QuickSettings.qml`

**Interfaces:**
- Consumes: `schedulerStatus.authorized` and user text from a masked `TextInput`.
- Produces: `Process.write(password + "\n")` to `backend --authorize-scheduler-stdin`, immediate field clearing, inline errors, and status refresh after success.

- [ ] Replace `authorizeScheduler()` terminal launch with open/submit/cancel functions.
- [ ] Add a tracked stdin-enabled process for authorization.
- [ ] Add the masked inline password row beneath sched-ext.
- [ ] Disable duplicate submits while authorization is running.
- [ ] Run the UI regression and `git diff --check`.

### Task 4: Validate the branch and prepare live test instructions

**Files:**
- Modify if needed: `.github/workflows/validate-awtarchy.yml`

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: a branch SHA that can be installed with `awtarchy git update` and tested after `sudo -k`.

- [ ] Run focused tests, Bash syntax, ShellCheck where applicable, and the existing security-boundary tests.
- [ ] Verify the final branch diff against `main` contains only intended sched-ext code/tests plus this plan.
- [ ] Give the exact branch SHA and live test command; do not merge to `main` until Dillon confirms the UI works.
