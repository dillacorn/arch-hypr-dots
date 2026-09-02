# AurGuard Shipping Security Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PR #121 ship-safe by replacing blind aur-scan severity blocking with structured review, adding narrowly proven signed-metadata integrity chains, and giving AurGuard an exact-commit self-refresh path that does not require manual Awtarchy updates.

**Architecture:** Keep Awtarchy's existing AurGuard verification/build pipeline authoritative. Add structured scanner-result handling inside that pipeline, add one generic chained-integrity verifier before the current SKIP hard failure, and add a stable bootstrap dispatcher that caches an exact-commit AurGuard runtime for 24 hours while preserving Git-testing pinning. The emergency blocklist, identity checks, checksums/PGP, dependency recursion, clean-root build, commit rechecks, and artifact inspection remain hard boundaries.

**Tech Stack:** Bash, Python 3 for strict JSON/metadata parsing, jq where already required, GitHub REST/raw content, flock, GitHub Actions, ShellCheck.

**Spec:** `docs/superpowers/specs/2026-09-02-aurguard-shipping-security-design.md`

## Global Constraints

- Do not add package-name allowlists.
- Do not make HIGH/CRITICAL aur-scan findings disappear.
- Scanner execution failure or malformed JSON fails closed.
- Known hard Awtarchy failures stay hard failures.
- Runtime refresh uses an exact 40-hex commit and atomic activation; never source mutable `main` directly.
- Fresh runtime cache is usable for 24 hours without a refresh request.
- Git-testing must execute AurGuard from the exact testing commit.
- Refresh failure may use only a previously validated cache; no valid cache means fail closed.
- Existing campaign/history warning semantics are preserved.

---

### Task 1: Structured aur-scan review policy

**Files:**
- Modify: `bashrc` around `_aur_guard_scan_checkout_with_aur_scan`, verification state initialization, `aurverify`, and `aurinstall` review/build boundary.
- Create: `tests/test-aur-scan-review-policy.sh`
- Modify: `.github/workflows/apply-aur-scan-integration.yml`

**Interfaces:**
- Produces `_AUR_GUARD_SCAN_REVIEW_FINDINGS` as transaction-local structured review records.
- Produces `_aur_guard_has_scan_review()` and `_aur_guard_print_scan_review()`.
- `_aur_guard_scan_checkout_with_aur_scan <pkg> <pkgdir>` returns nonzero only for scanner operational/JSON failure, not for findings.
- `aurverify` returns status 2 for completed verification with unresolved HIGH/CRITICAL heuristic review, 0 for normal pass, 1 for hard failure.
- `aurinstall` requires exact-transaction interactive acknowledgement after all verification succeeds and before any build starts.

- [ ] **Step 1: Write the failing scanner-policy regression**

Create `tests/test-aur-scan-review-policy.sh` that sources a noninteractive fixture of `bashrc`, installs a fake `aur-scan`, and exercises these JSON payloads:

```json
{"package_name":"fixture","package_version":"1-1","findings":[],"scanned_files":["PKGBUILD"],"timestamp":"2026-09-02T00:00:00Z","scan_duration_ms":1}
```

```json
{"package_name":"fixture","package_version":"1-1","findings":[{"id":"PERSIST-003","severity":"high","category":"persistence","title":"Cron job creation","description":"Creating cron jobs for persistence","location":{"file":"PKGBUILD","line":72,"column":null,"snippet":"rm -r \"$pkgdir\"/etc/cron.daily/"},"recommendation":"Review cron behavior","cwe_id":null,"metadata":{}}],"scanned_files":["PKGBUILD"],"timestamp":"2026-09-02T00:00:00Z","scan_duration_ms":1}
```

```json
{"package_name":"fixture","package_version":"1-1","findings":[{"id":"PRIV-002","severity":"critical","category":"privilege_escalation","title":"SUID bit in package()","description":"Function package sets SUID bits","location":{"file":"PKGBUILD","line":34,"column":null,"snippet":"chmod 4755 chrome-sandbox"},"recommendation":"Review sandbox requirement","cwe_id":"CWE-732","metadata":{}}],"scanned_files":["PKGBUILD"],"timestamp":"2026-09-02T00:00:00Z","scan_duration_ms":1}
```

Assertions:
- fake scanner arguments are exactly `scan <pkgdir> --format json` with no `--fail-on`;
- clean/LOW/MEDIUM scans return success;
- HIGH/CRITICAL scans return success from the scan helper but make `_aur_guard_has_scan_review` true;
- review output includes finding id, severity, title, and snippet;
- malformed JSON and nonzero fake scanner exit both fail hard;
- review records are reset between verification transactions.

