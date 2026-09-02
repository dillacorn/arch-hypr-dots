# AurGuard Shipping Security Design

Date: 2026-09-02
Branch: `feature/aur-scan-integration`
PR: #121

## Goal

Make AurGuard safe and practical enough to ship by fixing the three problems exposed by real-machine testing:

1. `aur-scan` heuristic severities currently act as automatic malware verdicts, which incorrectly blocks legitimate packages such as `google-chrome`, `visual-studio-code-bin`, and `brave-bin`.
2. Awtarchy's immutable-source verifier rejects legitimate chained integrity schemes such as Spotify's signed repository metadata flow.
3. Existing machines keep the AurGuard functions embedded in the `.bashrc` version they last installed, so security fixes do not propagate until the user manually updates Awtarchy.

The design must preserve Awtarchy's distinct protections: emergency blocklist, malware campaign lists, exact AUR checkout validation, maintainer/source identity review, recursive AUR dependency verification, checksum/PGP verification, clean/disposable build roots, exact commit rechecks, artifact inspection, and exact local artifact installation.

## Non-goals

- Do not replace Awtarchy's build/install pipeline with `aur-scan install`.
- Do not add package-name allowlists for Chrome, Brave, VS Code, Spotify, or any other legitimate package.
- Do not make HIGH/CRITICAL scanner findings disappear.
- Do not weaken known-malware, IOC, emergency-blocklist, source-origin, checksum, PGP, commit, or artifact failures into warnings.
- Do not download and source an arbitrary mutable remote `.bashrc`.
- Do not require the user to manually pull Awtarchy updates before every `aurverify` or `aurinstall` invocation.

## Selected architecture

### 1. Dedicated AurGuard runtime

Move the active AurGuard implementation into a dedicated managed runtime file, installed under Awtarchy's existing data directory, for example:

`~/.local/share/awtarchy/aurguard-runtime.sh`

The user's `.bashrc` keeps only thin public entrypoints/bootstrap plumbing for `aurcheck`, `aurverify`, `aurinstall`, and any compatibility alias that currently exposes AurGuard functionality. Those entrypoints dispatch into the cached runtime instead of permanently executing the copy that happened to be installed with the current `.bashrc`.

This avoids auto-replacing unrelated `.bashrc` content and gives the security subsystem its own update lifecycle.

### 2. Runtime refresh model

AurGuard uses a cached exact-commit runtime rather than sourcing mutable `main` directly.

On invocation:

1. Resolve Awtarchy `main` through GitHub's API to an exact 40-character commit SHA.
2. Read cached AurGuard metadata containing at minimum the cached commit and successful-refresh timestamp.
3. If the cache is present and younger than 24 hours, use it immediately with no network request beyond what the requested AUR operation itself needs.
4. If the cache is missing or stale, fetch `aurguard-runtime.sh` using the resolved exact commit, never an unpinned branch URL.
5. Validate the downloaded file before activation:
   - regular file, not symlink;
   - non-empty and below a conservative size limit;
   - Bash syntax passes with `bash -n`;
   - contains a fixed runtime identity/version marker and required dispatcher function;
   - resolved commit still matches the commit used for the download before activation.
6. Write to a temporary file in the same directory and atomically `mv` it into place.
7. Update metadata only after successful validation and activation.
8. Execute the requested AurGuard command from that exact cached runtime.

A refresh failure must never replace the last-known-good runtime. If a validated cache already exists, continue with that cache and print a concise warning that the refresh failed. If there is no validated cache, fail closed rather than executing partial or unverified downloaded code.

A forced-refresh entrypoint should exist for testing/recovery, for example `aurguard refresh`, but normal users should not need it.

Git-testing mode must stay reproducible: when Awtarchy is explicitly installed from a branch + exact commit for testing, the AurGuard runtime must resolve from that same testing commit instead of silently switching to `main`. This is required so a command such as:

`awtarchy git update --branch feature/aur-scan-integration --commit <sha>`

actually tests the AurGuard code at `<sha>`.

