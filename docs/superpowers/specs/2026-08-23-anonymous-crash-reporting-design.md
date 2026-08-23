# Anonymous Crash Reporting Design

## Goal

Add a privacy-conscious, user-approved failure-reporting path for Awtarchy that can turn real Awtarchy failures into deduplicated GitHub issues without requiring affected users to have GitHub accounts.

The reporting system is observational only. It may create or update GitHub issues through the dedicated Awtarchy Report Bot, but it must never modify repository contents, create branches, open pull requests, merge code, publish releases, or otherwise fix code automatically.

## Plain-English flow

```text
Awtarchy detects a known Awtarchy failure
    -> prepares a small sanitized report locally
    -> user reviews/sends or declines
    -> Cloudflare Worker validates it again
    -> Worker computes a server-controlled bug fingerprint
    -> D1 records or increments that fingerprint
    -> Awtarchy Report Bot creates one GitHub issue for a new fingerprint
    -> repeated reports increment the same fingerprint instead of creating spam
```

A reporting failure must never change the result of the original Awtarchy operation. Reporting is secondary and must fail harmlessly.

## Scope

Version 1 reports only failures Awtarchy can confidently attribute to Awtarchy-owned operations or components.

Initial reportable classes:

- `awtarchy update`, `reset`, or `git` failure where Awtarchy already has structured stage/error context;
- updater recovery/fallback failure;
- Quickshell fails to start or restart through Awtarchy's `quickshell.sh` manager;
- Quickshell resume recovery fails after Awtarchy has exhausted its existing recovery sequence.

Version 1 does not monitor arbitrary applications, the entire Arch system, unrelated systemd failures, generic kernel crashes, or failures Awtarchy cannot confidently associate with its own code.

## User consent and privacy model

Failure detection and local diagnostic capture are enabled by default.

No report is transmitted silently.

When a reportable failure occurs, Awtarchy records a sanitized pending report locally. Once the desktop/session is usable, the user is informed that Awtarchy detected a failure and can help improve the project by submitting the prepared report.

The initial choices are:

- Send report
- Review report
- Do not send

A future opt-in may allow automatic submission of later reports, but that is outside version 1.

The reporting client never sends raw troubleshooting logs wholesale. It builds a strict structured payload from an allowlist of diagnostic fields.

Explicitly excluded from the payload:

- username;
- hostname;
- home-directory path;
- IP addresses as report fields;
- MAC addresses;
- SSIDs;
- WireGuard/private VPN details;
- environment secrets or tokens;
- arbitrary command history;
- clipboard contents;
- arbitrary window titles;
- arbitrary file contents;
- persistent machine UUID or install identifier.

The application does not intentionally store the request IP as report data. Cloudflare necessarily processes network connection metadata to receive the request and may retain infrastructure/security logs according to Cloudflare behavior and account settings. Project documentation must therefore avoid claiming absolute network-layer anonymity.

GitHub issues created by the bot contain no Awtarchy user identity or persistent client identifier.

## Repository layout

The backend lives inside the existing Awtarchy repository:

```text
services/report-service/
├── src/
│   └── index.ts
├── migrations/
│   ├── 0001_initial.sql
│   └── 0002_issue_state.sql   # only if implementation needs schema additions
├── package.json
├── tsconfig.json
├── wrangler.jsonc
└── README.md
```

Client-side reporting support stays with the existing Awtarchy runtime/scripts rather than creating a second unrelated client framework.

## Existing infrastructure and GitHub permission boundary

The deployed infrastructure already exists:

- Cloudflare Worker: `awtarchy-reports`
- Worker URL: `awtarchy-reports.dillacorn.workers.dev`
- D1 binding: `DB`
- D1 database: `awtarchy-reports-db`
- GitHub App: Awtarchy Report Bot
- GitHub App ID: `4695629`
- GitHub installation ID: `156041074`
- GitHub repository: `dillacorn/awtarchy`

The GitHub App's effective repository permissions are intentionally narrow:

```text
Issues          Read + Write
Metadata        Read-only
Contents        No access
Pull requests   No access
Actions         No access
Releases        No access
Administration  No access
```

`Metadata: read-only` is GitHub's basic app metadata permission. It is not general read access to repository contents.

The GitHub private key remains only in the Cloudflare `GITHUB_APP_PRIVATE_KEY` secret and must never be added to the repository, client, issue body, logs, or D1.

## Backend endpoints

### `GET /health`

Returns basic service readiness without exposing secrets or GitHub tokens.

Expected response shape:

```json
{
  "ok": true,
  "service": "awtarchy-reports",
  "version": 1
}
```

This endpoint must not create database rows or GitHub issues.

### `POST /v1/report`

