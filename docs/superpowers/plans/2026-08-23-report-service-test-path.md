# Report Service Test Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify the smallest production-real Cloudflare Worker path that creates exactly one controlled `[TEST]` issue through the Awtarchy Report Bot and deduplicates repeated tests.

**Architecture:** Add a source-controlled Worker under `services/report-service/`. `GET /health` is public and side-effect-free. `POST /v1/test` requires the Cloudflare-only `TEST_AUTH_TOKEN`, uses the existing D1 `crash_signatures` row as the deduplication/issue-creation state, authenticates as the GitHub App with a short-lived JWT and installation token, recovers an already-created issue by its backend fingerprint marker, and never accepts caller-controlled issue content.

**Tech Stack:** Cloudflare Workers ES modules, TypeScript that is compatible with Node 22 type stripping for dependency-free unit tests, D1 SQLite, Web Crypto RS256, GitHub REST API, Wrangler for deployment.

**Spec:** `docs/superpowers/specs/2026-08-23-anonymous-crash-reporting-design.md`

## Global Constraints

- Work only on `anonymous-crash-reporting-testing`.
- Do not enable `POST /v1/report` or any Awtarchy production failure hooks in this phase.
- GitHub App permissions remain Issues read/write and Metadata read-only; no Contents/PR/Actions/Releases/Administration permissions.
- Never commit `GITHUB_APP_PRIVATE_KEY` or `TEST_AUTH_TOKEN`.
- The test route accepts no caller-controlled fingerprint, title, body, labels, repository, or GitHub action.
- Reuse the already-deployed `crash_signatures` schema; do not require a database migration solely for this controlled test.
- A Worker/GitHub failure returns a non-secret error and cannot expose JWTs, installation tokens, or private-key material.
- Repeated controlled tests must converge on one GitHub issue.

---

### Task 1: Health Route and Protected Test Route Shell

**Files:**
- Create: `services/report-service/src/index.ts`
- Create: `services/report-service/tests/worker.test.ts`
- Create: `services/report-service/package.json`

**Interfaces:**
- Produces: `handleRequest(request, env, runTest?) -> Promise<Response>`.
- `POST /v1/test` authenticates `Authorization: Bearer <TEST_AUTH_TOKEN>` using a constant-time string comparison before invoking the test workflow.

- [ ] **Step 1: Write failing route tests**

Cover `GET /health`, unsupported routes, missing test secret, missing/wrong bearer token, and successful authorization through an injected `runTest` function. The success test must prove that the request body cannot control issue contents because no body is read or forwarded.

- [ ] **Step 2: Run tests and verify RED**

Run from `services/report-service`:

```bash
node --test tests/worker.test.ts
```

Expected: failure because `src/index.ts` does not exist.

- [ ] **Step 3: Implement the minimal route shell**

Implement:

```text
GET  /health  -> {ok:true, service:"awtarchy-reports", version:1}
POST /v1/test -> bearer-secret check -> run controlled test
all else      -> 404 JSON
```

Do not log request headers or environment values.

- [ ] **Step 4: Run route tests and verify GREEN**

```bash
node --test tests/worker.test.ts
```

Expected: all route tests pass.

### Task 2: GitHub App Authentication and Issue API

**Files:**
- Create: `services/report-service/src/github.ts`
- Create: `services/report-service/tests/github.test.ts`

**Interfaces:**
- Produces `createAppJwt(appId, privateKeyPem, nowSeconds?)`.
- Produces `createGitHubClient(env)` with methods `findIssueByFingerprint(fingerprint)` and `createTestIssue(fingerprint)`.
- Private-key import accepts both GitHub-style PKCS#1 `BEGIN RSA PRIVATE KEY` PEM and PKCS#8 `BEGIN PRIVATE KEY` PEM by converting PKCS#1 DER to a PKCS#8 wrapper before `crypto.subtle.importKey`.

- [ ] **Step 1: Write failing crypto/API tests**

Use Node's `node:crypto` only in tests to generate throwaway RSA keys. Verify JWT header/payload, verify the RS256 signature with the generated public key, and run the same signing test for PKCS#1 and PKCS#8 PEM exports. Mock `fetch` only at the GitHub HTTP boundary to assert that installation-token requests use the app JWT and issue creation uses the returned installation token.

- [ ] **Step 2: Run tests and verify RED**

```bash
node --test tests/github.test.ts
```

Expected: failure because `src/github.ts` does not exist.

- [ ] **Step 3: Implement GitHub authentication**

Use Web Crypto `RSASSA-PKCS1-v1_5` with SHA-256. JWT payload uses `iat = now - 60`, `exp = now + 540`, and `iss = GITHUB_APP_ID`. Exchange it through `POST /app/installations/{installation_id}/access_tokens`, then use the installation token only for Issues API calls against `GITHUB_OWNER/GITHUB_REPO`.

Every bot-created test issue includes exactly one marker:

```text
<!-- awtarchy-report-fingerprint:<64-lowercase-hex> -->
```

The controlled title is fixed:

```text
[TEST] Awtarchy anonymous crash reporting
```

- [ ] **Step 4: Run crypto/API tests and verify GREEN**