After the feature is merged and the user returns to normal stable/main state, the normal 24-hour security-runtime refresh policy applies automatically.

### 3. `aur-scan` becomes structured evidence, not a verdict oracle

Run the exact fetched AUR checkout through:

`aur-scan scan <checkout> --format json`

Do not pass `--fail-on` in Awtarchy's integration.

Reason: upstream documents severity gates as policy choices, and real-machine tests demonstrated legitimate HIGH/CRITICAL findings. Examples include a HIGH cron-persistence finding on a line that removes Chrome cron files and CRITICAL SUID findings on Chromium/Electron sandbox packaging.

Operational behavior:

- If `aur-scan` cannot execute, times out, crashes, or returns malformed/unparseable JSON, AurGuard fails closed.
- If JSON is valid, parse every finding by `id`, `severity`, `category`, title, location, snippet, and recommendation.
- Preserve the scanner's original human-readable evidence in Awtarchy's output, but let Awtarchy decide how the finding affects the transaction.

Finding policy:

- LOW/INFO: visible advisory; do not block.
- MEDIUM: visible context warning; do not block by severity alone.
- HIGH/CRITICAL: mark the package `REVIEW REQUIRED`; do not call it malicious and do not fail solely because of severity.
- Known Awtarchy IOC, emergency-blocklist, malware-campaign, identity, integrity, exact-commit, or artifact failures remain hard blocks independent of `aur-scan` severity.

For `aurverify`:

- Continue the remaining non-executing verification layers after HIGH/CRITICAL scanner findings.
- Final success state must clearly distinguish a clean scan from a review-required scan, for example:
  - `PASSED` when no HIGH/CRITICAL scanner review remains and all Awtarchy checks pass.
  - `REVIEW REQUIRED` when all hard security checks pass but `aur-scan` reported HIGH/CRITICAL heuristic findings.
- The requested package remains uninstalled.

For `aurinstall`:

- Complete all verification layers first.
- If HIGH/CRITICAL scanner findings remain and no hard block fired, require one explicit interactive acknowledgement immediately before build/install.
- Show finding IDs, severity, title, location/snippet, and the rest of Awtarchy's verification result before asking.
- A noninteractive/no-TTY transaction must fail closed rather than silently overriding review.
- The acknowledgement is package/commit-specific for the current transaction only; do not create a permanent allowlist.

This preserves the scanner's value while preventing static-analysis false positives from becoming automatic package bans.

### 4. Chained integrity verification

The current `_aur_guard_validate_skipped_integrity` model accepts direct strong checksums, exact VCS commits, content-addressed sources, recognized GitHub release digests, or a direct detached PGP signature relationship. It rejects a remote `SKIP` source if that individual source is not directly protected.

That is too narrow for legitimate repository metadata chains where:

1. a metadata document is covered by a pinned PGP signature;
2. the signed metadata contains a cryptographic digest for a second metadata document or payload;
3. the PKGBUILD verifies that digest before consuming the downstream file.

Spotify is the current real-world example, but the implementation must be generic and evidence-based, not `pkgbase == spotify`.

Add a narrowly scoped chained-integrity verifier that runs before declaring a `SKIP` remote source unverified.

A skipped remote source may be accepted through a chain only when AurGuard can prove all of the following from the exact fetched PKGBUILD and downloaded files:

- the trust root is a detached signature whose signing key is pinned by a full fingerprint in `validpgpkeys`;
- `makepkg --verifysource` successfully validates that signature in Awtarchy's sandbox;
- the signed metadata file is the exact file consumed by the PKGBUILD;
- the PKGBUILD obtains a strong digest (SHA-256 or stronger, or BLAKE2) for the skipped source from that authenticated metadata, directly or through another authenticated metadata file;
- the PKGBUILD actually compares the calculated digest of the downloaded skipped source to the authenticated expected digest and fails on mismatch;
- there is no command substitution/eval/network fetch in the integrity proof path that obtains an unauthenticated expected digest at build time;
- all files participating in the proof remain unchanged after source verification and before build.