Accepts a strict JSON report payload from released Awtarchy clients.

Example logical payload:

```json
{
  "schema_version": 1,
  "report_type": "failure",
  "component": "quickshell",
  "failure_stage": "restart",
  "error_code": "quickshell_not_ready",
  "awtarchy_config_version": "v3.1.6",
  "awtarchy_command_revision": "<40-char sha>",
  "hyprland_version": "0.51.1",
  "quickshell_version": "0.2.0",
  "kernel_version": "6.x.y-arch1-1",
  "gpu_family": "AMD",
  "context": {
    "recovery_attempted": true,
    "recovery_succeeded": false
  }
}
```

The client does not send a free-form `normalized_error`. The Worker maps recognized `(component, failure_stage, error_code)` combinations to a canonical server-owned error description.

The exact client schema is allowlisted. Unknown top-level fields are rejected rather than silently stored.

Payload size is capped at 32 KiB or less.

### `POST /v1/test`

The controlled end-to-end test is separate from normal public reporting.

It is disabled unless a Cloudflare-only test secret is configured. Requests must authenticate with that secret. The secret is never shipped in Awtarchy source or binaries.

The endpoint accepts no caller-controlled issue title/body/fingerprint. It emits one fixed test signature and one fixed backend-generated test issue format.

After the end-to-end test is complete, the test secret can be removed or the endpoint can remain disabled by configuration.

## Validation and canonical error registry

The Worker validates:

- request method and content type;
- JSON parse success;
- supported schema version;
- allowed report type;
- required fields;
- recognized component/stage/error combinations;
- bounded string lengths;
- allowlisted context keys and value types;
- version/revision formatting where applicable;
- total request size.

The Worker owns a small canonical registry such as:

```text
quickshell + restart + quickshell_not_ready
    -> "Quickshell did not become ready after restart"

resume_recovery + final_validation + expected_bars_missing
    -> "Expected Quickshell bar layers remained absent after recovery"
```

Unknown combinations are rejected. Clients cannot manufacture new failure classes by changing a text string.

The client cannot provide:

- fingerprint;
- canonical error description;
- GitHub issue title;
- GitHub issue body;
- labels;
- arbitrary Markdown;
- repository owner/name;
- GitHub issue number;
- GitHub API action.

Those values/actions are generated by the backend from validated structured data.

## Fingerprinting and deduplication

The backend computes the canonical fingerprint. The client never chooses it.

The version-1 fingerprint is derived only from stable, server-validated identifiers:

- schema version;
- report type;
- component;
- failure stage;
- error code.

Free-form text is never part of the fingerprint.

Machine/version-specific values such as kernel, GPU family, Awtarchy version, Hyprland version, and Quickshell version are diagnostic context only. They do not split one bug into separate issues unless a future schema intentionally changes that rule.

The canonical fingerprint is a SHA-256 digest over a deterministic serialization of those server-validated fields.

For an existing fingerprint, D1 atomically increments `occurrence_count` and updates `last_seen`/`last_version`. It does not create another GitHub issue.

For a new valid fingerprint, D1 establishes ownership of issue creation before the Worker calls GitHub so concurrent identical requests cannot intentionally create multiple issues.

## Issue creation state and crash recovery

Issue creation must tolerate concurrent requests and Worker/GitHub failures.

The logical states are:

```text
pending_issue
creating_issue
open
issue_error
```

The exact implementation may use the existing `status` column or a focused follow-up migration if additional timestamps/state are required.

Rules:

1. The first request atomically inserts the fingerprint or wins a conditional transition to `creating_issue`.
2. Other concurrent requests increment the same aggregate row and do not create an issue.
3. Every bot-created issue contains a backend-generated fingerprint marker in its body, for example an HTML comment containing only the SHA-256 fingerprint.
4. If a Worker dies or loses the GitHub response after issue creation, a later recovery attempt searches issues using the bot's Issues read permission for that fingerprint marker before creating anything new.
5. If an issue already exists, the Worker links the D1 row to it instead of creating a duplicate.
6. A stale `creating_issue` state may be reclaimed only after a bounded timeout and the GitHub fingerprint check.

This makes duplicate creation unlikely even across concurrency, transient GitHub failures, or a Worker interruption between GitHub creation and the D1 update.

## D1 schema

The database already contains the initial schema below. Source control must reproduce it in `services/report-service/migrations/0001_initial.sql`:

