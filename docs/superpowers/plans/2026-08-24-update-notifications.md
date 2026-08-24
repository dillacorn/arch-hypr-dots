# Awtarchy Update Notifications Implementation Plan

**Goal:** Add deduplicated stable-release and same-release maintenance notifications to Awtarchy's existing Quickshell notification history.

**Architecture:** A focused shell helper owns remote release/runtime detection and operational notification state. Quickshell schedules the helper, exposes the persistent global preference through its existing state owner, and renders the notification through its current freedesktop notification server/action UI.

**Tech stack:** Bash, Python 3 JSON parsing, curl, jq, notify-send/libnotify, QML, GitHub Actions shell tests.

**Spec:** Approved in the 2026-08-24 Awtarchy update-notification design review.

## Global constraints

- Work only on `update-notifications-testing`; do not merge to `main`.
- Stable configuration, updater/runtime, and Git-testing state remain separate.
- Drafts, prereleases, unknown/unreleased installs, and active Git-testing state do not receive normal automatic notices.
- A different `main` commit with identical launcher/runtime payload is not a user-facing update.
- The same stable or maintenance target is never announced twice.
- Suppression override requires proof that at least five stable published releases are newer, is normal urgency, and is throttled.

### Task 1: Executable detection and notification behavior

**Files:**

- Create: `tests/test-awtarchy-update-notifications.sh`
- Create: `config/hypr/scripts/quickshell_update_notifications.sh`
- Modify: `.github/workflows/validate-awtarchy.yml`

- [ ] Add a failing integration test with controlled GitHub API, notify-send, and terminal boundaries.
- [ ] Run the test before the helper exists and confirm it fails for the missing implementation.
- [ ] Implement stable release ordering, prerelease rejection, content-aware runtime comparison, Git-testing exclusion, offline silence, persistent rate limits, deduplication, suppression, and five-release catch-up behavior.
- [ ] Verify the stable action launches `awtarchy update` and the maintenance action launches `awtarchy self-update` through `default_terminal.sh`.
- [ ] Run Bash syntax, ShellCheck, and the focused test.

### Task 2: Quickshell scheduling and preference UI

**Files:**

- Modify: `config/quickshell/awtarchy/shell.qml`
- Modify: `config/quickshell/awtarchy/Notifications.qml`
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Modify: `config/hypr/scripts/quickshell_application_state.sh`

- [ ] Extend the focused test to exercise the real state writer and persistent Boolean preference.
- [ ] Add a delayed startup check and six-hour session timer without blocking Quickshell.
- [ ] Add the global Notifications-settings toggle with immediate UI feedback and explanatory catch-up text.
- [ ] Preserve current DND, popup-history, action, focus, and multi-monitor behavior.

### Task 3: Managed updater metadata and verification

**Files:**

- Modify: `local/share/awtarchy/quickshell-managed-history.sha256`
- Modify: `tests/test-quickshell-production-readiness.sh`
- Verify: command, Git-mode, process-lifecycle, production-readiness, updater-bootstrap, and updater-migration suites.

- [ ] Append current hashes for every changed Quickshell-managed file while retaining earlier known hashes.
- [ ] Add production assertions for scheduling, action support, and preference persistence.
- [ ] Run focused tests first, then the complete repository validation workflow.
- [ ] Inspect the branch diff against `main` and confirm no stable-release/tag or Git-testing boundary changed.
