# Awtarchy Report Service Agent Guide

This file supplements the repository-root `AGENTS.md` for everything under `services/report-service/`.

## Purpose

This directory contains the Cloudflare Worker backend for Awtarchy's user-approved failure-reporting path.

The service is intentionally narrow:

- accept only server-defined Awtarchy failure classes;
- validate all public input strictly;
- deduplicate reports by a server-generated fingerprint;
- create/recover GitHub issues through the restricted Awtarchy Report Bot;
- store aggregate signature state in D1 rather than permanent raw-report history.

## Security and privacy invariants

Treat the public `/v1/report` endpoint as hostile input.

Do not add:

- a production client secret shipped with Awtarchy;
- free-form error text or raw logs;
- username, hostname, home path, MAC, SSID, VPN details, command history, clipboard, or arbitrary file contents;
- a persistent machine, install, or user identifier;
- caller-controlled GitHub title/body/repository/labels/actions/fingerprint.

The report payload must remain a strict structured allowlist. Any schema expansion requires matching client validation, Worker validation, tests, and privacy documentation.

The production route must apply both source-controlled Cloudflare rate-limit bindings before D1/GitHub reporting work. `REPORT_CLIENT_RATE_LIMITER` may combine Cloudflare's transport IP with the canonical failure signature only for its transient counter. Never copy that IP into the payload, D1, GitHub issue content, or a persistent Awtarchy identifier. `REPORT_SIGNATURE_RATE_LIMITER` provides the separate signature-wide ceiling.

If either limiter or the Cloudflare client-IP header is unavailable, fail closed before D1/GitHub reporting work.

## GitHub invariants

The GitHub App target is fixed by Worker environment configuration. Clients do not choose repository or API operations.

Recovery by fingerprint must accept only an issue authored by the exact Awtarchy Report Bot account and containing the exact server-generated fingerprint marker. A public issue created by another GitHub user must never satisfy deduplication merely because it copies a marker.

GitHub API requests must remain bounded by an explicit timeout shorter than the D1 issue-creation lease. Do not allow a creator to remain in GitHub long enough for another request to reclaim the lease while the first request can still complete normally.

Do not broaden the GitHub App beyond Issues read/write plus GitHub's required Metadata read-only permission without an explicit design decision.

## D1 invariants

`crash_signatures` is aggregate state, not a raw event store.

Issue creation uses ownership/lease semantics. A request may change a failed creation to `issue_error` only while it still owns the exact active creation lease. Lookup failures must not clear another request's `creating_issue` state.

If GitHub issue creation may have succeeded while the Worker lost the response, search for the bot-authored fingerprint marker before creating another issue.

Do not re-run `migrations/0001_initial.sql` against the existing production D1 database merely because the source file exists. The production schema predates source-controlled migrations. New schema needs a forward migration.

## Client/Worker compatibility

The client and Worker canonical failure registries must agree exactly on `(component, failure_stage, error_code)`.

Current production classes:

```text
quickshell | start                | quickshell_not_ready
quickshell | restart              | quickshell_not_ready
quickshell | restart_after_update | quickshell_not_ready
resume_recovery | start            | quickshell_start_failed
resume_recovery | restart          | quickshell_restart_failed
resume_recovery | final_validation | expected_bars_missing
```

Fingerprints depend only on stable server-validated identifiers, not diagnostic versions or machine-specific values.

## Validation

Before treating changes as complete, run the report-service tests on supported Node versions and a Wrangler deployment dry run:

```bash
cd services/report-service
npm install --no-audit --no-fund
npm test
npx --yes wrangler@latest deploy --dry-run --outdir /tmp/awtarchy-report-worker
```

CI runs the test matrix on Node 20 and 22 and the Wrangler dry run on Node 22. Do not claim a live deployment from dry-run success.

## Live deployment

Live deployment requires an authenticated Cloudflare Wrangler session:

```bash
node --version
npx wrangler@latest deploy
```

Review any Wrangler local-versus-dashboard configuration warning before accepting it. Do not apply D1 migrations as a side effect of a normal code deploy.