```sql
CREATE TABLE crash_signatures (
    fingerprint TEXT PRIMARY KEY,
    component TEXT NOT NULL,
    normalized_error TEXT NOT NULL,
    first_seen TEXT NOT NULL,
    last_seen TEXT NOT NULL,
    first_version TEXT,
    last_version TEXT,
    occurrence_count INTEGER NOT NULL DEFAULT 1,
    github_issue_number INTEGER,
    github_issue_url TEXT,
    status TEXT NOT NULL DEFAULT 'open'
);

CREATE INDEX idx_crash_signatures_last_seen
ON crash_signatures(last_seen);

CREATE INDEX idx_crash_signatures_issue
ON crash_signatures(github_issue_number);
```

`normalized_error` in D1 stores the server-owned canonical description, not caller-provided text.

If safe issue-creation recovery requires fields not present in this deployed schema, implementation must add a forward migration rather than silently changing the already-applied `0001_initial.sql` semantics.

Version 1 stores aggregate signature state, not a permanent raw-report history.

## GitHub authentication

The Worker authenticates as the GitHub App, not as the Awtarchy user.

Flow:

1. Worker signs a short-lived GitHub App JWT using `GITHUB_APP_PRIVATE_KEY` and `GITHUB_APP_ID`.
2. Worker exchanges that JWT for an installation access token using `GITHUB_INSTALLATION_ID`.
3. Worker uses the short-lived installation token only for GitHub Issues operations in `GITHUB_OWNER/GITHUB_REPO`.

The private key is never returned, logged, stored in D1, or sent to an Awtarchy client.

Installation access tokens are short-lived runtime values. They are not persisted to D1 or returned to clients.

## GitHub issue behavior

New failure issues use backend-generated content, for example:

```text
Automatic failure report: Quickshell restart did not become ready
```

The issue body clearly states that it was created by Awtarchy's user-approved anonymous failure-reporting path and includes only sanitized structured diagnostics.

The body also contains the server-generated fingerprint marker used for duplicate recovery. The marker identifies the bug signature, not a machine or user.

Duplicate reports do not create duplicate issues.

Version 1 records duplicate occurrence counts in D1. GitHub issue comments/updates are conservative. A later implementation may update the issue only at useful thresholds such as 5, 10, 25, and 50 occurrences.

The report bot has no repository-content permission and cannot modify code or fix the issue automatically.

## Controlled end-to-end test

A controlled test report must exercise the real path:

```text
maintainer test request
  -> Cloudflare Worker
  -> D1
  -> GitHub App
  -> dillacorn/awtarchy issue
```

The test uses a fixed, unmistakable signature and produces one issue titled approximately:

```text
[TEST] Awtarchy anonymous crash reporting
```

The `/v1/test` route requires a Cloudflare-only secret that is not committed or shipped to users.

Repeated authenticated test runs must deduplicate against the same D1 fingerprint instead of producing new issues.

The test issue may be closed manually after validation.

The first implementation must not enable production client submission hooks until this end-to-end test succeeds.

## Client-side pending report model

Awtarchy stores prepared reports under user state, not cache, because a pending report must survive logout/reboot.

