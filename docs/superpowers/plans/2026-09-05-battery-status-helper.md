# Battery Care Read-Only Status Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the unprivileged Quickshell Battery Care detector read authoritative `tlp-stat -b` output on current TLP without making any battery write path passwordless.

**Architecture:** Add a zero-argument root-owned read-only helper at `/usr/local/libexec/awtarchy/battery-status-helper`. The existing laptop power reconciler installs that helper plus one exact `NOPASSWD` sudoers rule, while the detector prefers `sudo -n -- /usr/local/libexec/awtarchy/battery-status-helper` and retains direct `tlp-stat -b` only as a fallback. Vendor normalization stays entirely in the existing detector; the status helper only returns TLP output.

**Tech Stack:** Bash, sudo/sudoers, `visudo`, TLP 1.10 `tlp-stat -b`, jq, ShellCheck, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-05-battery-status-helper-design.md`

## Global Constraints

- Work only on `hardening/tlp-battery-compatibility`; do not modify or merge `main`.
- Keep `/usr/local/libexec/awtarchy/power-profile-helper` authenticated; never grant it `NOPASSWD` access.
- The new status helper accepts zero arguments and executes only `/usr/bin/tlp-stat -b`.
- The helper must require EUID 0 and clear caller-controlled environment state before executing TLP.
- The detector must use noninteractive `sudo -n`; opening Battery Care must never create an authentication prompt.
- Unknown/unvalidated TLP plugins remain fail-closed for writes.
- Existing Sony, Lenovo, LG, ASUS, ThinkPad, Tuxedo, mixed-battery, rollback, and external-config behavior must remain unchanged.
- Preserve the current Awtarchy power reconciler architecture rather than adding a second install path.
- TDD is mandatory: every production behavior change must be preceded by a regression that fails for the intended reason.

---

### Task 1: Implement the fixed read-only status helper

**Files:**
- Create: `local/libexec/awtarchy/battery-status-helper`
- Test: `tests/test-power-profile-helper-update.sh`
- Test: `tests/test-battery-status-helper.sh`

**Interfaces:**
- Consumes: root execution via the exact sudoers command `/usr/local/libexec/awtarchy/battery-status-helper`.
- Produces: unmodified stdout/stderr and exit status from `/usr/bin/tlp-stat -b`; no write capability and no arguments.

- [ ] **Step 1: Preserve the existing RED proof**

Run the already-committed regression on the exact branch head. Expected failure:

```text
FAIL: read-only Battery Care status helper is missing
```

This proves the missing privileged read bridge is the reason for RED rather than an unrelated test failure.

- [ ] **Step 2: Add focused helper behavior tests before the helper exists**

Create `tests/test-battery-status-helper.sh` that asserts:

```bash
[[ -f "$HELPER" ]] || fail 'battery status helper is missing'
grep -Fq '#!/usr/bin/bash' "$HELPER" || fail 'helper interpreter is not fixed'
grep -Fq '[[ $# -eq 0 ]]' "$HELPER" || fail 'helper does not reject arguments'
grep -Fq '(( EUID == 0 ))' "$HELPER" || fail 'helper is not root-only'
grep -Fq '/usr/bin/env -i' "$HELPER" || fail 'helper does not sanitize its environment'
grep -Fq '/usr/bin/tlp-stat -b' "$HELPER" || fail 'helper does not execute the fixed battery report'
! grep -Fq '"$@"' "$HELPER" || fail 'helper forwards arguments'
! grep -Fq '/usr/bin/tlp ' "$HELPER" || fail 'helper contains a battery write command'
```

The test must also create a temporary copy whose fixed `/usr/bin/tlp-stat` path is replaced with a fake executable, then verify a root-run zero-argument invocation forwards the fake report and status while an invocation with an argument fails before the fake binary runs.

- [ ] **Step 3: Run the focused helper test and verify RED**

Run:

```bash
sudo bash tests/test-battery-status-helper.sh
```

Expected: FAIL because `local/libexec/awtarchy/battery-status-helper` does not exist.

- [ ] **Step 4: Implement the minimal helper**

Create `local/libexec/awtarchy/battery-status-helper` with this behavior:

```bash
#!/usr/bin/bash
set -euo pipefail

