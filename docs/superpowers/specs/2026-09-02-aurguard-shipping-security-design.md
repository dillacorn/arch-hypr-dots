# AurGuard Shipping Security Design

Date: 2026-09-02
Branch: `feature/aur-scan-integration`
PR: #121

## Goal

Make AurGuard safe and practical enough to ship by fixing the three problems exposed by real-machine testing:

1. `aur-scan` heuristic severities currently act as automatic malware verdicts, which incorrectly blocks legitimate packages such as `google-chrome`, `visual-studio-code-bin`, and `brave-bin`.
2. Awtarchy's immutable-source verifier rejects legitimate signed metadata schemes such as Spotify's PGP-authenticated Debian `Release` metadata protecting its `Packages` index.
3. Existing machines keep the AurGuard functions embedded in the `.bashrc` version they last installed, so security fixes do not propagate until the user manually updates Awtarchy.

The design must preserve Awtarchy's distinct protections: emergency blocklist, malware campaign/history evidence under its existing policy, exact AUR checkout validation, maintainer/source identity review, recursive AUR dependency verification, checksum/PGP verification, clean/disposable build roots, exact commit rechecks, artifact inspection, and exact local artifact installation.

## Non-goals

- Do not replace Awtarchy's build/install pipeline with `aur-scan install`.
- Do not add package-name allowlists for Chrome, Brave, VS Code, Spotify, or any other legitimate package.
- Do not make HIGH/CRITICAL scanner findings disappear.
- Do not weaken explicit hard-block/IOC, emergency-blocklist, source-origin, checksum, PGP, commit, or artifact failures into warnings.
- Do not silently change the current warning/review semantics of Awtarchy's historical malware campaign lists.
- Do not download and source an arbitrary mutable remote `.bashrc`.
- Do not require the user to manually pull Awtarchy updates before every `aurverify` or `aurinstall` invocation.

## Selected architecture

### 1. Dedicated AurGuard runtime

Move the active AurGuard implementation into a dedicated managed runtime file installed under Awtarchy's existing data directory:

`~/.local/share/awtarchy/aurguard-runtime.sh`

The user's `.bashrc` keeps only thin public entrypoints/bootstrap plumbing for `aurcheck`, `aurverify`, `aurinstall`, and any compatibility alias that currently exposes AurGuard functionality. Those entrypoints dispatch into the cached runtime instead of permanently executing the copy that happened to be installed with the current `.bashrc`.

This avoids auto-replacing unrelated `.bashrc` content and gives the security subsystem its own update lifecycle.

### 2. Runtime refresh model

AurGuard uses a cached exact-commit runtime rather than sourcing mutable `main` directly.

On invocation:

1. Determine the expected runtime target from local Awtarchy state without network access:
   - normal installed state: target ref is `main`;
   - active Git-testing state: target is the exact testing commit already recorded by Awtarchy.
2. Read cached AurGuard metadata containing the cached target, exact commit, runtime hash, and successful-refresh timestamp.
3. If the cached runtime validates, matches the expected local target, and is younger than 24 hours, use it immediately with no AurGuard refresh network request.
4. If the cache is missing, invalid, target-mismatched, or stale:
   - normal mode resolves `main` through GitHub's API to an exact 40-character commit SHA;
   - Git-testing mode uses the already-recorded exact testing commit and must not silently switch to `main`.
5. Fetch `aurguard-runtime.sh` using that exact commit, never an unpinned branch URL.
6. Validate the downloaded candidate before activation:
   - regular file, not symlink;
   - non-empty and below a conservative size limit;
   - SHA-256 recorded and later revalidated from metadata;
   - Bash syntax passes with `bash -n`;
   - contains a fixed runtime identity/version marker and required dispatcher function;
   - in normal mode, re-resolve `main` immediately before activation and require it to still equal the commit used for the download; if it moved, retry from the new exact head rather than activating mixed state.
7. Write to a temporary file in the same directory and atomically `mv` it into place.
8. Update metadata only after successful validation and activation.
9. Execute the requested AurGuard command from that exact cached runtime.

A refresh failure must never replace the last-known-good runtime. If a validated cache for the same expected target already exists, continue with that cache and print a concise warning that the refresh failed. If there is no validated cache for the expected target, fail closed rather than executing partial, mismatched, or unverified downloaded code.

A forced-refresh entrypoint should exist for testing/recovery, for example `aurguard refresh`, but normal users should not need it.

