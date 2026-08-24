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

The Worker also uses the source-controlled `REPORT_RATE_LIMITER` Cloudflare Rate Limiting binding for the public production route.

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

The accepted structured diagnostics are limited to Awtarchy config/revision, Hyprland version, Quickshell version, kernel version, broad GPU family, and fixed boolean recovery context.

Clients cannot provide the fingerprint, canonical error description, GitHub title/body, labels, repository, issue number, or GitHub API action. The Worker generates those values after validation.

The fingerprint is SHA-256 over only:

```text
schema_version | report_type | component | failure_stage | error_code
```

Machine/version diagnostics do not split one bug into separate signatures.

## Abuse protection

After schema validation and before any D1/GitHub work, `/v1/report` uses Cloudflare's native Rate Limiting binding. Version 1 allows at most five accepted requests per 60 seconds for each canonical failure signature. The limiter key is the same stable server-validated signature material used for fingerprinting; Awtarchy does not add a user, machine, install, or IP identifier to that key.

If the rate-limiter binding is unavailable, the production route fails closed with `503` rather than accepting unprotected reports. If a signature exceeds the configured limit, the Worker returns `429` and does not call the D1/GitHub reporting workflow. Awtarchy keeps a failed submission pending locally so it can be retried later.

The limiter is intentionally before D1 because the Workers Free plan has bounded daily D1 write capacity. It is abuse protection, not an accounting or identity system.

## D1 and deduplication

D1 stores aggregate signature state rather than permanent raw-report history. Repeated valid reports for the same server-generated fingerprint increment the same row instead of creating a new GitHub issue.

Issue creation uses a short ownership lease and a fingerprint marker in the GitHub issue body. If issue creation succeeds but the Worker loses the response before linking D1, a later request searches existing issues for the exact marker and recovers the link before creating another issue.

## Tests

The focused test suite supports Node.js 20.6 or newer. Install the report-service development dependency, then run the tests:

```bash
cd services/report-service
npm install --no-audit --no-fund
npm test
```

Tests use generated throwaway RSA keys and fake GitHub/D1 boundaries. No production Cloudflare or GitHub credentials are needed.

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

`wrangler.jsonc` uses `keep_vars: true` and records the dashboard-backed text variables, D1 binding, rate-limiter binding, preview setting, and observability settings. Cloudflare secrets remain managed outside the repository.

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

See the repository root [PRIVACY.md](../../PRIVACY.md). The Worker does not intentionally store request IPs as report fields or add persistent client identifiers. Cloudflare still necessarily processes connection metadata at the infrastructure layer.
