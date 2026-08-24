# Anonymous Failure Reporting

Awtarchy's failure-reporting path is intentionally narrow and user-approved.

## Runtime flow

```text
known Awtarchy failure
  -> config/hypr/scripts/awtarchy_report_failure.sh
  -> sanitized pending JSON in XDG state
  -> user Send / Review / Don't send
  -> https://awtarchy-reports.dillacorn.workers.dev/v1/report
  -> strict Worker validation
  -> server-generated SHA-256 failure fingerprint
  -> D1 aggregate/deduplication
  -> Awtarchy Report Bot GitHub issue
```

Noninteractive failure paths queue the report but never invent consent or spawn a terminal. The report remains local until a user explicitly submits or discards it.

## Security invariants

- Treat `/v1/report` as hostile public input.
- Never add a production client secret; Awtarchy is open source.
- Never accept caller-controlled GitHub title/body/labels/repository/action/fingerprint.
- Never add raw logs or arbitrary strings to the report schema merely because they are useful for debugging.
- Never add persistent install, machine, or user identifiers without a new explicit privacy/design decision.
- Reporting failure must never change the original operation's exit code or recovery behavior.
- Keep the GitHub App limited to Issues read/write plus required Metadata read-only.
- Keep the Worker private key and maintainer test token in Cloudflare secrets only.
- Keep D1 aggregate-only unless a future design explicitly justifies additional retention.

## Adding a new reportable failure

A new failure class is incomplete unless the same `(component, failure_stage, error_code)` triple is added to both:

1. the client helper allowlist; and
2. the Worker canonical registry with a server-owned description.

Add focused tests on both sides. The fingerprint must remain server-generated from stable enum-like identifiers, not diagnostic version strings or free-form error text.

## Deployment

The Worker source lives under `services/report-service/`. The existing production D1 database predates source-controlled migrations; do not apply `0001_initial.sql` to it merely to deploy code.

Use Node 22+ for current Wrangler releases:

```bash
cd services/report-service
npm test
npx wrangler@latest deploy
```

If Wrangler reports dashboard/local configuration differences, review them before accepting. Secrets must remain dashboard-managed and must never be committed.

## Test endpoint

`POST /v1/test` is a separate maintainer-only infrastructure test protected by `TEST_AUTH_TOKEN`. It is not used by Awtarchy clients. Remove the Cloudflare secret when that endpoint is no longer needed.