- [ ] **Step 2: Run the new regression and confirm RED**

Run in CI/local checkout:

```bash
bash tests/test-aur-scan-review-policy.sh
```

Expected failure: current implementation still invokes `--fail-on high` and has no review-state functions.

- [ ] **Step 3: Implement JSON scanner parsing**

Change the helper to write JSON to a transaction-local temporary file and run:

```bash
"$scanner" scan "$pkgdir" --format json >"$scan_json"
```

Parse with Python 3. Validate top-level object, `findings` array, recognized severities (`critical|high|medium|low|info`), string ids/titles/categories, and optional location/snippet fields. Emit tab-separated, escaped records back to Bash. Reject malformed/unexpected schema rather than guessing.

Store HIGH/CRITICAL records in `_AUR_GUARD_SCAN_REVIEW_FINDINGS`; print all findings in a compact Awtarchy-formatted scanner section so LOW/MEDIUM remain visible.

- [ ] **Step 4: Add final verification/install behavior**

Add:

```bash
_aur_guard_has_scan_review() {
  (( ${#_AUR_GUARD_SCAN_REVIEW_FINDINGS[@]} > 0 ))
}
```

Add `_aur_guard_print_scan_review` and an interactive `_aur_guard_confirm_scan_review_install <pkg>` that:
- prints exact review findings;
- requires a TTY;
- accepts only explicit `y`/`yes` for current transaction;
- persists nothing.

`aurverify`: after all existing hard checks pass, print `REVIEW REQUIRED:` instead of `PASSED:` when review state exists and return 2.

`aurinstall`: after verification/identity review but before `_aur_guard_build_verified_artifacts`, require scanner-review acknowledgement. Decline/no TTY returns failure before build.

- [ ] **Step 5: Run focused tests GREEN**

```bash
bash -n bashrc
shellcheck bashrc tests/test-aur-scan-review-policy.sh
bash tests/test-aur-scan-review-policy.sh
bash tests/test-security-boundaries.sh
bash tests/test-aur-scan-self-heal.sh
bash tests/test-aur-scan-checkout-delegation.sh
git diff --check
```

Expected: all exit 0.

- [ ] **Step 6: Commit**

```bash
git add bashrc tests/test-aur-scan-review-policy.sh .github/workflows/apply-aur-scan-integration.yml
git commit -m "Review aur-scan heuristics without blind blocking"
```

---

### Task 2: Generic signed-metadata integrity chains

**Files:**
- Modify: `bashrc` around `_aur_guard_validate_skipped_integrity` and source verification ordering.
- Create: `tests/test-aur-signed-metadata-chain.sh`
- Modify: `.github/workflows/apply-aur-scan-integration.yml`

**Interfaces:**
- Produces `_aur_guard_verify_signed_metadata_chain <pkgbase> <srcinfo> <pkgdir>` returning 0 only when a skipped remote source is mechanically bound to a pinned PGP trust root through SHA-256-or-stronger metadata.
- `_aur_guard_validate_skipped_integrity` still hard-fails any skipped remote source not covered directly or by a proven chain.

- [ ] **Step 1: Write failing chain regression**

Fixture a minimal package directory containing:
- `.SRCINFO` with `Release`, `Release.sig`, `Packages`, and a payload source, with `SKIP` on the downstream metadata/payload positions;
- a PKGBUILD that verifies a SHA256 digest for `Packages` from `Release`, then verifies the payload SHA256 from `Packages`;
- a full 40-hex `validpgpkeys` fingerprint;
- test files with known SHA256 values.

Stub the earlier sandbox signature-verification result as already successful, then assert:
- valid Release -> Packages -> payload chain passes;
- changed Packages fails;
- changed payload fails;
- missing full fingerprint fails;
- unauthenticated expected hash retrieval pattern fails;
- package name is irrelevant to the result.

- [ ] **Step 2: Run and confirm RED**

```bash
bash tests/test-aur-signed-metadata-chain.sh
```

Expected failure: current `_aur_guard_validate_skipped_integrity` rejects the SKIP source before any chained proof exists.

- [ ] **Step 3: Implement narrow proof recognizer**