```bash
node --test tests/github.test.ts
```

Expected: all tests pass.

### Task 3: D1 Test Signature, Deduplication, and Recovery

**Files:**
- Create: `services/report-service/src/test-report.ts`
- Create: `services/report-service/tests/test-report.test.ts`
- Create: `services/report-service/migrations/0001_initial.sql`

**Interfaces:**
- Produces `runControlledTest(env, overrides?)`.
- Uses one deterministic SHA-256 fingerprint derived from the fixed canonical string `1|test|report-service|end_to_end|controlled_test`.
- Uses the existing `crash_signatures` columns and statuses `pending_issue`, `creating_issue`, `open`, `issue_error`.

- [ ] **Step 1: Write failing orchestration tests**

Use an in-memory fake D1 adapter to prove:

```text
first request  -> creates one issue and stores issue number/url
second request -> increments/deduplicates and does not call create again
existing marker but missing D1 link -> recovers and links existing issue
active creating_issue lease -> does not create concurrently
stale creating_issue with no GitHub marker -> may reclaim and create
GitHub failure -> marks issue_error and returns non-secret failure
```

- [ ] **Step 2: Run tests and verify RED**

```bash
node --test tests/test-report.test.ts
```

Expected: failure because `src/test-report.ts` does not exist.

- [ ] **Step 3: Implement minimal D1 orchestration**

Use `INSERT OR IGNORE` for the fixed fingerprint. Use `last_seen` as the bounded issue-creation lease timestamp while status is `creating_issue`, avoiding a schema change for this test-only phase. Before reclaiming a stale creation state, call `findIssueByFingerprint`; if the marker already exists, link that issue instead of creating another.

Source-control the exact initial schema already created manually, using `CREATE TABLE IF NOT EXISTS` and `CREATE INDEX IF NOT EXISTS` so it documents/bootstrap-tests cleanly without changing the deployed schema.

- [ ] **Step 4: Run orchestration tests and verify GREEN**

```bash
node --test tests/test-report.test.ts
```

Expected: all tests pass.

### Task 4: Deployment Configuration and Local Validation

**Files:**
- Create: `services/report-service/wrangler.jsonc`
- Create: `services/report-service/README.md`
- Modify: `.github/workflows/validate-awtarchy.yml`

**Interfaces:**
- Wrangler targets Worker `awtarchy-reports` and D1 database `awtarchy-reports-db` with binding `DB`.
- Non-secret values may be source-controlled; `GITHUB_APP_PRIVATE_KEY` and `TEST_AUTH_TOKEN` remain dashboard secrets.

- [ ] **Step 1: Add dependency-free service validation**

`package.json` exposes:

```json
{
  "scripts": {
    "test": "node --test tests/*.test.ts"
  },
  "engines": {
    "node": ">=22"
  }
}
```

CI installs Node 22 with `actions/setup-node`, then runs `npm test` in `services/report-service`. No production credentials are used in CI.

- [ ] **Step 2: Run all report-service tests locally**

```bash
cd services/report-service
npm test
```

Expected: all tests pass.

- [ ] **Step 3: Validate repository diff**

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 4: Commit the backend test path**

Commit message:

```text
feat: add report service test path
```

### Task 5: Real Cloudflare/GitHub End-to-End Test

**Files:**
- No source changes required unless deployment exposes a verified bug.

**Interfaces:**
- Worker URL: `https://awtarchy-reports.dillacorn.workers.dev`
- User supplies the existing Cloudflare-only `TEST_AUTH_TOKEN` locally; it is never pasted into chat or committed.

- [ ] **Step 1: Update local testing branch**

```bash
cd ~/awtarchy
git pull --ff-only origin anonymous-crash-reporting-testing
```

- [ ] **Step 2: Authenticate Wrangler if needed and deploy**

```bash
cd ~/awtarchy/services/report-service
npx wrangler@latest login
npx wrangler@latest deploy
```

`wrangler login` is skipped if the CLI is already authenticated.

- [ ] **Step 3: Verify health**

```bash
curl -fsS https://awtarchy-reports.dillacorn.workers.dev/health | jq
```

Expected:

```json
{"ok":true,"service":"awtarchy-reports","version":1}
```

- [ ] **Step 4: Submit the controlled test without exposing the token**

```bash
read -rsp 'TEST_AUTH_TOKEN: ' TEST_AUTH_TOKEN; echo
curl -fsS -X POST \
  -H "Authorization: Bearer ${TEST_AUTH_TOKEN}" \
  https://awtarchy-reports.dillacorn.workers.dev/v1/test | jq
unset TEST_AUTH_TOKEN
```

Expected: JSON identifying one created GitHub issue titled `[TEST] Awtarchy anonymous crash reporting`.

- [ ] **Step 5: Repeat the same authenticated request**

Expected: response reports deduplication and the same issue number/url; GitHub still contains exactly one matching test issue.

- [ ] **Step 6: Inspect D1 and GitHub**

Confirm `crash_signatures.occurrence_count` increased and the stored `github_issue_number` matches the single bot-created issue. Only after this succeeds is the infrastructure considered validated for later production-report work.
