# Anonymous Crash Reporting Design

## Goal

Add a privacy-conscious, user-approved failure-reporting path for Awtarchy that can turn real Awtarchy failures into deduplicated GitHub issues without requiring affected users to have GitHub accounts.

The reporting system must remain observational only. It may create or update GitHub issues through the dedicated Awtarchy Report Bot, but it must never modify repository contents, create branches, open pull requests, merge code, publish releases, or otherwise fix code automatically.

## Scope

Version 1 reports only failures Awtarchy can confidently attribute to Awtarchy-owned operations or components.

Initial reportable classes:

- `awtarchy update`, `reset`, or `git` failure where Awtarchy already has structured stage/error context;
- updater recovery/fallback failure;
- Quickshell fails to start or restart through Awtarchy's `quickshell.sh` manager;
- Quickshell resume recovery fails after Awtarchy has exhausted its existing recovery sequence.

Version 1 does not monitor arbitrary applications, the entire Arch system, unrelated systemd failures, generic kernel crashes, or failures that Awtarchy cannot confidently associate with its own code.

## User consent and privacy model

Failure detection and local diagnostic capture are enabled by default.

No report is transmitted silently.

When a reportable failure occurs, Awtarchy records a sanitized pending report locally. Once the desktop/session is usable, the user is informed that Awtarchy detected a failure and can help improve the project by submitting the prepared report.

The initial choices are:

- Send report
- Review report
- Do not send

A future opt-in may allow automatic submission of later reports, but that is outside version 1.

The reporting client must never send raw troubleshooting logs wholesale. It builds a strict structured payload from an allowlist of diagnostic fields.

Explicitly excluded from the payload:

- username;
- hostname;
- home-directory path;
- IP addresses;
- MAC addresses;
- SSIDs;
- WireGuard/private VPN details;
- environment secrets or tokens;
- arbitrary command history;
- clipboard contents;
- arbitrary window titles;
- arbitrary file contents;
- persistent machine UUID or install identifier.

The backend does not intentionally persist the request IP as report data. Normal Cloudflare transport/security infrastructure may still process connection metadata independently of the application payload, so documentation must not claim absolute network-layer anonymity.

## Repository layout

The backend lives inside the existing Awtarchy repository:

```text
services/report-service/
├── src/
│   └── index.ts
├── migrations/
│   └── 0001_initial.sql
├── package.json
├── tsconfig.json
├── wrangler.jsonc
└── README.md
```

Client-side reporting support stays with the existing Awtarchy runtime/scripts rather than creating a second unrelated client framework.

## Existing infrastructure

The deployed infrastructure already exists:

- Cloudflare Worker: `awtarchy-reports`
- Worker URL: `awtarchy-reports.dillacorn.workers.dev`
- D1 binding: `DB`
- D1 database: `awtarchy-reports-db`
- GitHub App: Awtarchy Report Bot
- GitHub App ID: `4695629`
- GitHub installation ID: `156041074`
- GitHub repository: `dillacorn/awtarchy`
- GitHub App repository permissions: Metadata read-only, Issues read/write

The GitHub private key remains only in the Cloudflare `GITHUB_APP_PRIVATE_KEY` secret and must never be added to the repository.

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

Accepts a strict JSON report payload.

Example logical fields:

```json
{
  "schema_version": 1,
  "report_type": "failure",
  "component": "quickshell",
  "failure_stage": "restart",
  "error_code": "quickshell_not_ready",
  "normalized_error": "Quickshell did not become ready after restart",
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

The exact client schema is allowlisted. Unknown top-level fields are rejected rather than silently stored.

Payload size is capped. Version 1 should target a hard limit no larger than 32 KiB.

## Validation and normalization

The Worker validates:

- request method and content type;
- JSON parse success;
- supported schema version;
- allowed report type;
- required fields;
- enum-like component/stage/error identifiers;
- bounded string lengths;
- bounded context keys and values;
- version/revision formatting where applicable;
- total request size.

The client cannot provide:

- GitHub issue title;
- GitHub issue body;
- labels;
- arbitrary Markdown;
- repository owner/name;
- GitHub issue number.

Those are generated by the backend from validated structured data.

## Fingerprinting and deduplication

The backend computes the canonical fingerprint. The client does not choose it.

The fingerprint is derived from stable normalized failure identity, initially:

- schema version;
- report type;
- component;
- failure stage;
- error code;
- normalized error after deterministic normalization.

Machine/version-specific values such as kernel, GPU family, Awtarchy version, and Hyprland version are not part of the core fingerprint unless later evidence shows they are necessary to distinguish unrelated failures.

This prevents the same bug on different machines/releases from generating separate issues.

For an existing fingerprint, D1 increments `occurrence_count` and updates `last_seen`/`last_version`. It does not create another GitHub issue.

For a new valid fingerprint, the backend creates one GitHub issue, then stores its issue number and URL in D1.

## D1 schema

The existing database schema is represented in source control by `services/report-service/migrations/0001_initial.sql`:

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

Version 1 stores aggregate signature state, not a permanent raw-report history.

## GitHub authentication

The Worker authenticates as the GitHub App, not as the user.

Flow:

1. Worker signs a short-lived GitHub App JWT using `GITHUB_APP_PRIVATE_KEY` and `GITHUB_APP_ID`.
2. Worker exchanges that JWT for an installation access token using `GITHUB_INSTALLATION_ID`.
3. Worker uses the short-lived installation token to create/update issues in `GITHUB_OWNER/GITHUB_REPO`.

The private key is never returned, logged, stored in D1, or sent to an Awtarchy client.

## GitHub issue behavior

New failure issues use backend-generated content, for example:

```text
Automatic failure report: Quickshell restart did not become ready
```

The issue body clearly states that it was created by the anonymous Awtarchy failure-reporting system and includes only sanitized structured diagnostics.

Duplicate reports do not create duplicate issues.

Version 1 records duplicate occurrence counts in D1. GitHub issue comments/updates should be conservative. A later implementation may update the issue only at useful thresholds such as 5, 10, 25, and 50 occurrences.

The report bot has no repository-content permission and cannot fix the issue automatically.

## Controlled end-to-end test

A controlled test report must exercise the real path:

```text
Awtarchy/client test
  -> Cloudflare Worker
  -> D1
  -> GitHub App
  -> dillacorn/awtarchy issue
