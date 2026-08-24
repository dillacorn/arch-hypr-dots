# Production Failure Reporting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship user-approved, privacy-conscious Awtarchy failure reporting for known Quickshell and resume-recovery failures through the already-proven Cloudflare Worker, D1 deduplication, and Awtarchy Report Bot.

**Architecture:** Awtarchy-owned failure paths call one local reporting helper that creates a strictly sanitized pending JSON report under user state. Interactive callers can review/send/decline immediately; noninteractive failures remain pending without spawning a terminal. The Worker validates a fixed public schema, maps only recognized failure triples to server-owned descriptions, fingerprints the bug signature, deduplicates in D1, and creates one GitHub issue per signature.

**Tech Stack:** Bash, curl, jq, Cloudflare Workers TypeScript, D1, Web Crypto SHA-256, GitHub App Issues API, Node test runner via tsx.

**Spec:** `docs/superpowers/specs/2026-08-23-anonymous-crash-reporting-design.md`

## Global Constraints

- No failure report is transmitted without explicit user approval.
- No username, hostname, home path, IP report field, MAC, SSID, VPN detail, environment secret, command history, clipboard data, arbitrary file content, raw log, or persistent install/machine identifier may be included.
- Reporting failure must never change the original Awtarchy operation exit status or recovery behavior.
- Public clients contain no Cloudflare or GitHub secret.
- The Worker accepts only a strict allowlisted schema of at most 32 KiB and rejects unknown fields or unknown failure classes.
- Fingerprints are server-generated from schema version, report type, component, failure stage, and error code only.
- GitHub issue title/body/repository/fingerprint are server-owned.
- Raw troubleshooting logs remain local.
- Initial production hooks cover known Quickshell start/restart and exhausted resume-recovery failures only; do not report arbitrary system or application failures.

---

### Task 1: Production Worker report contract

**Files:**
- Create: `services/report-service/src/failure-report.ts`
- Modify: `services/report-service/src/github.ts`
- Modify: `services/report-service/src/index.ts`
- Create: `services/report-service/tests/failure-report.test.ts`
- Modify: `services/report-service/tests/github.test.ts`
- Modify: `services/report-service/tests/worker.test.ts`

**Interfaces:**
- Consumes: existing `ReportServiceEnv`, D1 `crash_signatures`, GitHub App client.
- Produces: `POST /v1/report`, `validateFailurePayload()`, `runFailureReport()`, and server-generated production issue creation.

- [ ] **Step 1: Write failing validation/route tests** covering wrong content type, malformed JSON, oversized body, unknown fields, invalid versions, unknown failure triples, and caller attempts to provide fingerprint/title/body.
- [ ] **Step 2: Run `npm test` and verify the new tests fail because `/v1/report` and validation do not exist.**
- [ ] **Step 3: Implement the strict schema and canonical registry.** Recognized v1 triples are:

```text
quickshell | start | quickshell_not_ready
quickshell | restart_after_update | quickshell_not_ready
resume_recovery | start | quickshell_start_failed
resume_recovery | restart | quickshell_restart_failed
resume_recovery | final_validation | expected_bars_missing
```

- [ ] **Step 4: Implement deterministic SHA-256 fingerprinting and D1 insert/increment/issue-claim behavior using the same recovery rules already proven by `/v1/test`.**
- [ ] **Step 5: Add `createFailureIssue()` with fixed server-generated Markdown and only validated structured diagnostic fields.**
- [ ] **Step 6: Run `npm test`; require zero failures.**
- [ ] **Step 7: Commit backend production reporting.**

### Task 2: Local sanitized pending-report helper

**Files:**
- Create: `config/hypr/scripts/awtarchy_report_failure.sh`
- Create: `tests/test-anonymous-reporting.sh`
- Modify: `.github/workflows/validate-awtarchy.yml`

**Interfaces:**
- Consumes: `component`, `failure_stage`, `error_code`; local Awtarchy state and safe version commands.
- Produces: sanitized pending JSON under `${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy/reports/`; interactive review/send/decline; submission to `https://awtarchy-reports.dillacorn.workers.dev/v1/report`.