Implementation should recognize a small set of auditable shell verification primitives rather than attempting general Bash theorem proving. At minimum support the concrete signed Release -> Packages digest -> package digest pattern exposed by Spotify's current PKGBUILD. If the verifier cannot establish the chain mechanically, keep the existing hard failure.

The verifier should print the proof it accepted, for example:

`AUR Verify: verified <file> through pinned PGP-signed metadata chain: Release -> Packages -> payload SHA256.`

No package-name exception is permitted.

### 5. Existing Awtarchy protections remain authoritative

The following remain hard failures and are not overridden by scanner review acknowledgement:

- emergency blocklist;
- confirmed malware campaign/package-list matches according to existing policy;
- malformed/escaping/special-file AUR checkouts;
- PKGBUILD/.SRCINFO mismatch;
- maintainer/package identity violations;
- unresolved or ambiguous required dependencies;
- untrusted source-integrity state for which no direct or chained proof succeeds;
- failed checksum or PGP verification;
- changed AUR commit or changed tracked files after verification;
- source snapshot changes;
- clean-root build failures;
- post-build artifact inspection failures;
- package metadata identity/conflict failures that currently require explicit review.

`aur-scan` supplements these layers; it does not replace them.

## Alternatives rejected

### Auto-update the whole `.bashrc`

Rejected because AurGuard security refreshes should not overwrite unrelated user shell configuration or require opening a new shell merely to receive current security logic.

### Fetch and source `main/bashrc` or `main/aurguard-runtime.sh` directly on every command

Rejected because it executes mutable branch state, adds a GitHub request to every command, creates avoidable availability dependency, and gives no atomic last-known-good fallback.

### Keep `--fail-on critical`

Rejected because real-machine testing already found legitimate CRITICAL Chromium/Electron sandbox findings. Changing the threshold from HIGH to CRITICAL reduces false positives but does not solve the policy error.

### Per-package or per-rule permanent allowlist

Rejected because it creates maintenance burden and can hide a future malicious change to a previously legitimate package. Review must bind to the exact current transaction/commit.

### Use `aur-scan install`

Rejected because Awtarchy already has stronger/different build boundaries, including its disposable clean-root flow, commit rechecks, artifact inspection, dependency behavior, and exact local artifact installation. Upstream also documents `aur-scan install` as not covering all helper/chroot features.

## State and cache layout

Recommended locations:

- runtime: `${XDG_DATA_HOME:-$HOME/.local/share}/awtarchy/aurguard-runtime.sh`
- metadata: `${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy/aurguard-runtime`
- refresh lock: `${XDG_RUNTIME_DIR:-/tmp}/awtarchy-aurguard-${UID}.lock` or another safe user-owned lock location

Metadata fields should be simple validated key/value data, for example:

- `revision=<40-hex-sha>`
- `ref=main` or the active Git-testing ref
- `refreshed_at=<unix-seconds>`
- `runtime_sha256=<64-hex>`

Never source metadata as shell code.

Concurrent AurGuard commands must serialize refresh with `flock`; after acquiring the lock, re-check freshness because another process may already have refreshed the runtime.

## Error handling

- Missing `aur-scanner`: retain current pinned-key self-healing bootstrap.
- Scanner process failure or malformed JSON: hard failure.
- Scanner HIGH/CRITICAL: review state, not automatic malware failure.
- Runtime refresh network/API failure with valid cached runtime: warn and continue with cache.
- Runtime refresh failure without a validated cache: hard failure.
- Runtime syntax/identity/hash/commit mismatch: reject candidate; retain cache if available.
- Chained-integrity proof incomplete: existing immutable-source hard failure.
- User declines HIGH/CRITICAL review during `aurinstall`: abort before build/install.

## Testing strategy

Use TDD and preserve the real-machine packages as regression fixtures/expected behaviors where practical without depending on live AUR state in CI.

### Scanner policy tests

Create fake `aur-scan` JSON fixtures for:

