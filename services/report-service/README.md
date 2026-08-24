# Awtarchy Report Service

Cloudflare Worker backend for Awtarchy's privacy-conscious, user-approved failure-reporting system.

Endpoints:

- `GET /health` — side-effect-free readiness check.
- `POST /v1/report` — public production endpoint for the strict sanitized Awtarchy failure-report schema.
- `POST /v1/test` — maintainer-only end-to-end test that creates or recovers one fixed GitHub test issue through the Awtarchy Report Bot.

The public report endpoint has no client secret. Awtarchy is open source, so any secret shipped in the client would not provide authentication. Instead, the Worker treats every request as hostile input and accepts only fixed known failure classes and bounded structured fields.

## Runtime configuration

The Worker uses the existing D1 binding:

```text
DB -> awtarchy-reports-db
```

Cloudflare runtime variables/secrets:

```text
GITHUB_APP_ID              Text
GITHUB_APP_PRIVATE_KEY     Secret
GITHUB_INSTALLATION_ID     Text
GITHUB_OWNER               Text
GITHUB_REPO                Text
TEST_AUTH_TOKEN            Secret
```

The Worker also uses the source-controlled `REPORT_CLIENT_RATE_LIMITER` and `REPORT_SIGNATURE_RATE_LIMITER` Cloudflare Rate Limiting bindings for the public production route.

Never commit `GITHUB_APP_PRIVATE_KEY` or `TEST_AUTH_TOKEN`.

The GitHub App requires only Issues read/write plus GitHub's required Metadata read-only permission. It has no Contents, Pull requests, Actions, Releases, or Administration access.

## Production report contract

`POST /v1/report` requires `Content-Type: application/json`, rejects bodies over 32 KiB, rejects unknown fields, and recognizes only server-defined failure triples.

Version 1 recognizes:

```text
quickshell | start                | quickshell_not_ready
quickshell | restart              | quickshell_not_ready
quickshell | restart_after_update | quickshell_not_ready
resume_recovery | start            | quickshell_start_failed
resume_recovery | restart          | quickshell_restart_failed
resume_recovery | final_validation | expected_bars_missing
```

The accepted structured diagnostics are limited to Awtarchy config/revision, Hyprland version, Quickshell version, kernel version, broad GPU family, fixed boolean recovery context, and an optional tightly bounded managed-QML diagnostic.

The optional QML diagnostic accepts only:

```json
{
  "diagnostic": {
    "kind": "qml_parse_error",
    "managed_file": "Theme.qml",
    "line": 65,
    "column": 1
  }
}
```

`kind` must be one of `qml_parse_error`, `qml_import_error`, `qml_type_error`, or `qml_load_error`. `managed_file` must be the basename of a QML file in the Worker's server-owned allowlist of files Awtarchy actually ships under `config/quickshell/awtarchy/`; merely looking like a `.qml` filename is not sufficient, and paths are rejected. Line and column must be positive bounded integers. There is no field for raw log text, exception text, module text, arbitrary diagnostic strings, or filesystem paths.

The open-source client applies a separate first boundary before creating this object: it reads only a bounded tail of the Awtarchy Quickshell log, requires the log and managed configuration directory to be user-owned non-symlinks, and emits the basename only when the corresponding regular QML file exists inside Awtarchy's managed Quickshell directory.

Clients cannot provide the fingerprint, canonical error description, GitHub title/body, labels, repository, issue number, or GitHub API action. The Worker generates those values after validation.

The D1/GitHub bug fingerprint is SHA-256 over the fixed failure class and, when present, only the safe diagnostic class:

```text
schema_version | report_type | component | failure_stage | error_code
[| diagnostic | diagnostic_kind | managed_qml_basename]
```

This lets a recognized `qml_parse_error` in `Theme.qml` create a distinct actionable issue instead of disappearing into an older generic `quickshell_not_ready` issue. Line, column, Awtarchy config version, command revision, runtime versions, GPU family, and recovery context never enter the fingerprint. Moving the same class of error within the same managed file therefore still deduplicates.

Cloudflare rate limiting deliberately does **not** use the refined diagnostic fingerprint. Both production limiters remain keyed by the original coarse failure class:

```text
schema_version | report_type | component | failure_stage | error_code
```

A hostile caller therefore cannot increase the rate-limit budget by rotating among allowed diagnostic kinds or managed filenames.

## Abuse protection

After schema validation and before any D1/GitHub reporting work, `/v1/report` applies two Cloudflare native Rate Limiting bindings.