Git-testing mode must stay reproducible: a command such as:

`awtarchy git update --branch feature/aur-scan-integration --commit <sha>`

must cause AurGuard to execute the runtime from `<sha>`, not current `main`.

After the feature is merged and a machine returns to normal non-Git-testing state, the 24-hour `main` security-runtime refresh policy applies automatically.

### 3. `aur-scan` becomes structured evidence, not a verdict oracle

Run the exact fetched AUR checkout through:

`aur-scan scan <checkout> --format json`

Do not pass `--fail-on` in Awtarchy's integration.

Reason: upstream exposes severity gates as policy choices, and real-machine tests demonstrated legitimate HIGH/CRITICAL findings. Examples include a HIGH cron-persistence finding on a line that removes Chrome cron files and CRITICAL SUID findings on Chromium/Electron sandbox packaging.

Operational behavior:

- If `aur-scan` cannot execute, times out, crashes, returns nonzero without a valid result, or emits malformed/unparseable JSON, AurGuard fails closed.
- If JSON is valid, parse every finding by `id`, `severity`, `category`, title, location, snippet, and recommendation.
- Render equivalent human-readable evidence from that JSON so users still see the scanner's finding details while Awtarchy decides how the finding affects the transaction.

Finding policy:

- LOW/INFO: visible advisory; do not block.
- MEDIUM: visible context warning; do not block by severity alone.
- HIGH/CRITICAL: mark the package `REVIEW REQUIRED`; do not call it malicious and do not fail solely because of severity.
- Awtarchy's existing explicit hard-block/IOC, emergency-blocklist, identity, integrity, exact-commit, and artifact failures remain authoritative independent of `aur-scan` severity.
- Historical malware campaign/list evidence retains its existing Awtarchy warning/review semantics unless it already reaches an explicit hard-block boundary elsewhere.

For `aurverify`:

- Continue the remaining non-executing verification layers after HIGH/CRITICAL scanner findings.
- Final success state must clearly distinguish a clean scan from a review-required scan:
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

### 4. Signed metadata integrity verification

The current `_aur_guard_validate_skipped_integrity` model accepts direct strong checksums, exact VCS commits, content-addressed sources, recognized GitHub release digests, or a direct detached PGP signature relationship. It rejects a remote `SKIP` source if that individual source is not directly protected.

That is too narrow for a legitimate repository metadata model where a skipped index file is authenticated by a separately signed metadata document.

Spotify exposed the concrete first case: a PGP-authenticated Debian `Release` document contains the SHA-256 digest for the downloaded `Packages` index. Awtarchy currently rejects the `Packages` source before it can recognize that authenticated relationship.

Do not attempt to prove arbitrary Bash verification logic. Instead add a small, format-specific, independently verified metadata-chain layer.

First supported chain: Debian-style signed `Release` metadata.

A skipped remote file may be accepted through this path only when AurGuard independently proves all of the following:

1. The exact downloaded `Release` metadata has a detached signature source (`.gpg`, `.sig`, `.asc`, or the exact sidecar relationship already recognized by Awtarchy).
2. The signing key is pinned by a full fingerprint in `validpgpkeys`.
3. Awtarchy's existing sandboxed `makepkg --verifysource` succeeds, thereby authenticating the signed `Release` file with the pinned key.
4. The authenticated `Release` file contains a supported strong digest section for the skipped source. Initial implementation supports `SHA256` and may also accept stronger algorithms already implemented by Awtarchy.
5. The metadata entry's path/basename resolves unambiguously to the exact downloaded skipped source declared by `.SRCINFO`; aliases are handled explicitly and path traversal is rejected.
6. Awtarchy independently hashes the downloaded skipped source and requires an exact match to the digest from the authenticated `Release` metadata.
7. The signed metadata and skipped source remain unchanged after verification and before build under the existing tracked/source recheck boundaries.

If all conditions hold, the skipped index is treated as strongly authenticated even though its `.SRCINFO` checksum entry is `SKIP`.

If the skipped index then describes payload digests, those payloads still need to satisfy Awtarchy's existing direct checksum/content-addressed/release-digest rules unless a future explicitly implemented metadata format extends the chain. The first implementation does not broaden trust beyond the file actually authenticated by signed `Release` metadata.

Print the proof accepted, for example:

`AUR Verify: verified Packages through pinned PGP-signed Release metadata (SHA256).`