- [ ] **Step 1: Write a failing shell test using isolated HOME/XDG state and stubbed curl/version commands.** Assert restrictive pending-file permissions, exact allowlisted JSON keys, no username/hostname/home path, no network call before approval, successful send removes the pending report, decline removes it, and failed send keeps it.
- [ ] **Step 2: Run the focused test and verify RED.**
- [ ] **Step 3: Implement the helper with `umask 077`, deterministic local signature filename, strict enum validation, safe diagnostic extraction, and no raw logs.**
- [ ] **Step 4: Interactive prompt options are Send, Review, and Don't send. Noninteractive invocation queues only and returns success regardless of submission availability.**
- [ ] **Step 5: Run `bash -n`, ShellCheck using existing project exclusions where needed, and the focused test.**
- [ ] **Step 6: Add the focused test to CI and commit.**

### Task 3: Quickshell failure hooks

**Files:**
- Modify: `config/hypr/scripts/quickshell.sh`
- Modify: `config/hypr/scripts/quickshell_resume_recover.sh`
- Modify: `tests/test-quickshell-process-lifecycle.sh`
- Modify: `tests/test-quickshell-resume-recovery.sh`

**Interfaces:**
- Consumes: `awtarchy_report_failure.sh`.
- Produces: one pending report for terminal Awtarchy-owned Quickshell failures without changing existing return codes.

- [ ] **Step 1: Add failing tests proving a Quickshell readiness timeout invokes `quickshell|start|quickshell_not_ready` and still returns the original failure status.**
- [ ] **Step 2: Add failing resume tests for start failure, restart failure, and final missing-bar validation with their exact canonical triples.**
- [ ] **Step 3: Add a small best-effort reporting function beside the existing Quickshell scripts. Reporting errors are swallowed and never replace the original failure.**
- [ ] **Step 4: Distinguish update-triggered restart with an environment marker from the normal `start` failure so the Worker records `restart_after_update`.**
- [ ] **Step 5: Run Bash syntax, focused lifecycle/resume tests, and ShellCheck.**
- [ ] **Step 6: Commit the failure hooks.**

### Task 4: Updater marks update-triggered Quickshell restarts

**Files:**
- Modify: `local/bin/awtarchy`
- Modify: `tests/test-awtarchy-command.sh`

**Interfaces:**
- Consumes: existing `reconcile_quickshell_ui_after_update()` restart path.
- Produces: `AWTARCHY_REPORT_FAILURE_STAGE=restart_after_update` only around the update-triggered manager restart.

- [ ] **Step 1: Add a failing command test proving the marker reaches the Quickshell manager only for the post-update restart path.**
- [ ] **Step 2: Wrap the existing manager restart invocation with the marker while preserving current warning and exit behavior.**
- [ ] **Step 3: Run `bash -n local/bin/awtarchy`, focused command/updater tests, and ShellCheck.**
- [ ] **Step 4: Commit.**

### Task 5: Privacy and operator documentation

**Files:**
- Create: `PRIVACY.md`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `services/report-service/README.md`

**Interfaces:** Documentation only.

- [ ] **Step 1: Replace the absolute README claim that Awtarchy does not collect user data with precise opt-in failure-reporting language.**
- [ ] **Step 2: Document exactly what is and is not sent, local pending-report behavior, Cloudflare transport-metadata caveat, GitHub issue behavior, and how users decline/delete a report.**
- [ ] **Step 3: Add durable AGENTS guidance that failure reporting is an explicit hosted-service exception with consent/privacy/security invariants.**
- [ ] **Step 4: Document Worker deployment and public `/v1/report`; keep `/v1/test` maintainer-only.**
- [ ] **Step 5: Commit docs.**

### Task 6: Full validation, deployment, and real user-flow test

**Files:** no production source changes unless validation exposes a defect.

- [ ] **Step 1: Run report-service `npm test`.**
- [ ] **Step 2: Run affected Awtarchy shell tests plus `bash -n`/ShellCheck and `git diff --check`.**
- [ ] **Step 3: Open a PR from `anonymous-crash-reporting-testing` to `main` so repository CI validates the integrated branch.**
- [ ] **Step 4: Deploy the Worker with `npx wrangler@latest deploy`; do not run the already-applied initial D1 migration.**
- [ ] **Step 5: Trigger a controlled local Quickshell failure on the testing branch, review the sanitized payload, approve sending, and verify the bot-created production-style GitHub issue.**
- [ ] **Step 6: Trigger the same signature again and verify it deduplicates to the same GitHub issue.**
- [ ] **Step 7: After CI and real flow pass, merge the authorized branch to `main`.**
- [ ] **Step 8: Remove or disable `TEST_AUTH_TOKEN` after production validation if the maintenance test endpoint is no longer needed.**