The client limiter allows three calls per 60 seconds for each `CF-Connecting-IP` plus coarse canonical failure-class pair in a Cloudflare location. This prevents one transport client from immediately consuming the entire signature-wide budget. The source IP is used only for this transient Cloudflare counter; it is not written into the report payload, D1, GitHub, or a persistent Awtarchy identifier.

The signature limiter then allows 20 calls per 60 seconds for each coarse canonical failure class in a Cloudflare location. This provides a separate ceiling on D1/GitHub work even if abuse is distributed across clients.

Cloudflare documents Worker rate-limit counters as location-local, permissive, and eventually consistent. These limits are therefore best-effort abuse reduction and D1 protection, not strict global request caps or accounting. Cloudflare also cautions that IPs may be shared by legitimate users, which is why Awtarchy does not use the client-IP limiter as its only abuse boundary.

If either rate-limiter binding is unavailable, the production route fails closed with `503`. If either limiter rejects a request, the Worker returns `429` before D1/GitHub reporting work. Awtarchy keeps a failed submission pending locally so it can be retried later.

## D1 and deduplication

D1 stores aggregate signature state rather than permanent raw-report history. Repeated valid reports for the same server-generated bug fingerprint increment the same row instead of creating a new GitHub issue. `occurrence_count` represents accepted report events, not unique affected users.

Issue creation uses a short ownership lease and a fingerprint marker in the GitHub issue body. If issue creation succeeds but the Worker loses the response before linking D1, a later request searches existing issues for the exact marker and recovers the link before creating another issue. Recovery accepts only issues authored by the Awtarchy Report Bot.

GitHub API calls are bounded by explicit request timeouts so one creation attempt cannot outlive the D1 creation lease under normal request execution.

## Tests

The focused test suite supports Node.js 20.6 or newer. Install the report-service development dependency, then run the tests:

```bash
cd services/report-service
npm install --no-audit --no-fund
npm test
```

Tests use generated throwaway RSA keys and fake GitHub/D1 boundaries. No production Cloudflare or GitHub credentials are needed.

CI also runs a Wrangler deployment dry run on Node 22 so source-controlled Worker bindings and configuration are parsed before a live deploy.

## Deploy

Current Wrangler releases require Node.js 22 or newer. On Arch Linux, use the supported `nodejs-lts-jod` package (or another supported Node 22+ runtime) before deploying.

The production D1 schema was created manually before this source-controlled service existed. `migrations/0001_initial.sql` records that schema for reproducibility. Do **not** run the initial migration against the existing production database merely to deploy code.

From this directory:

```bash
node --version
npx wrangler@latest login
npx wrangler@latest deploy
```

Skip `wrangler login` when already authenticated.

`wrangler.jsonc` uses `keep_vars: true` and records the dashboard-backed text variables, D1 binding, both rate-limiter bindings, preview setting, and observability settings. Cloudflare secrets remain managed outside the repository.

## Verify health

```bash
curl -fsS https://awtarchy-reports.dillacorn.workers.dev/health | jq
```

Expected:

```json
{
  "ok": true,
  "service": "awtarchy-reports",
  "version": 1
}
```

## Controlled GitHub issue test

Use the same `TEST_AUTH_TOKEN` value stored in Cloudflare. Do not put it in shell history or repository files.

```bash
read -rsp 'TEST_AUTH_TOKEN: ' TEST_AUTH_TOKEN; echo
curl -fsS -X POST \
  -H "Authorization: Bearer ${TEST_AUTH_TOKEN}" \
  https://awtarchy-reports.dillacorn.workers.dev/v1/test | jq
unset TEST_AUTH_TOKEN
```

The first successful request creates exactly one issue titled:

```text
[TEST] Awtarchy anonymous crash reporting
```

Repeating the authenticated request must return the same issue number with `deduplicated: true` instead of creating another issue.

The controlled test contains no user diagnostic data. Its server-generated fingerprint identifies only this fixed test signature, not a user or machine.

After production reporting is proven and the maintenance endpoint is no longer useful, remove `TEST_AUTH_TOKEN` from the Worker to disable `/v1/test`.

## Privacy

See the repository root [PRIVACY.md](../../PRIVACY.md). The Worker does not intentionally store request IPs as report fields or persistent client identifiers. It uses Cloudflare's client-IP transport header only to partition the first transient rate-limit counter. Cloudflare still necessarily processes connection metadata at the infrastructure layer.
