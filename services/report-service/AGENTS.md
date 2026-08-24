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
- persistent machine, install, or user identifiers.

Cloudflare necessarily processes transport metadata to receive requests. Never describe the system as guaranteeing network-layer anonymity.

## Consent

No production failure report may be transmitted silently. Awtarchy may prepare a sanitized pending report locally, but submission requires explicit user approval.

Do not add automatic submission without a new explicit project decision and corresponding privacy/documentation review.

## Public endpoint security

`POST /v1/report` is public and must be treated as hostile input.

- Keep a strict allowlisted schema and hard request-size limit.
- Reject unknown fields and unsupported failure triples.
- Keep canonical error descriptions server-owned.
- Keep GitHub issue title/body/repository/action server-owned.
- Keep fingerprints server-generated from stable enum-like failure identifiers only.
- Keep `REPORT_RATE_LIMITER` ahead of D1/GitHub work and fail the production route closed if the binding is unavailable.
- Rate-limit by the canonical failure signature, not a persistent user/machine/install identifier. Using IP-based application identity requires a new explicit privacy/design decision.
- Do not ship a production API secret in the open-source client.
- Do not accept arbitrary Markdown, logs, attachments, issue numbers, labels, or GitHub actions from clients.

## GitHub App boundary

The Awtarchy Report Bot requires only:

```text
Issues          Read + Write
Metadata        Read-only
```

Do not add Contents, Pull requests, Actions, Releases, or Administration permissions for this reporting workflow.

The GitHub App private key and maintainer `TEST_AUTH_TOKEN` remain Cloudflare secrets. Never commit, print, return, or store them in D1.

## D1 behavior

D1 stores aggregate bug-signature state, not permanent raw-report history.

Repeated reports for one fingerprint must reuse the same GitHub issue. Preserve the issue-creation lease and fingerprint-marker recovery behavior so concurrent requests or a Worker interruption cannot easily create duplicate issues.

Do not run `migrations/0001_initial.sql` against the existing production database merely to deploy code; the initial schema was created before migrations were source-controlled.

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

For deployment, current Wrangler requires Node 22+:

```bash
node --version
npx wrangler@latest deploy
```

Review any Wrangler local-versus-dashboard configuration warning before accepting it. Do not apply D1 migrations as a side effect of a normal code deploy.