No package-name exception is permitted. If the exact metadata format cannot be parsed and proven mechanically, keep the existing immutable-source hard failure.

### 5. Existing Awtarchy protections remain authoritative

The following remain hard failures and are not overridden by scanner review acknowledgement:

- emergency blocklist and existing explicit hard-block/IOC boundaries;
- malformed/escaping/special-file AUR checkouts;
- PKGBUILD/.SRCINFO mismatch;
- maintainer/package identity violations that currently block;
- unresolved or ambiguous required dependencies;
- untrusted source-integrity state for which no direct or supported signed-metadata proof succeeds;
- failed checksum or PGP verification;
- changed AUR commit or changed tracked files after verification;
- source snapshot changes;
- clean-root build failures;
- post-build artifact inspection failures;
- package metadata identity/conflict failures that currently require explicit review.

Historical/campaign evidence retains its current Awtarchy semantics rather than being silently promoted or demoted by this work.

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
- refresh lock: a user-owned lock below `${XDG_RUNTIME_DIR}` when available, with a safe user-owned fallback under Awtarchy state when it is not

Metadata fields are validated data, never sourced shell code:

- `revision=<40-hex-sha>`
- `target=main` or `target=git:<40-hex-sha>`
- `refreshed_at=<unix-seconds>`
- `runtime_sha256=<64-hex>`

Concurrent AurGuard commands serialize refresh with `flock`; after acquiring the lock, re-check freshness because another process may already have refreshed the runtime.

## Error handling

- Missing `aur-scanner`: retain current pinned-key self-healing bootstrap.
- Scanner process failure or malformed JSON: hard failure.
- Scanner HIGH/CRITICAL: review state, not automatic malware failure.
- Runtime refresh network/API failure with valid same-target cache: warn and continue with cache.
- Runtime refresh failure without a validated same-target cache: hard failure.
- Runtime syntax/identity/hash/commit mismatch: reject candidate; retain same-target cache if available.
- Signed metadata proof incomplete or digest mismatch: existing immutable-source hard failure.
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
- scanner operational nonzero -> hard failure.

Pin regression examples matching the observed false-positive shapes:

- `PERSIST-003` on a command removing `cron.daily` content;
- `PRIV-002` on `chrome-sandbox` SUID packaging.

Tests must prove those findings remain visible and trigger review, not silent ignore.

### `aurinstall` review tests

- HIGH/CRITICAL + all other checks passing + user accepts -> build may proceed.
- user declines -> no build.
- no TTY -> fail closed.
- emergency/hard-block/integrity failure -> acknowledgement is never offered.
- review acknowledgement is not persisted across transactions.

### Signed metadata tests

Fixture a minimal Debian-style chain:

`Release signature -> Release SHA256 entry -> Packages`

Test:

- valid pinned key + valid signature + correct `Packages` digest -> accepted;
- wrong fingerprint -> rejected;
- invalid signature -> rejected;
- missing `SHA256` entry -> rejected;
- ambiguous/mismatched metadata filename -> rejected;
- `Packages` digest mismatch -> rejected;
- path traversal/unsafe metadata path -> rejected;
- unsupported metadata format -> remains rejected rather than guessed.

### Runtime refresh tests

- missing cache -> resolve exact target commit, download, validate, atomically install, dispatch;
- fresh same-target cache (<24h) -> no AurGuard refresh network request;
- stale cache -> refresh;
- failed refresh + valid same-target cache -> warning + cached dispatch;
- failed refresh + no same-target cache -> fail closed;
- invalid candidate syntax -> old cache retained;
- invalid candidate identity marker -> old cache retained;
- candidate hash mismatch -> old cache retained;
- normal `main` moves during refresh -> reject/retry rather than activate mixed state;
- concurrent invocations -> one refresh, both use same validated runtime;
- Git-testing mode -> exact testing commit runtime, never `main`;
- switching from Git-testing back to normal -> testing cache is not mistaken for the normal `main` target.

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
- `aurverify spotify` -> its skipped `Packages` index is mechanically authenticated through pinned PGP-signed `Release` metadata; no blanket SKIP-integrity rejection.
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
6. existing historical/campaign warning behavior has not been unintentionally changed;
7. an existing installed Awtarchy machine can receive a newer AurGuard runtime without manually running an Awtarchy update;
8. Git-testing remains exact-commit reproducible;
9. PR body documents the final policy accurately.