Add a verifier that accepts only an auditable pattern:
- full fingerprint exists in verified `.SRCINFO`;
- a detached signature sidecar protects the root metadata file;
- root metadata contains a SHA256/SHA512/BLAKE2 digest and size entry for the next metadata file;
- actual next-file digest/size matches;
- next metadata contains SHA256/SHA512/BLAKE2 digest for the payload filename;
- actual payload digest matches;
- PKGBUILD contains a fail-closed comparison for each hop and does not source the expected digest from `curl`, `wget`, `eval`, or command execution outside the verified local metadata.

Record accepted local filenames in a transaction-local set so `_aur_guard_validate_skipped_integrity` can treat only those exact sources as strongly verified. Do not special-case Spotify.

- [ ] **Step 4: Preserve ordering**

The chain verifier must run only after `makepkg --verifysource` has succeeded for the pinned detached signature and before final SKIP rejection. Re-check tracked AUR files afterward as existing code already does.

- [ ] **Step 5: Run GREEN**

```bash
bash -n bashrc
shellcheck bashrc tests/test-aur-signed-metadata-chain.sh
bash tests/test-aur-signed-metadata-chain.sh
bash tests/test-security-boundaries.sh
bash tests/test-aur-scan-review-policy.sh
git diff --check
```

- [ ] **Step 6: Commit**

```bash
git add bashrc tests/test-aur-signed-metadata-chain.sh .github/workflows/apply-aur-scan-integration.yml
git commit -m "Verify signed AUR metadata integrity chains"
```

---

### Task 3: Self-refreshing exact-commit AurGuard runtime

**Files:**
- Modify: `bashrc` to add stable runtime markers/bootstrap dispatcher and thin public dispatch hooks.
- Create: `tests/test-aurguard-runtime-refresh.sh`
- Modify: `.github/workflows/apply-aur-scan-integration.yml`
- Modify installer/update delivery tests only where required to ensure the updated `.bashrc` bootstrap is installed.

**Interfaces:**
- Produces `_aur_guard_runtime_dispatch <command> [args...]`.
- Cache path: `${XDG_DATA_HOME:-$HOME/.local/share}/awtarchy/aurguard-runtime.sh`.
- Metadata path: `${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy/aurguard-runtime`.
- Public commands dispatch exactly once; runtime child sets `AWTARCHY_AURGUARD_RUNTIME_ACTIVE=1` to prevent recursion.

- [ ] **Step 1: Write failing runtime-refresh regression**

The test uses fake `curl`, fixed commit responses, temporary XDG dirs, and a fixture `bashrc` with runtime markers. Verify:
- missing cache resolves an exact 40-hex revision, downloads exact-revision source, extracts/validates runtime, atomically installs it, writes non-sourceable key/value metadata, and dispatches;
- fresh cache (<86400 seconds) performs zero refresh network calls;
- stale cache refreshes;
- refresh failure with valid cache warns and dispatches cached runtime;
- refresh failure without cache fails;
- bad syntax/identity marker candidate does not replace valid cache;
- changed branch head during candidate fetch rejects candidate and retries/falls back;
- Git-testing metadata selects the exact testing commit rather than `main`;
- `flock` serialization yields one activation for concurrent refresh attempts.

- [ ] **Step 2: Run and confirm RED**

```bash
bash tests/test-aurguard-runtime-refresh.sh
```

Expected failure: no runtime dispatcher/cache exists.

- [ ] **Step 3: Add stable runtime markers and extraction**

Wrap the complete AurGuard implementation region in fixed comments such as:

```bash
# AWTARCHY_AURGUARD_RUNTIME_BEGIN v1
...
# AWTARCHY_AURGUARD_RUNTIME_END v1
```

The cached runtime is generated from exact-commit `bashrc` bytes by extracting only the content between these markers, prepending:

```bash
# AWTARCHY_AURGUARD_RUNTIME v1
# shellcheck shell=bash
```

and validating `bash -n` plus required dispatcher/public functions. Never source the rest of remote `.bashrc`.

- [ ] **Step 4: Implement refresh/cache bootstrap**

Bootstrap behavior:
- when `AWTARCHY_AURGUARD_RUNTIME_ACTIVE=1`, run local implementation directly;
- otherwise validate current cache hash/metadata;
- if fresh, dispatch immediately without GitHub request;
- if missing/stale, acquire user-owned `flock`, re-check freshness, resolve target exact commit, fetch exact commit `bashrc`, extract runtime markers, validate syntax/size/identity, re-resolve the target ref to detect movement, atomically activate, then dispatch;
- normal target ref is `main`;
- active Git-testing state comes from existing Awtarchy state metadata and uses its exact revision;
- no valid cache on refresh failure means failure;
- valid cache on refresh failure means concise warning + cache.

