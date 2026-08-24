# Awtarchy Report Service Agent Guide

This file supplements the repository-root `AGENTS.md` for everything under `services/report-service/`.

## Purpose

This service is the explicitly approved hosted exception to Awtarchy's otherwise local-utility architecture. It receives user-approved, sanitized failure reports, deduplicates known failure signatures in Cloudflare D1, and uses the restricted Awtarchy Report Bot GitHub App to create or recover GitHub issues.

It is observational only. It does not fix code or modify user systems.

## Non-negotiable privacy boundary

Do not broaden the report payload casually.

The production client/report contract must not include:

- username or hostname;
- home-directory paths;
- IP address as an application report field;
- MAC address or SSID;
- VPN/WireGuard details;
- secrets, tokens, or arbitrary environment values;
- command history or clipboard contents;
- arbitrary window titles or file contents;
- raw troubleshooting logs;
- raw diagnostic/error text;
- persistent machine, install, or user identifiers.

Cloudflare necessarily processes transport metadata to receive requests. Never describe the system as guaranteeing network-layer anonymity.

The production route may use Cloudflare's `CF-Connecting-IP` transport value only to partition the transient `REPORT_CLIENT_RATE_LIMITER` counter. Never copy that value into the report payload, D1, GitHub issue content, logs intentionally emitted by this service, or a persistent Awtarchy identifier.

## Consent

No production failure report may be transmitted silently. Awtarchy may prepare a sanitized pending report locally, but submission requires explicit user approval.

Do not add automatic submission without a new explicit project decision and corresponding privacy/documentation review.

## Public endpoint security

`POST /v1/report` is public and must be treated as hostile input.

- Keep a strict allowlisted schema and hard request-size limit.
- Reject unknown fields and unsupported failure triples.
- Keep diagnostic kinds server-owned and enum-like.
- For managed-QML diagnostics, accept only QML basenames in the server-owned allowlist of files Awtarchy actually ships; a generic filename regex is not sufficient.
- Keep canonical error descriptions server-owned.
- Keep GitHub issue title/body/repository/action server-owned.
- Keep fingerprints server-generated from stable enum-like failure identifiers only.
- Keep both rate-limit bindings ahead of D1/GitHub reporting work.
- `REPORT_CLIENT_RATE_LIMITER` combines Cloudflare's transport IP with the canonical failure signature for a small client-specific allowance.
- `REPORT_SIGNATURE_RATE_LIMITER` applies a separate signature-wide ceiling so distributed abuse cannot bypass backend protection merely by changing client address.
- If either binding or the Cloudflare client-IP header is unavailable, fail the production route closed before D1/GitHub reporting work.
- Do not ship a production API secret in the open-source client.
- Do not accept arbitrary Markdown, logs, attachments, issue numbers, labels, or GitHub actions from clients.

Cloudflare rate-limit counters are best-effort abuse controls, not identity or exact accounting systems. Do not persist their client keys.

## GitHub App boundary

The Awtarchy Report Bot requires only:

```text
Issues          Read + Write
Metadata        Read-only
```

Do not add Contents, Pull requests, Actions, Releases, or Administration permissions for this reporting workflow.

The GitHub App private key and maintainer `TEST_AUTH_TOKEN` remain Cloudflare secrets. Never commit, print, return, or store them in D1.

Recovery by fingerprint must trust only issues authored by the exact Awtarchy Report Bot account and containing the exact server-generated fingerprint marker. A public issue created by another GitHub user must never satisfy recovery merely because it copies a marker.

GitHub API calls must remain explicitly bounded below the D1 issue-creation lease. Do not allow one creator to remain in GitHub long enough for another request to reclaim the lease while the first request can still complete normally.

## D1 behavior

D1 stores aggregate bug-signature state, not permanent raw-report history.

Repeated accepted reports for one fingerprint must reuse the same GitHub issue. Preserve the issue-creation lease and fingerprint-marker recovery behavior so concurrent requests or a Worker interruption cannot easily create duplicate issues.

A request may mark creation `issue_error` only while it still owns the exact active creation lease. A lookup failure must not clear another request's `creating_issue` state.

Do not run `migrations/0001_initial.sql` against the existing production database merely to deploy code; the initial schema was created before migrations were source-controlled. Schema changes require a forward migration.

`occurrence_count` records accepted report events, not unique affected users.

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

Optional managed-QML diagnostics are best-effort hints and do not identify a user or machine. The client may emit only a fixed diagnostic kind, a verified Awtarchy-managed QML basename, and bounded numeric line/column. The Worker must independently validate the diagnostic and enforce its own exact QML filename allowlist.

Fingerprints depend only on stable server-validated failure identifiers, not diagnostic versions, managed-QML diagnostics, or machine-specific values.

## Failure isolation

Reporting is secondary. Client-side reporting failure must never change the original Awtarchy/Quickshell operation result, replace its exit code, or interfere with recovery.

Backend errors must never expose private keys, JWTs, installation tokens, request internals containing secrets, or secret-bearing stack traces.

## Validation

For backend changes, run at minimum:

```bash
cd services/report-service
npm install --no-audit --no-fund
npm test
```

CI runs the report-service matrix on Node 20 and Node 22. Node 22 also runs a Wrangler deployment dry run to validate source-controlled bindings/configuration:

```bash
npx --yes wrangler@latest deploy --dry-run --outdir /tmp/awtarchy-report-worker
```

Do not claim a live deployment from dry-run success.

## Live deployment

For deployment, current Wrangler requires Node 22+:

```bash
node --version
npx wrangler@latest deploy
```

Review any Wrangler local-versus-dashboard configuration warning before accepting it. Do not apply D1 migrations as a side effect of a normal code deploy.
