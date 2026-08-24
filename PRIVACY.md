# Privacy

Awtarchy is primarily a local open-source utility. It includes an optional failure-reporting path for a small set of recognized Awtarchy/Quickshell failures.

## Failure reports are user-approved

Awtarchy does not silently submit diagnostic reports.

When Awtarchy recognizes a supported failure, it may prepare a sanitized report locally and ask whether to send it. The available choices are to send the report, review it first, or not send it.

If no interactive terminal is available, the sanitized report may remain pending locally for later review. Awtarchy does not automatically open a terminal merely to request consent.

## What a report can contain

Version 1 uses a strict structured schema. A submitted report can contain:

- Awtarchy report schema version;
- report type;
- Awtarchy component, failure stage, and fixed error code;
- Awtarchy configuration version;
- Awtarchy maintenance-command revision, or `unknown`;
- Hyprland version;
- Quickshell version;
- kernel version;
- broad GPU family: AMD, Intel, NVIDIA, Other, or Unknown;
- fixed boolean recovery state for supported recovery failures.

The report service validates these fields again before accepting a report. Clients cannot choose the GitHub issue title, issue body, repository, fingerprint, or GitHub action.

## What Awtarchy does not include

Failure-report payloads do not include:

- username;
- hostname;
- home-directory path;
- IP address as a report field;
- MAC address;
- Wi-Fi SSID;
- WireGuard or private VPN details;
- environment secrets or tokens;
- shell command history;
- clipboard contents;
- arbitrary window titles;
- arbitrary file contents;
- raw troubleshooting logs;
- persistent machine, installation, or user identifiers.

The reporting helper derives only the allowlisted structured fields above. Raw `awtarchy troubleshoot` output remains local unless a user chooses to share it separately.

## Local pending reports

Pending reports are stored under:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy/reports/
```

The report directory is restricted to the user and pending report files are written with mode `0600`.

The helper's send, review, and discard operations are restricted to Awtarchy's known pending-report filenames inside that directory. Before a pending report can be sent, the helper locally revalidates its size, allowed fields, field formats, recognized failure class, and filename-to-failure match. An arbitrary local file or a tampered report with unknown fields is rejected before any network request is made.

A pending report is removed after a successful submission or when the user explicitly declines/discards it. A failed network submission leaves the sanitized report local so the user can retry later.

## Network and hosting

Submitted reports are sent over HTTPS to Awtarchy's Cloudflare Worker at:

```text
https://awtarchy-reports.dillacorn.workers.dev/v1/report
```

The Awtarchy report payload does not contain an IP-address field or a persistent client identifier. However, Cloudflare necessarily processes network connection metadata, including source IP information, to receive and protect HTTP requests. Cloudflare may retain infrastructure or security logs according to its service behavior and the project's Cloudflare account settings.

The public report route uses two Cloudflare Worker Rate Limiting bindings before any D1/GitHub reporting work. The first combines Cloudflare's `CF-Connecting-IP` transport header with the validated failure signature to keep one client from consuming the entire signature-wide allowance. The second applies a higher ceiling to the validated failure signature across clients in the same Cloudflare location.

The source IP is used transiently only for the first Cloudflare rate-limit counter. Awtarchy does not add it to the report payload, D1 signature state, GitHub issue content, or a persistent machine/install/user identifier. If either limiter rejects the request, the Worker returns `429` before D1/GitHub reporting work and the local sanitized report remains available for retry.

Cloudflare documents Worker rate-limit counters as location-local, permissive, and eventually consistent. They are abuse controls, not exact accounting. D1 occurrence counts likewise represent accepted report events, not a count of unique affected users.

For these reasons, Awtarchy describes the report payload as sanitized and without direct or persistent identity fields, and does not claim absolute network-layer anonymity.

## GitHub issues

The Worker validates accepted reports, creates a server-controlled bug fingerprint, and stores aggregate signature state in Cloudflare D1. The fingerprint identifies a failure signature, not a user or machine.

For a new recognized signature, the dedicated Awtarchy Report Bot may create a public issue in `dillacorn/awtarchy`. The GitHub issue contains only server-generated text derived from the validated structured report.

Repeated reports with the same signature are deduplicated in D1 rather than creating a new GitHub issue for every user.

The GitHub App is intentionally limited to Issues read/write and GitHub's required Metadata read-only permission. It has no repository Contents, Pull requests, Actions, Releases, or Administration permission.

## No automatic fixes

The reporting service is observational. It cannot modify Awtarchy source code, create branches, open or merge pull requests, publish releases, or make changes on a user's computer.

## Disabling submission

Choosing **Don't send** discards that pending report without transmitting it. A report can also simply be left pending locally. Version 1 does not include an automatic-send mode.