Add `aurguard refresh` as an explicit force-refresh path while preserving existing `aur` help behavior.

- [ ] **Step 5: Run GREEN**

```bash
bash -n bashrc
shellcheck bashrc tests/test-aurguard-runtime-refresh.sh
bash tests/test-aurguard-runtime-refresh.sh
bash tests/test-aur-scan-review-policy.sh
bash tests/test-aur-signed-metadata-chain.sh
bash tests/test-security-boundaries.sh
bash tests/test-aur-scan-self-heal.sh
bash tests/test-aur-scan-checkout-delegation.sh
git diff --check
```

- [ ] **Step 6: Commit**

```bash
git add bashrc tests/test-aurguard-runtime-refresh.sh .github/workflows/apply-aur-scan-integration.yml
git commit -m "Self-refresh AurGuard from exact Awtarchy commits"
```

---

### Task 4: Final integration and real-machine acceptance head

**Files:**
- Modify: `.github/workflows/apply-aur-scan-integration.yml` to include every new test and remain `contents: read`.
- Modify: PR #121 body after validation.

- [ ] **Step 1: Run complete focused validation**

```bash
bash -n bashrc
bash -n tests/test-security-boundaries.sh
bash -n tests/test-aur-scan-self-heal.sh
bash -n tests/test-aur-scan-checkout-delegation.sh
bash -n tests/test-aur-scan-review-policy.sh
bash -n tests/test-aur-signed-metadata-chain.sh
bash -n tests/test-aurguard-runtime-refresh.sh
shellcheck bashrc \
  tests/test-security-boundaries.sh \
  tests/test-aur-scan-self-heal.sh \
  tests/test-aur-scan-checkout-delegation.sh \
  tests/test-aur-scan-review-policy.sh \
  tests/test-aur-signed-metadata-chain.sh \
  tests/test-aurguard-runtime-refresh.sh
bash tests/test-security-boundaries.sh
bash tests/test-aur-scan-self-heal.sh
bash tests/test-aur-scan-checkout-delegation.sh
bash tests/test-aur-scan-review-policy.sh
bash tests/test-aur-signed-metadata-chain.sh
bash tests/test-aurguard-runtime-refresh.sh
git diff --check
```

- [ ] **Step 2: Confirm repository-wide Actions**

Require all PR workflows, including `Validate Awtarchy`, to complete successfully on one exact head. Confirm focused workflow token permission is `contents: read` and no temporary write-capable applicator remains.

- [ ] **Step 3: Update PR body**

Document scanner review policy, signed-metadata chains, runtime refresh model, exact final head, CI state, and mark real-machine acceptance pending.

- [ ] **Step 4: Hand user one exact test command**

Provide:

```bash
awtarchy git update \
  --branch feature/aur-scan-integration \
  --commit <FINAL_HEAD>
exec bash
```

Then the acceptance matrix:

```bash
aurverify hyprmoncfg-bin
aurverify google-chrome
aurverify visual-studio-code-bin
aurverify brave-bin
aurverify spotify
aurverify paru
aurverify mpvpaper
aurverify qimgv
aurverify alacritty-graphics
aurverify obs-pipewire-audio-capture-bin
aurverify smtty
```

Expected:
- clean/LOW/MEDIUM packages complete normally;
- Google Chrome/VS Code/Brave continue through all hard verification and finish `REVIEW REQUIRED`, not false `FAILED`, if no independent hard failure exists;
- Spotify proves the signed metadata chain and no longer fails solely on its chained SKIP source;
- no package is installed by `aurverify`.

Finally test one review-gated install only after verifying no hard failure:

```bash
aurinstall visual-studio-code-bin
```

Expected: full verification first, then one explicit scanner-review acknowledgement immediately before build/install; decline must install nothing.

## Plan Self-Review

- Spec coverage: scanner policy, install review, chained integrity, runtime freshness/fallback/Git-testing/concurrency, existing hard boundaries, CI, and real-machine matrix are all mapped to tasks.
- Placeholder scan: no TBD/TODO or unspecified implementation step remains.
- Interface consistency: scanner review state is transaction-local; signed-chain verifier only influences SKIP integrity; runtime dispatcher is the only recursion-control boundary and uses `AWTARCHY_AURGUARD_RUNTIME_ACTIVE=1` consistently.