Proposed location:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy/reports/
```

A pending report contains only the already-sanitized structured payload. Raw logs remain in their existing locations and are not automatically transmitted.

Report files use restrictive permissions (`umask 077`).

After successful submission or explicit rejection, the corresponding pending report is removed or marked resolved so the user is not prompted repeatedly for the same event.

No persistent install ID is added merely to correlate pending reports.

## User notification

Version 1 prioritizes reliability over a complicated UI.

Notification order:

1. If Quickshell is healthy, surface an Awtarchy failure-report prompt through the existing shell/UI integration.
2. If the shell is unavailable, preserve the pending report and show the prompt the next time the `awtarchy` maintenance command is opened.
3. Do not automatically spawn terminals during a broken session merely to ask for submission consent.

The report can be reviewed as plain structured text before submission.

Reviewing a report never transmits it.

## Initial client failure hooks

### Awtarchy maintenance/update runtime

Capture a pending report only when an Awtarchy-owned operation reaches a known failure path with enough structured context to classify the problem.

Do not turn every non-zero external command into an anonymous report.

The reporting helper must preserve the operation's original exit status. A report-generation or submission problem cannot convert success to failure, failure to success, or replace the original error.

### Quickshell manager

Candidate version-1 report point:

- `start_shell` exhausts its readiness window and returns `quickshell_not_ready`.

A deliberate user stop is not a crash report.

### Resume recovery

Candidate version-1 report points after existing recovery has been exhausted:

- Quickshell manager fails to start after resume;
- restart fails during resume recovery;
- expected bar layers remain absent after the full restart sequence.

Intermediate recoverable states are not reported as failures if Awtarchy successfully self-recovers.

## Abuse controls

The public Worker endpoint is treated as hostile input.

Version 1 protections:

- strict allowlisted schema;
- hard payload-size limit;
- bounded strings and allowlisted context;
- server-owned canonical error registry;
- server-generated fingerprints from enum-like identifiers only;
- atomic D1 deduplication/issue-creation claiming;
- fixed target repository;
- server-generated issue title/body;
- no arbitrary Markdown supplied by clients;
- no client control over GitHub issue numbers/actions;
- protected `/v1/test` route;
- Cloudflare-side request/rate protections where practical;
- backend refuses unsupported/future schema versions;
- conservative GitHub issue creation behavior.

An embedded production client API secret is explicitly not used because Awtarchy is open source and any shipped secret would be public.

The test secret is different: it is maintainer-only, never shipped to clients, and exists solely to validate infrastructure.

If abuse appears in practice, Cloudflare rate limits/WAF rules or stronger server-side throttling can be added without changing the privacy model.

## Error handling

Report submission must never interfere with recovery or normal Awtarchy operation.

If the Worker is unavailable, GitHub authentication fails, D1 fails, or the network is offline:

- the original Awtarchy operation and exit status remain unchanged;
- the pending report remains local;
- Awtarchy reports that submission failed and can be retried later;
- no retry loop runs indefinitely;
- no reporting exception is allowed to crash Quickshell or the maintenance command.

The Worker returns structured non-secret errors and never includes GitHub credentials, JWTs, installation tokens, private-key material, stack traces containing secrets, or raw request internals.

## Testing

Backend tests cover at minimum:

- `/health` success;
- malformed JSON rejection;
- wrong content type;
- unsupported schema version;
- unknown field rejection;
- unknown component/stage/error combination rejection;
- overlong/oversized values;
- caller cannot supply a canonical error/fingerprint/title/body;
- deterministic server-side fingerprinting;
- new-signature insertion;
- duplicate increment without issue duplication;
- concurrent identical reports result in one issue-creation owner;
- stale `creating_issue` recovery checks GitHub before recreation;
- GitHub API failure leaves a recoverable database state;
- secret values never appear in responses/logging fixtures;
- `/v1/test` is unavailable without the maintainer secret;
- repeated authenticated tests deduplicate.

Client tests cover at minimum:

- failure hooks create sanitized pending reports;
- successful recovery does not create a report;
- pending report survives until action;
- review does not transmit;
- reject does not transmit;
- send invokes only the configured reporting endpoint;
- failed submission retains the pending report;
- successful submission resolves it;
- known sensitive strings are removed/rejected before payload creation;
- report handling preserves the original operation exit status.

Existing `tests/test-troubleshoot-command.sh`, Quickshell process/recovery tests, updater tests, and security-boundary tests remain regression coverage and should be extended rather than bypassed.

## CI

Awtarchy CI validates the report-service source and migrations alongside existing validation.

The report-service must be testable without real Cloudflare or GitHub credentials. Production GitHub issue creation is validated separately through the controlled test issue.

No production private keys or installation tokens are stored as GitHub repository secrets solely to run unit tests.

## Documentation changes

Before release, update:

- `AGENTS.md` with the report-service architecture, exact GitHub permission boundary, and privacy model;
- `README.md` or a focused privacy/reporting document describing that local capture is default but submission requires explicit approval;
- report-service README with Cloudflare/D1 deployment requirements;
- the current statement that Awtarchy does not collect user data so it accurately distinguishes local diagnostics from user-approved report submission.

Documentation must not imply that Awtarchy can identify the reporting user from the report payload, and must not promise that Cloudflare never processes transport metadata.

## Non-goals for version 1

- silent telemetry;
- automatic report submission without user approval;
- automatic code fixes;
- repository contents write access for the report bot;
- repository contents read access for the report bot;
- arbitrary bug reports entered by users;
- arbitrary attachments/raw logs;
- full-system crash monitoring;
- unique machine tracking;
- analytics dashboards;
- automatic GitHub issue closure;
- paid third-party crash-reporting service dependency.

## Success criteria

Version 1 is successful when:

1. a controlled authenticated test reaches the real Cloudflare Worker;
2. the Worker validates and stores a single fixed test fingerprint in D1;
3. the Awtarchy Report Bot creates exactly one `[TEST]` issue in `dillacorn/awtarchy`;
4. repeating the same test does not create another issue;
5. the report bot still has only Issues read/write plus Metadata read-only;
6. no GitHub credential or maintainer test secret exists in client or repository source;
7. production fingerprints depend only on server-validated identifiers, not caller-controlled error text;
8. issue creation safely handles concurrency and recoverable partial failure;
9. production report hooks remain user-approved and scoped only to defined Awtarchy failures;
10. reporting cannot alter the original Awtarchy operation's result or exit status;
11. existing Awtarchy tests remain passing.
