# Anonymous Failure Reporting

Awtarchy's failure-reporting path is intentionally narrow and user-approved.

## Runtime flow

```text
known Awtarchy failure
  -> config/hypr/scripts/awtarchy_report_failure.sh
  -> sanitized pending JSON in XDG state
  -> local path/schema revalidation
  -> user Send / Review / Don't send
  -> https://awtarchy-reports.dillacorn.workers.dev/v1/report
  -> strict Worker validation
  -> client+signature Cloudflare rate limit
  -> signature-wide Cloudflare rate limit
  -> server-generated SHA-256 failure fingerprint
  -> D1 aggregate/deduplication
  -> Awtarchy Report Bot GitHub issue
```

Noninteractive failure paths queue the report but never invent consent or spawn a terminal. The report remains local until a user explicitly submits or discards it. Once Quickshell becomes healthy again, Awtarchy may notify the user that sanitized reports are waiting. If Quickshell remains unavailable, opening the interactive `awtarchy` maintenance menu also surfaces any valid pending reports.

## Security invariants

- Treat `/v1/report` as hostile public input.
- Never add a production client secret; Awtarchy is open source.
- Never accept caller-controlled GitHub title/body/labels/repository/action/fingerprint.
- Never add raw logs or arbitrary strings to the report schema merely because they are useful for debugging.
- Never add persistent install, machine, or user identifiers without a new explicit privacy/design decision.
- Restrict client send/review/discard operations to known Awtarchy pending-report files and revalidate a report locally before transmission.
- Keep both Worker rate limiters ahead of D1/GitHub reporting work. The client limiter may use Cloudflare's transport IP only for its transient counter; never persist that value or add it to report/D1/GitHub content.
- Reporting failure must never change the original operation's exit code or recovery behavior.
- Keep the GitHub App limited to Issues read/write plus required Metadata read-only.
- Keep the Worker private key and maintainer test token in Cloudflare secrets only.
- Keep D1 aggregate-only unless a future design explicitly justifies additional retention.

## Reported failures

Version 1 recognizes these fixed failure signatures:

```text
quickshell | start                | quickshell_not_ready
quickshell | restart              | quickshell_not_ready
quickshell | restart_after_update | quickshell_not_ready
resume_recovery | start            | quickshell_start_failed
resume_recovery | restart          | quickshell_restart_failed
resume_recovery | final_validation | expected_bars_missing
```

A post-update Quickshell restart is explicitly marked `restart_after_update` by the Awtarchy maintenance command before invoking the Quickshell manager. Resume recovery suppresses the manager's generic report and emits the more specific recovery failure instead, preventing duplicate signatures for one failure.

## Adding a new reportable failure

A new failure class is incomplete unless the same `(component, failure_stage, error_code)` triple is added to both:

1. the client helper allowlist; and
2. the Worker canonical registry with a server-owned description.

Add focused tests on both sides. If an updater/recovery caller needs a distinct stage, add a caller-to-manager wiring regression test too. The fingerprint must remain server-generated from stable enum-like identifiers, not diagnostic version strings or free-form error text.

## Abuse protection

The production route uses two Cloudflare Worker Rate Limiting bindings after validation and before D1/GitHub reporting work.

`REPORT_CLIENT_RATE_LIMITER` allows three calls per 60 seconds for each Cloudflare client-IP plus canonical failure-signature pair in a Cloudflare location. `REPORT_SIGNATURE_RATE_LIMITER` then allows 20 calls per 60 seconds for each canonical failure signature in that location. The first boundary prevents one client from trivially monopolizing the second; the second still caps aggregate backend work if abuse is distributed.

The client IP comes from Cloudflare's `CF-Connecting-IP` transport header and is used only for the transient client-rate counter. It is not added to the report payload, D1 state, GitHub issue, or a persistent Awtarchy identifier.

Cloudflare's native Worker limiter is location-local, permissive, and eventually consistent, so these are best-effort abuse controls rather than strict global request caps. If either binding or the Cloudflare client-IP header is unavailable, `/v1/report` fails closed with `503`. If either limiter rejects a request it returns `429`. In either case, the client keeps the pending report locally rather than treating it as successfully submitted.

## Deployment

The Worker source lives under `services/report-service/`. The existing production D1 database predates source-controlled migrations; do not apply `0001_initial.sql` to it merely to deploy code.

Use Node 22+ for current Wrangler releases:

```bash
cd services/report-service
npm test
npx wrangler@latest deploy
```

If Wrangler reports dashboard/local configuration differences, review them before accepting. The deployment must include the existing D1 binding plus both source-controlled rate-limit bindings. Secrets must remain dashboard-managed and must never be committed.

CI runs a Wrangler deployment dry run on Node 22 to parse the source-controlled Worker configuration before a live deploy.

## Test endpoint

`POST /v1/test` is a separate maintainer-only infrastructure test protected by `TEST_AUTH_TOKEN`. It is not used by Awtarchy clients. Remove the Cloudflare secret when that endpoint is no longer needed.