- no findings -> normal pass;
- LOW -> advisory pass;
- MEDIUM -> context-warning pass;
- HIGH -> review-required verification but not automatic failure;
- CRITICAL -> review-required verification but not automatic failure;
- malformed JSON -> hard failure;
- scanner nonzero operational failure -> hard failure.

Pin regression examples matching the observed false-positive shapes:

- `PERSIST-003` on a command removing `cron.daily` content;
- `PRIV-002` on `chrome-sandbox` SUID packaging.

Tests must prove those findings remain visible and trigger review, not silent ignore.

### `aurinstall` review tests

- HIGH/CRITICAL + all other checks passing + user accepts -> build may proceed.
- user declines -> no build.
- no TTY -> fail closed.
- emergency/malware/integrity hard failure -> acknowledgement is never offered.
- review acknowledgement is not persisted across transactions.

### Chained-integrity tests

Fixture a minimal signed-metadata pattern equivalent to:

`Release.sig -> Release -> Packages -> package payload digest`

Test:

- valid pinned key + valid signature + correct nested digests -> accepted;
- wrong fingerprint -> rejected;
- invalid signature -> rejected;
- signed metadata digest mismatch -> rejected;
- downstream payload digest mismatch -> rejected;
- expected digest sourced from unauthenticated network data -> rejected;
- missing proof step -> rejected.

### Runtime refresh tests

- missing cache -> resolve exact commit, download, validate, atomically install, dispatch;
- fresh cache (<24h) -> no refresh;
- stale cache -> refresh;
- failed refresh + valid cache -> warning + cached dispatch;
- failed refresh + no cache -> fail closed;
- invalid candidate syntax -> old cache retained;
- invalid candidate identity marker -> old cache retained;
- branch head changes during refresh -> reject/retry rather than activate mixed state;
- concurrent invocations -> one refresh, both use same validated runtime;
- Git-testing mode -> exact testing commit runtime, never `main`;
- normal mode after merge -> `main` refresh policy.

### Existing validation

At minimum:

- `bash -n` for every changed shell file;
- ShellCheck for every changed shell file;
- existing AurGuard security-boundary regressions;
- existing self-heal/bootstrap regressions;
- `git diff --check`;
- repository-wide `Validate Awtarchy` workflow;
- focused read-only AurGuard workflow.

## Real-machine acceptance matrix

Before PR #121 is considered merge-ready, retest:

- `aurverify hyprmoncfg-bin` -> passes; LOW provides warning is visible.
- `aurverify google-chrome` -> HIGH scanner finding is visible, but verification continues and final result is review-required rather than false malware failure if all Awtarchy hard checks pass.
- `aurverify visual-studio-code-bin` -> CRITICAL scanner finding is visible, verification continues, final review-required if all hard checks pass.
- `aurverify brave-bin` -> same review-required behavior.
- `aurverify spotify` -> signed metadata chain is mechanically verified; no blanket SKIP-integrity rejection.
- `aurverify paru` -> clean pass.
- `aurverify mpvpaper` -> clean pass.
- `aurverify qimgv` -> LOW epoch advisory, otherwise pass.
- `aurverify alacritty-graphics` -> LOW provides advisory, otherwise pass.
- `aurverify obs-pipewire-audio-capture-bin` -> LOW provides advisory, otherwise pass.
- `aurverify smtty` -> clean pass.

Then test at least one real `aurinstall` with HIGH/CRITICAL scanner review to prove explicit acknowledgement happens before any build/install and binds only to the exact current transaction.

## Shipping criteria

PR #121 is merge-ready only when:

1. all CI/security regressions pass on one exact final head;
2. the focused workflow is read-only;
3. no temporary write-capable workflow remains;
4. real-machine acceptance matrix above behaves as designed;
5. existing hard security layers still fail closed;
6. an existing installed Awtarchy machine can receive a newer AurGuard runtime without manually running an Awtarchy update;
7. Git-testing remains exact-commit reproducible;
8. PR body documents the final policy accurately.
