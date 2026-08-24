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

A pending report is removed after a successful submission or when the user explicitly declines/discards it. A failed network submission leaves the sanitized report local so the user can retry later.

## Network and hosting

Submitted reports are sent over HTTPS to Awtarchy's Cloudflare Worker at:

```text
https://awtarchy-reports.dillacorn.workers.dev/v1/report
```

The Awtarchy report payload does not contain an IP-address field or a persistent client identifier. However, Cloudflare necessarily processes network connection metadata, including source IP information, to receive and protect HTTP requests. Cloudflare may retain infrastructure or security logs according to its service behavior and the project's Cloudflare account settings.

For that reason, Awtarchy describes the report payload as identity-free/sanitized and does not claim absolute network-layer anonymity.

## GitHub issues

The Worker validates accepted reports, creates a server-controlled bug fingerprint, and stores aggregate signature state in Cloudflare D1. The fingerprint identifies a failure signature, not a user or machine.

For a new recognized signature, the dedicated Awtarchy Report Bot may create a public issue in `dillacorn/awtarchy`. The GitHub issue contains only server-generated text derived from the validated structured report.

Repeated reports with the same signature are deduplicated in D1 rather than creating a new GitHub issue for every user.

The GitHub App is intentionally limited to Issues read/write and GitHub's required Metadata read-only permission. It has no repository Contents, Pull requests, Actions, Releases, or Administration permission.

## No automatic fixes

The reporting service is observational. It cannot modify Awtarchy source code, create branches, open or merge pull requests, publish releases, or make changes on a user's computer.

## Disabling submission

Choosing **Don't send** discards that pending report without transmitting it. A report can also simply be left pending locally. Version 1 does not include an automatic-send mode.