[[ $# -eq 0 ]] || {
  printf 'battery-status-helper: no arguments are accepted\n' >&2
  exit 2
}

(( EUID == 0 )) || {
  printf 'battery-status-helper: root privileges are required\n' >&2
  exit 1
}

exec /usr/bin/env -i \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin \
  LC_ALL=C \
  /usr/bin/tlp-stat -b
```

Do not add environment overrides, arbitrary command forwarding, or write operations.

- [ ] **Step 5: Verify helper GREEN**

Run:

```bash
sudo bash tests/test-battery-status-helper.sh
bash -n local/libexec/awtarchy/battery-status-helper
shellcheck local/libexec/awtarchy/battery-status-helper tests/test-battery-status-helper.sh
```

Expected: all PASS.

- [ ] **Step 6: Commit**

Commit the helper and focused test together with a concise message such as `Add read-only TLP battery status helper`.

---

### Task 2: Install and authorize only the read-only helper

**Files:**
- Modify: `local/share/awtarchy/awtarchy-power-profile.sh`
- Modify: `tests/test-power-profile-helper-update.sh`
- Test: `tests/test-power-profile-inline-auth.sh`
- Test: `tests/test-security-boundaries.sh`

**Interfaces:**
- Consumes: repository source `local/libexec/awtarchy/battery-status-helper` and the invoking Awtarchy desktop user.
- Produces: root-owned `/usr/local/libexec/awtarchy/battery-status-helper` plus one root-owned `0440` sudoers file whose only command is that helper with zero arguments.

- [ ] **Step 1: Extend the existing RED assertions to cover policy safety**

Before changing the reconciler, require all of the following in tests:

```text
BATTERY_STATUS_HELPER_SOURCE="${REPO_ROOT}/local/libexec/awtarchy/battery-status-helper"
BATTERY_STATUS_HELPER_DESTINATION="/usr/local/libexec/awtarchy/battery-status-helper"
visudo -cf
NOPASSWD: ${BATTERY_STATUS_HELPER_DESTINATION} ""
```

Also retain explicit absence checks for any `NOPASSWD` grant to `power-profile-helper`.

- [ ] **Step 2: Run the reconciler/auth tests and verify RED**

Run:

```bash
bash tests/test-power-profile-helper-update.sh
bash tests/test-power-profile-inline-auth.sh
bash tests/test-security-boundaries.sh
```

Expected: the power-profile update test remains RED because install/policy behavior is missing.

- [ ] **Step 3: Add fixed reconciler paths and target-user validation**

Add fixed constants near the existing helper paths:

```bash
BATTERY_STATUS_HELPER_SOURCE="${REPO_ROOT}/local/libexec/awtarchy/battery-status-helper"
BATTERY_STATUS_HELPER_DESTINATION="/usr/local/libexec/awtarchy/battery-status-helper"
SUDOERS_DIR="${AWTARCHY_SUDOERS_DIR:-/etc/sudoers.d}"
```

Resolve the policy user from the real non-root invoking account, preferring `SUDO_USER` only when it is non-empty and not `root`, otherwise the current non-root `USER`/`id -un`. Validate it against `^[a-z_][a-z0-9_-]*[$]?$`; fail rather than writing a malformed sudoers rule.

- [ ] **Step 4: Add status-helper install verification**

Follow the existing `power_profile_helper_is_current()` and atomic install pattern:

- source must be a regular non-symlink file;
- first line must be `#!/usr/bin/bash`;
- `bash -n` must pass;
- destination directory must be root-owned and not group/world writable;
- stage with `install -m 0755 -o root -g root`;
- verify source/staged SHA-256;
- atomically `mv -Tf` into place;
- verify final owner/mode/content.

Do not merge write-helper and status-helper permissions.

- [ ] **Step 5: Add exact sudoers policy installation**

Create a deterministic Awtarchy-owned sudoers path such as:

```text
/etc/sudoers.d/awtarchy-battery-status-<user>
```

Stage its complete content in the same root-owned directory:

```text
<user> ALL=(root) NOPASSWD: /usr/local/libexec/awtarchy/battery-status-helper ""
```

Set mode `0440`, owner `root:root`, validate the staged file with `/usr/sbin/visudo -cf`, then atomically activate it. Refuse symlinked sudoers paths/directories and do not overwrite a non-Awtarchy policy with unrelated content.

- [ ] **Step 6: Invoke status-helper reconciliation from the existing laptop backend path**

`install_laptop_backend()` must install/repair the read-only status helper and its policy along with the existing authenticated write helper before returning successfully.

- [ ] **Step 7: Verify reconciler/auth GREEN**

Run:

```bash
bash tests/test-power-profile-helper-update.sh
bash tests/test-power-profile-inline-auth.sh
bash tests/test-security-boundaries.sh
bash -n local/share/awtarchy/awtarchy-power-profile.sh
shellcheck local/share/awtarchy/awtarchy-power-profile.sh tests/test-power-profile-helper-update.sh tests/test-power-profile-inline-auth.sh tests/test-security-boundaries.sh
```

Expected: all PASS and no `NOPASSWD` rule references `power-profile-helper`.

- [ ] **Step 8: Commit**

Commit the reconciler/policy behavior and tests with a concise message such as `Install narrow battery status sudo bridge`.

---

### Task 3: Route detector reads through the noninteractive bridge

**Files:**
- Modify: `config/hypr/scripts/quickshell_battery_care.sh`
- Modify: `tests/test-power-profile-helper-update.sh`
- Test: `tests/test-battery-care-detector-profiles.sh`
- Test: `tests/test-battery-charge-limit-detection.sh`

**Interfaces:**
- Consumes: `/usr/local/libexec/awtarchy/battery-status-helper` via `/usr/bin/sudo -n --`.
- Produces: the same detector JSON contract as before, now backed by authoritative TLP output on systems where direct unprivileged `tlp-stat -b` fails.

- [ ] **Step 1: Preserve the functional RED fixture**

The already-committed regression deliberately supplies:

- a direct `tlp-stat` executable that exits with `root privileges required`;
- a fake zero-argument status helper returning Dell range semantics;
- a fake sudo accepting only `-n -- <helper>`.

Before production changes, rerun `bash tests/test-power-profile-helper-update.sh` and confirm that fixture remains RED.

- [ ] **Step 2: Add fixed detector bridge variables**

Add:

```bash
BATTERY_STATUS_HELPER="${AWTARCHY_BATTERY_STATUS_HELPER:-/usr/local/libexec/awtarchy/battery-status-helper}"
SUDO_BIN="${AWTARCHY_SUDO_BIN:-/usr/bin/sudo}"
```

The overrides exist only so tests can exercise the unprivileged detector without modifying `/usr/local` or `/usr/bin`; production defaults remain absolute trusted paths.

- [ ] **Step 3: Add one read-only TLP report function**

Implement a helper such as:

```bash
read_tlp_battery_report() {
    local report=""
    if [[ -x "$BATTERY_STATUS_HELPER" && -x "$SUDO_BIN" ]]; then
        report="$("$SUDO_BIN" -n -- "$BATTERY_STATUS_HELPER" 2>/dev/null || true)"
        [[ -n "$report" ]] && { printf '%s\n' "$report"; return 0; }
    fi
    if [[ -x "$TLP_STAT_BIN" ]]; then
        report="$("$TLP_STAT_BIN" -b 2>/dev/null || true)"
        [[ -n "$report" ]] && { printf '%s\n' "$report"; return 0; }
    fi
    return 1
}
```

The privileged path must be attempted first. It must use `sudo -n`, never plain `sudo`.

- [ ] **Step 4: Replace direct detector invocation with the read function**

Set `tlp_available=true` only when an executable TLP/status path is present, populate `tlp_output` through `read_tlp_battery_report`, and leave plugin/features/spec parsing unchanged. If both reads fail, existing fail-closed normalization must remain intact.

- [ ] **Step 5: Verify detector GREEN**

Run:

```bash
bash tests/test-power-profile-helper-update.sh
bash tests/test-battery-care-detector-profiles.sh
bash tests/test-battery-charge-limit-detection.sh
bash tests/test-battery-care-compatibility.sh
bash tests/test-battery-care-write-gating.sh
bash -n config/hypr/scripts/quickshell_battery_care.sh
shellcheck config/hypr/scripts/quickshell_battery_care.sh tests/test-power-profile-helper-update.sh
```

Expected: all PASS, including the simulated root-only Dell report.

- [ ] **Step 6: Commit**

Commit detector routing with a concise message such as `Read TLP battery status through safe bridge`.

---

### Task 4: Permanent CI, updater metadata, and full hostile verification

**Files:**
- Modify if needed: `.github/workflows/validate-awtarchy.yml`
- Modify if detector hash changed: `local/share/awtarchy/quickshell-managed-history.sha256`
- Test: full repository validation set

**Interfaces:**
- Consumes: all prior tasks.
- Produces: exact-head CI evidence and a clean branch ready for another audit pass, not an automatic merge.

- [ ] **Step 1: Ensure permanent CI executes focused coverage**

If `tests/test-battery-status-helper.sh` is new, add both syntax/ShellCheck coverage and a test invocation to the normal `Validate Awtarchy` workflow. Do not add a temporary write-capable workflow.

- [ ] **Step 2: Refresh managed Quickshell history only for changed release-managed detector/UI files**

Because `quickshell_battery_care.sh` is release-managed, append its exact new SHA-256 to `local/share/awtarchy/quickshell-managed-history.sha256` using the existing updater-policy format. Do not regenerate unrelated entries.

- [ ] **Step 3: Run focused battery/security verification**

Run:

```bash
sudo bash tests/test-battery-status-helper.sh
sudo bash tests/test-battery-care-control.sh
bash tests/test-battery-care-compatibility.sh
bash tests/test-battery-care-detector-profiles.sh
bash tests/test-battery-care-vendor-semantics.sh
bash tests/test-battery-care-write-gating.sh
bash tests/test-battery-care-annotated-range.sh
bash tests/test-battery-care-thinkpad-readback.sh
bash tests/test-battery-care-multibattery.sh
bash tests/test-power-profile-helper-update.sh
bash tests/test-power-profile-inline-auth.sh
bash tests/test-security-boundaries.sh
git diff --check
```

Expected: all PASS.

- [ ] **Step 4: Run permanent PR CI on the exact final head**

Wait for every PR-triggered workflow associated with the exact branch head. `Validate Awtarchy` must pass Bash syntax, ShellCheck, desktop validation, and the complete integration suite. Any failure resets the clean-pass counter and must be diagnosed before proceeding.

- [ ] **Step 5: Hostile audit pass**

Compare the final detector/helper/reconciler behavior against current upstream TLP plugin semantics and inspect:

- privilege escalation surface;
- sudoers argument matching;
- environment influence;
- install/update ownership and symlink handling;
- multi-battery reporting and rollback;
- vendor-specific disable/readback semantics;
- missing-root-status behavior;
- failure messages that claim restoration or success without proof.

A pass counts toward the requested 3-pass completion counter only if it discovers no real defect. Any real defect resets the counter to 0/3 and starts a new RED/GREEN cycle.

- [ ] **Step 6: Update PR #148 only after exact-head verification**

Update the PR description/evidence so obsolete previously-green head claims are not presented as current. Keep the PR open and unmerged until the user separately approves merge/release behavior.
