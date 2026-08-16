# Inline Power Mode Authorization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace terminal-based Power Mode setup/repair with a secure inline Quickshell password flow backed by a fixed root-owned helper.

**Architecture:** Quickshell collects the sudo password in a masked transient field and sends it only through a child process stdin. A user-space backend invokes a fixed root-owned `/usr/local/libexec/awtarchy/power-profile-helper`; the helper exposes only `setup` and `resolve-tlp-conflict`, uses exact package/service names, and is installed atomically by the installer/updater with the same hardening pattern as the sched-ext helper.

**Tech Stack:** QML/Quickshell 0.3, Bash, sudo, pacman, systemd, GitHub Actions.

## Global Constraints

- Work from the current `main` state and do not modify the published v3.0.0 release.
- No privileged execution of user-writable files under `$HOME`.
- No broad `NOPASSWD` rule for pacman, systemctl, shell, or the Power Mode helper.
- The password may travel only over process stdin and must not be placed in argv, environment, files, logs, or persistent state.
- The helper accepts only fixed actions and rejects extra arguments.
- Normal Power Saver / Balanced / Performance switching remains through the Power Profiles D-Bus interface without sudo.

---

### Task 1: Lock the privileged-helper contract with regression tests

**Files:**
- Create: `tests/test-power-profile-inline-auth.sh`
- Create: `tests/test-power-profile-helper-update.sh`
- Modify: `.github/workflows/validate-awtarchy.yml`

**Interfaces:**
- Consumes: existing `PowerModeCard.qml`, installer helper deployment, updater helper repair pattern.
- Produces: regression requirements for masked stdin auth, no terminal launcher, fixed helper actions, and hardened helper deployment.

- [ ] **Step 1: Write failing tests** requiring `TextInput.Password`, `stdinEnabled: true`, direct sudo stdin transport, absence of `awtarchy-power-mode-setup`, helper `setup|resolve-tlp-conflict` allowlist, extra-argument rejection, exact package checks, and installer/updater deployment.
- [ ] **Step 2: Run both tests** and verify they fail because the inline helper flow does not exist yet.
- [ ] **Step 3: Add both tests to Bash syntax, ShellCheck, and integration sections of `.github/workflows/validate-awtarchy.yml` only after the feature passes locally/structurally.

### Task 2: Add the restricted root-owned Power Mode helper

**Files:**
- Create: `local/libexec/awtarchy/power-profile-helper`

**Interfaces:**
- Consumes: exactly one action argument: `setup` or `resolve-tlp-conflict`.
- Produces: configured TLP/tlp-pd or power-profiles-daemon backend; nonzero exit with concise stderr on failure.

- [ ] **Step 1: Implement fixed `/usr/bin/bash` helper** with `set -Eeuo pipefail`, exact `pacman -Qq | grep -Fx` checks, laptop guard, absolute privileged executable paths, and no shell/eval execution.
- [ ] **Step 2: Implement `setup`** so literal `tlp` installs/enables only `tlp-pd`, while systems without TLP install/enable only `power-profiles-daemon`; refuse a literal TLP+PPD conflict and require the explicit conflict action.
- [ ] **Step 3: Implement `resolve-tlp-conflict`** so it operates only when literal `tlp` and literal `power-profiles-daemon` are both present, removes only `power-profiles-daemon`, installs `tlp-pd`, and enables only `tlp.service` and `tlp-pd.service`.
- [ ] **Step 4: Run helper contract tests and Bash syntax/ShellCheck** until green.

### Task 3: Install/repair the trusted helper safely

**Files:**
- Modify: `awtarchy-install.sh`
- Modify: `local/share/awtarchy/awtarchy-runtime.sh`

**Interfaces:**
- Consumes: repository helper source `local/libexec/awtarchy/power-profile-helper`.
- Produces: root-owned, mode `0755`, non-symlink `/usr/local/libexec/awtarchy/power-profile-helper` with bytes matching the source.

- [ ] **Step 1: Extend installer validation/staging** to validate fixed interpreter and Bash syntax, stage atomically under the root-owned libexec directory, and never follow a symlinked destination directory.
- [ ] **Step 2: Add updater current/repair functions** mirroring the scxctl helper checks: owner uid 0, non-group/world-writable mode, fixed interpreter, syntax, source/staged SHA-256 equality, atomic activation, and post-install comparison.
- [ ] **Step 3: Call repair before managed config application** so Quickshell can never be updated to an inline privileged path without the trusted helper present.
- [ ] **Step 4: Run updater/helper regression tests** until green.

### Task 4: Replace terminal setup with inline Quickshell auth

**Files:**
- Modify: `config/quickshell/awtarchy/PowerModeCard.qml`

**Interfaces:**
- Consumes: transient password text and backend state (`setup` vs `conflict`).
- Produces: inline authorization/result UI and a child `sudo -S -p '' /usr/local/libexec/awtarchy/power-profile-helper <fixed-action>` process.

- [ ] **Step 1: Remove terminal-launcher/setup-script execution** from `PowerModeCard.qml`.
- [ ] **Step 2: Add masked inline password state/input** with submit/cancel/error/busy state; clear visible and pending password immediately after process start.
- [ ] **Step 3: Add stdin-enabled process runner** with fixed argv, write the password through stdin only, disable duplicate submission while running, surface the first useful error inline, and re-probe backend only after exit 0.
- [ ] **Step 4: Keep profile buttons unchanged** so normal switching remains through `PowerProfiles.profile`.
- [ ] **Step 5: Run inline-auth tests** until green.

### Task 5: Final validation and security review

**Files:**
- Modify if required: `local/share/awtarchy/quickshell-managed-history.sha256`
- Modify if required: `.github/workflows/validate-awtarchy.yml`

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: a tested main-eligible change set.

- [ ] **Step 1: Append managed-history hashes** for changed managed Quickshell/config files required by updater migration tests.
- [ ] **Step 2: Run full repository validation** including Bash syntax, ShellCheck, updater integration, security-boundary tests, and `git diff --check` equivalent coverage through CI.
- [ ] **Step 3: Review the exact diff using the Codex Security diff-scan methodology** with special attention to sudo stdin handling, symlink/ownership checks, arbitrary-command/package/service injection, and password leakage.
- [ ] **Step 4: Merge only after validation is green**, then provide `awtarchy git update --branch main` for hardware testing.