```

The test uses a fixed, unmistakable signature and produces one issue titled approximately:

```text
[TEST] Awtarchy anonymous crash reporting
```

Repeated runs must deduplicate against the same D1 fingerprint instead of producing new issues.

The test issue may be closed manually after validation.

The first implementation must not enable production failure submission until this end-to-end test succeeds.

## Client-side pending report model

Awtarchy stores prepared reports under user state, not cache, because a pending report must survive logout/reboot.

Proposed location:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy/reports/
```

A pending report contains only the already-sanitized structured payload. Raw logs remain in their existing locations and are not automatically transmitted.

Report files use restrictive permissions (`umask 077`).

After successful submission or explicit rejection, the corresponding pending report is removed or marked resolved so the user is not prompted repeatedly for the same event.

## User notification

Version 1 prioritizes reliability over a complicated UI.

Notification order:

1. If Quickshell is healthy, surface an Awtarchy failure-report prompt through the existing shell/UI integration.
2. If the shell is unavailable, preserve the pending report and show the prompt the next time the `awtarchy` maintenance command is opened.
3. Do not automatically spawn terminals during a broken session merely to ask for submission consent.

The report can be reviewed as plain structured text before submission.

## Initial client failure hooks

### Awtarchy maintenance/update runtime

Capture a pending report only when an Awtarchy-owned operation reaches a known failure path with enough structured context to classify the problem.

Do not turn every non-zero external command into an anonymous report.

### Quickshell manager

Candidate version-1 report point:

- `start_shell` exhausts its readiness window and returns `quickshell_not_ready`.

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
- bounded strings and context;
- server-generated fingerprints;
- D1 deduplication;
- fixed target repository;
- server-generated issue title/body;
- no arbitrary Markdown supplied by clients;
- no client control over GitHub issue numbers/actions;
- Cloudflare-side request/rate protections where practical;
- backend refuses unsupported/future schema versions;
- conservative GitHub issue creation behavior.

An embedded client API secret is explicitly not used because Awtarchy is open source and any shipped secret would be public.

If abuse appears in practice, Cloudflare rate limits/WAF rules or stronger server-side throttling can be added without changing the privacy model.

## Error handling

Report submission must never interfere with recovery or normal Awtarchy operation.

If the Worker is unavailable, GitHub authentication fails, D1 fails, or the network is offline:

- the original Awtarchy operation remains the primary result;
- the pending report remains local;
- Awtarchy reports that submission failed and can be retried later;
- no retry loop runs indefinitely.

The Worker must return structured non-secret errors and must never include GitHub credentials, JWTs, installation tokens, stack traces containing secrets, or raw request internals.

## Testing

Backend tests should cover:

- `/health` success;
- malformed JSON rejection;
- wrong content type;
- unsupported schema version;
- unknown field rejection;
- overlong/oversized values;
- deterministic fingerprinting;
- new-signature insertion;
- duplicate increment without issue duplication;
- GitHub API failure leaves a recoverable database state;
- GitHub issue title/body cannot be controlled by client input;
- secret values never appear in responses/logging fixtures.

Client tests should cover:

- failure hooks create sanitized pending reports;
- successful recovery does not create a report;
- pending report survives until action;
- review does not transmit;
- reject does not transmit;
- send invokes only the configured reporting endpoint;
- failed submission retains the pending report;
- successful submission resolves it;
- known sensitive strings are removed/rejected before payload creation.

Existing `tests/test-troubleshoot-command.sh`, Quickshell process/recovery tests, updater tests, and security-boundary tests remain regression coverage and should be extended rather than bypassed.

## CI

Awtarchy CI should validate the report-service source and migrations alongside existing validation.

The report-service must be testable without real Cloudflare or GitHub credentials. Production GitHub issue creation is validated separately through the controlled test issue.

No production private keys or installation tokens are stored as GitHub repository secrets solely to run unit tests.

## Documentation changes

Before release, update:

- `AGENTS.md` with the new report-service architecture and privacy boundary;
- `README.md` or a focused privacy/reporting document describing that local capture is default but submission requires explicit approval;
- report-service README with Cloudflare/D1 deployment requirements;
- current statement that Awtarchy does not collect user data so it accurately distinguishes local diagnostics from user-approved anonymous submission.

## Non-goals for version 1

- silent telemetry;
- automatic report submission without user approval;
- automatic code fixes;
- repository write access for the report bot;
- arbitrary bug reports entered by users;
- arbitrary attachments/raw logs;
- full-system crash monitoring;
- unique machine tracking;
- analytics dashboards;
- automatic GitHub issue closure;
- paid third-party crash-reporting service dependency.

## Success criteria

Version 1 is successful when:

1. a controlled report from an Awtarchy machine reaches the real Cloudflare Worker;
2. the Worker validates and stores a single fingerprint in D1;
3. the Awtarchy Report Bot creates exactly one `[TEST]` issue in `dillacorn/awtarchy`;
4. repeating the same test does not create another issue;
5. no GitHub credential exists on the client or in repository source;
6. production report hooks remain user-approved and scoped only to defined Awtarchy failures;
7. existing Awtarchy tests remain passing.
