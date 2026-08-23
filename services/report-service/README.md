# Awtarchy Report Service

Cloudflare Worker backend for Awtarchy's privacy-conscious failure-reporting system.

This initial testing phase exposes only:

- `GET /health` — side-effect-free readiness check.
- `POST /v1/test` — maintainer-only end-to-end test that creates or recovers one fixed GitHub test issue through the Awtarchy Report Bot.

Production `POST /v1/report` and Awtarchy client failure hooks are intentionally not enabled yet.

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

Never commit `GITHUB_APP_PRIVATE_KEY` or `TEST_AUTH_TOKEN`.

The GitHub App requires only Issues read/write plus GitHub's required Metadata read-only permission. It has no Contents, Pull requests, Actions, Releases, or Administration access.

## Tests

Requires Node.js 22 or newer.

```bash
cd services/report-service
npm test
```

Tests use generated throwaway RSA keys and fake GitHub/D1 boundaries. No production Cloudflare or GitHub credentials are needed.

## Deploy

The production D1 schema was created manually before this source-controlled service existed. `migrations/0001_initial.sql` records that schema for reproducibility, but do not run the initial migration against the existing production database merely to deploy this first test path.

From this directory:

```bash
npx wrangler@latest login
npx wrangler@latest deploy
```

Skip `wrangler login` when already authenticated.

`wrangler.jsonc` uses `keep_vars: true` so dashboard-managed runtime variables remain in place. Cloudflare secrets remain managed outside the repository.

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
