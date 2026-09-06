# TLP Battery Compatibility Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Awtarchy Battery Care fail closed on unknown TLP hardware, correctly implement current upstream TLP vendor semantics, and add regression coverage for every supported compatibility class.

**Architecture:** Keep TLP as the hardware compatibility authority. The unprivileged detector reports capability plus explicit Awtarchy write eligibility, the root-owned helper independently enforces the same validated plugin set and performs TLP-mediated writes with plugin-specific read-back verification/rollback, and QML consumes only normalized detector data. Tests simulate upstream TLP `tlp-stat -b` behavior so compatibility logic is exercised without physical hardware.

**Tech Stack:** Bash, QML/Quickshell, jq, TLP 1.10.x vendor plugin semantics, GitHub Actions, ShellCheck.

**Spec:** `docs/superpowers/specs/2026-09-05-tlp-battery-compatibility-hardening-design.md`

## Global Constraints

- Base work on `hardening/tlp-battery-compatibility`, created from `main` commit `eb0f9bf39c87fa97d0948b87be00220d1a8ba4be`.
- TLP remains the source of truth for vendor/plugin semantics; do not create a laptop-model database.
- Quickshell and user-writable scripts must never write battery sysfs directly.
- Unknown future TLP plugins must fail closed for writes.
- `generic` must remain unsupported/non-writable.
- Preserve external-user-TLP-config conflict detection, read-back verification, and rollback.
- Preserve Sony raw `battery_care_limiter=0` as logical OFF/100%.
- Do not modify the published v3.5.4 tag or create another v3.5.4 post-release bridge in this branch.
- Do not source a user-writable compatibility policy into the installed root helper; detector/helper parity is enforced by tests instead.

---

### Task 1: Add failing compatibility-policy and detector tests

**Files:**
- Create: `tests/test-battery-care-compatibility.sh`
- Modify: `tests/test-battery-charge-limit-detection.sh`
- Read: `config/hypr/scripts/quickshell_battery_care.sh`
- Read: `local/libexec/awtarchy/power-profile-helper`

**Interfaces:**
- Consumes: existing detector JSON contract from `quickshell_battery_care.sh --status-json`.
- Produces: regression expectations for new detector fields `writable` (JSON boolean) and `compatibility` (`validated|unvalidated|unsupported`), plus exact detector/helper validated plugin-set parity.

- [ ] **Step 1: Extend detector regression assertions to require explicit write eligibility**

In `tests/test-battery-charge-limit-detection.sh`, add assertions after the existing Dell range fixture:

```bash
assert_json "$json" '.writable == true and .compatibility == "validated"' \
    'validated Dell hardware was not marked writable'
```

Add the same validated/write assertion for current `lg`, `lenovo`, and `samsung` fixtures.

Change the sysfs-only expectation to:

```bash
assert_json "$json" '.supported == true and .writable == false and .compatibility == "unvalidated" and .backend == "sysfs" and .mode == "sysfs"' \
    'standard sysfs fallback was not kept read-only/unvalidated'
```

Change unsupported/no-interface expectation to:

```bash
assert_json "$json" '.supported == false and .writable == false and .compatibility == "unsupported" and .backend == "none" and .mode == "unsupported"' \
    'unsupported hardware was incorrectly advertised as charge-limit capable'
```

Add an unknown-TLP fixture:

```bash
unknown_root="$TMP/unknown-power"
make_battery "$unknown_root" BAT0 '' 80
cat >"$TMP/tlp-unknown" <<'EOF_TLP_UNKNOWN'
#!/usr/bin/env bash
cat <<'EOF_STATUS'
+++ Battery Care
Plugin: future-vendor
Supported features: charge threshold
Parameter value range:
* STOP_CHARGE_THRESH_BAT0: 50..100(default)
/sys/class/power_supply/BAT0/charge_control_end_threshold = 80 [%]
EOF_STATUS
EOF_TLP_UNKNOWN
chmod +x "$TMP/tlp-unknown"

json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$unknown_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-unknown" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.supported == true and .writable == false and .compatibility == "unvalidated" and .plugin == "future-vendor"' \
    'unknown TLP plugin was not detected-but-fail-closed'
```

Add a generic fixture:

```bash
generic_root="$TMP/generic-power"
make_battery "$generic_root" BAT0
cat >"$TMP/tlp-generic" <<'EOF_TLP_GENERIC'
#!/usr/bin/env bash
cat <<'EOF_STATUS'
+++ Battery Care
Plugin: generic
Supported features: none available
EOF_STATUS
EOF_TLP_GENERIC
chmod +x "$TMP/tlp-generic"

json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$generic_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-generic" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.supported == false and .writable == false and .compatibility == "unsupported" and .plugin == "generic"' \
    'generic TLP backend was not kept unsupported/non-writable'
```

- [ ] **Step 2: Create a focused compatibility-set parity test**

Create `tests/test-battery-care-compatibility.sh` with a helper that extracts the explicit validated plugin list from both files and compares sorted sets. The expected current set is:

```text
asus
cros-ec
dell
huawei
lenovo
lenovo-legacy
lg
macbook
msi
samsung
sony
system76
thinkpad
thinkpad-legacy
toshiba
tuxedo
wilco-ec
```

The test must explicitly assert that `lg-legacy` and `generic` are absent from the writable set.

Use source markers that implementation will add verbatim:

```bash
battery_plugin_writable() {
```

in both detector and helper. Extract each `case` body and compare the plugin alternation line after implementation.

- [ ] **Step 3: Run the new/changed tests and confirm RED**

Run:

```bash
bash tests/test-battery-charge-limit-detection.sh
bash tests/test-battery-care-compatibility.sh
```

Expected before implementation: failures because `writable`, `compatibility`, and detector-side `battery_plugin_writable()` do not yet exist, and helper still includes `lg-legacy`.

- [ ] **Step 4: Commit only the failing tests**

```bash
git add tests/test-battery-charge-limit-detection.sh tests/test-battery-care-compatibility.sh
git commit -m "test: define TLP battery compatibility policy"
```

---

### Task 2: Make detector classification explicit and fail closed

**Files:**
- Modify: `config/hypr/scripts/quickshell_battery_care.sh`
- Test: `tests/test-battery-charge-limit-detection.sh`
- Test: `tests/test-battery-care-compatibility.sh`

**Interfaces:**
- Consumes: TLP `Plugin`, `Supported features`, advertised start/stop specs, and existing sysfs read-only values.
- Produces JSON fields:
  - `supported: bool`
  - `writable: bool`
  - `compatibility: "validated"|"unvalidated"|"unsupported"`
  - existing `backend`, `plugin`, `mode`, ranges/presets/state.

- [ ] **Step 1: Add explicit detector writable-plugin policy**

Add near TLP capability parsing:

```bash
battery_plugin_writable() {
    case "$1" in
        asus|cros-ec|dell|huawei|thinkpad|thinkpad-legacy|lenovo|lenovo-legacy|lg|macbook|msi|samsung|sony|system76|toshiba|tuxedo|wilco-ec) return 0 ;;
        *) return 1 ;;
    esac
}
```

Do not include `lg-legacy` or `generic`.

- [ ] **Step 2: Separate capability from Awtarchy write eligibility**

Initialize:

```bash
writable=false
compatibility="unsupported"
```

For TLP capability:

- if plugin is `generic` or TLP reports no charge capability: keep `supported=false`, `writable=false`, `compatibility=unsupported`;
- if TLP reports capability and `battery_plugin_writable "$plugin_lower"`: set `supported=true`, `writable=true`, `compatibility=validated` and continue current mode parsing;
- if TLP reports capability but plugin is unknown/unvalidated: set `supported=true`, `writable=false`, `compatibility=unvalidated`, `backend=tlp`, and keep enough range/preset parsing for informational display without authorizing controls;
- sysfs-only capability: `supported=true`, `writable=false`, `compatibility=unvalidated`.

Do not silently rewrite an unknown plugin to a known one except the existing Sony sysfs recovery path, which is based on Sony's actual kernel node.

- [ ] **Step 3: Emit the two new JSON fields**

Add `--argjson writable "$writable"` and `--arg compatibility "$compatibility"`, then include:

```jq
writable:$writable,
compatibility:$compatibility,
```

in the output object.

- [ ] **Step 4: Run detector/parity tests and confirm GREEN for detector behavior**

```bash
bash tests/test-battery-charge-limit-detection.sh
bash tests/test-battery-care-compatibility.sh
```

The parity test may still fail until Task 4 removes `lg-legacy` from the helper writable set; detector-specific assertions must pass.

- [ ] **Step 5: Commit detector hardening**

```bash
git add config/hypr/scripts/quickshell_battery_care.sh tests/test-battery-charge-limit-detection.sh tests/test-battery-care-compatibility.sh
git commit -m "fix: fail closed on unvalidated TLP battery plugins"
```

---

### Task 3: Gate Quickshell controls on detector write eligibility

**Files:**
- Modify: `config/quickshell/awtarchy/BatteryCareCard.qml`
- Test: `tests/test-battery-care-control.sh`
- Test: `tests/test-battery-charge-limit-detection.sh`

**Interfaces:**
- Consumes: detector fields `supported`, `writable`, `compatibility`, `backend`, `config_conflict`, normalized mode/targets.
- Produces: no write controls for unvalidated/unsupported backends while retaining informative status text.

- [ ] **Step 1: Add failing QML source-contract assertions**

In `tests/test-battery-care-control.sh`, require the card to consume the new field:

```bash
require_source "$CARD" '&& Boolean(statusData.writable)' 'Battery Care controls do not require validated writable support'
require_source "$CARD" 'writable: false' 'Battery Care empty state does not default writes to disabled'
require_source "$CARD" 'compatibility: "unsupported"' 'Battery Care empty state has no compatibility classification'
```

Run:

```bash
bash tests/test-battery-care-control.sh
```

Expected: FAIL before QML implementation.

- [ ] **Step 2: Extend `emptyStatus()`**

Add:

```qml
writable: false,
compatibility: "unsupported",
```

- [ ] **Step 3: Harden `controlsAvailable`**

Change it to require write eligibility:

```qml
readonly property bool controlsAvailable: Boolean(statusData.supported)
    && Boolean(statusData.writable)
    && String(statusData.backend || "") === "tlp"
    && !Boolean(statusData.config_conflict)
    && (fixedUnknownTarget || root.hasNumericControl())
```

No laptop/vendor-specific logic is added to QML.

- [ ] **Step 4: Add unvalidated explanatory text path**

Where the card renders detector detail/summary, ensure an unvalidated TLP plugin displays its detector-provided summary/detail and does not render enabled controls. Detector text should be set to:

```text
Battery Care detected but not validated by Awtarchy
Write controls are disabled for this backend.
```

for `compatibility=unvalidated` with a TLP backend.

- [ ] **Step 5: Run focused UI/control tests**

```bash
bash tests/test-battery-charge-limit-detection.sh
bash tests/test-battery-care-control.sh
```

Expected: PASS.

- [ ] **Step 6: Commit UI gating**

```bash
git add config/quickshell/awtarchy/BatteryCareCard.qml tests/test-battery-care-control.sh
git commit -m "fix: gate battery writes on validated TLP support"
```

---

### Task 4: Correct helper plugin policy, LG semantics, and dual-battery config behavior

**Files:**
- Modify: `local/libexec/awtarchy/power-profile-helper`
- Modify: `tests/test-battery-care-control.sh`
- Test: `tests/test-battery-care-compatibility.sh`
- Test: `tests/test-battery-care-multibattery.sh`

**Interfaces:**
- Consumes: current `tlp-stat -b` plugin/features/spec output.
- Produces: exact helper-side writable plugin policy, correct current LG literal `80/100` writes, BAT1 managed config for Lenovo/Tuxedo where TLP uses per-battery config.

- [ ] **Step 1: Add failing helper regression assertions**

Change the LG fake TLP behavior in `tests/test-battery-care-control.sh` from selector semantics to literal current TLP semantics:

```bash
lg)
  target="$stop"
  enabled=$([[ "$target" -lt 100 ]] && printf 1 || printf 0)
  ;;
```

Change assertions to:

```bash
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$MANAGED" || fail 'LG 80% target was not persisted literally'
```

For Lenovo after `battery-enable-fixed`, add:

```bash
grep -Fxq 'START_CHARGE_THRESH_BAT1=0' "$MANAGED" || fail 'Lenovo BAT1 dummy start threshold missing'
grep -Fxq 'STOP_CHARGE_THRESH_BAT1=1' "$MANAGED" || fail 'Lenovo BAT1 Long_Life selector was not persisted'
```

For Tuxedo after `battery-set 80`, add:

```bash
grep -Fxq 'START_CHARGE_THRESH_BAT1=70' "$MANAGED" || fail 'Tuxedo BAT1 supported start threshold was not selected'
grep -Fxq 'STOP_CHARGE_THRESH_BAT1=80' "$MANAGED" || fail 'Tuxedo BAT1 stop preset was not persisted'
```

Run:

```bash
bash tests/test-battery-care-control.sh
```

Expected: FAIL against current helper.

- [ ] **Step 2: Rename helper allowlist function to express writable semantics**

Replace `battery_plugin_allowed()` with:

```bash
battery_plugin_writable() {
  case "$1" in
    macbook|asus|cros-ec|dell|huawei|thinkpad|thinkpad-legacy|lenovo|lenovo-legacy|lg|msi|samsung|sony|system76|toshiba|tuxedo|wilco-ec) return 0 ;;
    *) return 1 ;;
  esac
}
```

Update `battery_require_capability()` to call `battery_plugin_writable`. This removes `lg-legacy` from current writable support and keeps unknown plugins rejected by the root authority.

- [ ] **Step 3: Correct current LG target translation**

Change `battery_set_target()` so only Samsung translates `80` to selector `1`. For LG:

```bash
lg)
  [[ "$target" == 80 ]] || fail 'LG battery care mode only supports an 80% health target'
  start_value=0
  stop_value=80
  ;;
```

Remove `lg-legacy` from that branch entirely.

- [ ] **Step 4: Expand dual-config plugin set**

Change:

```bash
battery_dual_config_plugin() {
  case "$1" in
    asus|cros-ec|dell|thinkpad|thinkpad-legacy|msi|toshiba|lenovo|tuxedo) return 0 ;;
    *) return 1 ;;
  esac
}
```

Do not add shared/single-config plugins.

- [ ] **Step 5: Run helper/multibattery/parity tests**

```bash
bash tests/test-battery-care-control.sh
bash tests/test-battery-care-multibattery.sh
bash tests/test-battery-care-compatibility.sh
```

Expected: PASS.

- [ ] **Step 6: Commit helper corrections**

```bash
git add local/libexec/awtarchy/power-profile-helper tests/test-battery-care-control.sh tests/test-battery-care-compatibility.sh tests/test-battery-care-multibattery.sh
git commit -m "fix: align battery helper with current TLP vendor semantics"
```

---

### Task 5: Expand simulated vendor-family coverage

**Files:**
- Modify: `tests/test-battery-care-compatibility.sh`
- Read: current upstream `linrunner/TLP` `bat.d/*` plugin files while implementing fixtures.

**Interfaces:**
- Consumes: detector/helper behavior established in Tasks 2-4.
- Produces: simulated regression coverage for every current validated plugin/classification family.

- [ ] **Step 1: Add table-driven detector fixtures for normal/range plugins**

Cover at minimum these exact advertised semantics:

```text
asus: stop 1..100
cros-ec: start 0..99, stop 1..100
dell: start 50..95, stop 55..100
huawei: start 0..99, stop 1..100
msi: start don't care, stop 10..100
system76: start 0..99, stop 1..100
thinkpad: start 0..99, stop 1..100
thinkpad-legacy: start 2..96, stop 6..100
wilco-ec: start 50..95, stop 55..100
```

For each, assert `supported=true`, `writable=true`, `compatibility=validated`, expected mode, and parsed stop bounds.

- [ ] **Step 2: Add preset/fixed fixtures**

Cover:

```text
macbook: stop 80,100; start don't care
sony: stop 50,80,100(off), raw 0 normalizes to 100
tuxedo: start 40/50/60/70/80/95; stop 60/70/80/90/100
lg: stop 80(on),100(off)
toshiba: stop 80(on),100(off)
```

Assert numeric presets exposed to QML exclude logical OFF from target buttons but state normalization still reports OFF as 100.

- [ ] **Step 3: Add selector-family fixtures**

Cover:

```text
lenovo: charge_types Standard/Long_Life
lenovo-legacy: conservation_mode 0/1
samsung: battery_life_extender 0/1 -> normalized 100/80
```

Assert detector normalized `enabled`/`target` semantics without treating raw `0/1` as percentages.

- [ ] **Step 4: Add explicit classification tests for obsolete/unknown backends**

Assert:

```text
lg-legacy -> supported if feature text exists, writable=false, compatibility=unvalidated
generic -> supported=false, writable=false, compatibility=unsupported
future-vendor -> supported=true when feature exists, writable=false, compatibility=unvalidated
```

- [ ] **Step 5: Run compatibility suite**

```bash
bash tests/test-battery-care-compatibility.sh
bash tests/test-battery-charge-limit-detection.sh
bash tests/test-battery-care-control.sh
bash tests/test-battery-care-annotated-range.sh
bash tests/test-battery-care-thinkpad-readback.sh
bash tests/test-battery-care-multibattery.sh
```

Expected: PASS.

- [ ] **Step 6: Commit expanded fixtures**

```bash
git add tests/test-battery-care-compatibility.sh
git commit -m "test: cover current TLP battery vendor profiles"
```

---

### Task 6: Wire the new compatibility test into permanent CI

**Files:**
- Modify: `.github/workflows/validate-awtarchy.yml`
- Test: `tests/test-battery-care-compatibility.sh`

**Interfaces:**
- Consumes: new focused test from Tasks 1/5.
- Produces: syntax, ShellCheck, and execution coverage in repository CI.

- [ ] **Step 1: Add Bash syntax validation**

Add next to the existing battery test syntax checks:

```yaml
bash -n tests/test-battery-care-compatibility.sh
```

- [ ] **Step 2: Add ShellCheck coverage**

Add `tests/test-battery-care-compatibility.sh` to the normal ShellCheck list unless it requires the same narrowly justified suppression as `test-battery-care-control.sh`. Do not globally suppress new warnings.

- [ ] **Step 3: Add test execution**

Find the existing battery test execution block and add:

```bash
bash tests/test-battery-care-compatibility.sh
```

beside the other Battery Care tests.

- [ ] **Step 4: Run workflow-file and focused local checks**

```bash
bash -n tests/test-battery-care-compatibility.sh
shellcheck tests/test-battery-care-compatibility.sh
bash tests/test-battery-care-compatibility.sh
```

Expected: PASS.

- [ ] **Step 5: Commit CI wiring**

```bash
git add .github/workflows/validate-awtarchy.yml tests/test-battery-care-compatibility.sh
git commit -m "ci: validate TLP battery compatibility coverage"
```

---

### Task 7: Verify managed-file/update implications without changing stable release delivery

**Files:**
- Inspect: `local/share/awtarchy/quickshell-managed-history.sha256`
- Inspect: updater/migration tests that cover managed Quickshell/script updates.
- Modify only if current updater rules prove it is required for the changed `BatteryCareCard.qml` or `quickshell_battery_care.sh` state.

**Interfaces:**
- Consumes: final changed release-managed files.
- Produces: correct unreleased update/reset behavior without changing v3.5.4 tag/release maintenance logic.

- [ ] **Step 1: Run managed-history/updater-focused tests before touching history data**

Run the relevant existing tests identified by repository search for `quickshell-managed-history.sha256`, including at least:

```bash
bash tests/test-quickshell-updater-migration.sh
bash tests/test-quickshell-updater-bootstrap.sh
```

- [ ] **Step 2: Only update managed history if those tests/current runtime contract require it**

If no requirement exists, leave `local/share/awtarchy/quickshell-managed-history.sha256` unchanged.

If required, use the repository's existing managed-history generation/update mechanism rather than manually inventing hashes, then rerun every updater test that consumes the file.

- [ ] **Step 3: Confirm v3.5.4 maintenance repair remains scoped and untouched**

Run:

```bash
bash tests/test-battery-care-control.sh
```

Its existing v3.5.4 fixture assertions must still pass. Do not broaden `repair_v354_sony_battery_disable_repo()` to this new hardening branch.

- [ ] **Step 4: Commit only if updater-managed data actually changed**

```bash
git add local/share/awtarchy/quickshell-managed-history.sha256
git commit -m "chore: record battery compatibility managed states"
```

Skip this commit if no managed-history change is required.

---

### Task 8: Full verification, issue update, and PR preparation

**Files:**
- Verify all branch changes.
- Update issue #147 with findings/results after code verification.
- Create a PR from `hardening/tlp-battery-compatibility` to `main` only after local/focused verification is clean; do not merge without maintainer approval.

**Interfaces:**
- Consumes: completed implementation and tests.
- Produces: evidence-backed review state ready for maintainer decision.

- [ ] **Step 1: Run Bash syntax checks for every touched Bash file/test**

```bash
bash -n config/hypr/scripts/quickshell_battery_care.sh
bash -n local/libexec/awtarchy/power-profile-helper
bash -n tests/test-battery-charge-limit-detection.sh
bash -n tests/test-battery-care-control.sh
bash -n tests/test-battery-care-compatibility.sh
bash -n tests/test-battery-care-annotated-range.sh
bash -n tests/test-battery-care-thinkpad-readback.sh
bash -n tests/test-battery-care-multibattery.sh
```

Expected: all exit 0.

- [ ] **Step 2: Run ShellCheck on touched Bash files/tests**

```bash
shellcheck config/hypr/scripts/quickshell_battery_care.sh \
  local/libexec/awtarchy/power-profile-helper \
  tests/test-battery-charge-limit-detection.sh \
  tests/test-battery-care-compatibility.sh \
  tests/test-battery-care-annotated-range.sh \
  tests/test-battery-care-thinkpad-readback.sh \
  tests/test-battery-care-multibattery.sh
shellcheck -e SC2016 tests/test-battery-care-control.sh
```

Expected: no new actionable warnings.

- [ ] **Step 3: Run complete focused Battery Care regression set**

```bash
bash tests/test-battery-charge-limit-detection.sh
bash tests/test-battery-care-control.sh
bash tests/test-battery-care-compatibility.sh
bash tests/test-battery-care-annotated-range.sh
bash tests/test-battery-care-thinkpad-readback.sh
bash tests/test-battery-care-multibattery.sh
bash tests/test-battery-health-fallback.sh
bash tests/test-power-profile-helper-update.sh
bash tests/test-power-profile-inline-auth.sh
```

Expected: PASS.

- [ ] **Step 4: Run repository integrity checks relevant to the branch**

```bash
git diff --check main...HEAD
```

Run the repository's normal validation workflow commands that are practical in the execution environment. If GitHub CI is available only after PR creation, do not claim full CI until those exact workflow runs complete.

- [ ] **Step 5: Compare final branch against base**

Review:

```bash
git diff --stat main...HEAD
git diff main...HEAD -- \
  config/hypr/scripts/quickshell_battery_care.sh \
  config/quickshell/awtarchy/BatteryCareCard.qml \
  local/libexec/awtarchy/power-profile-helper \
  tests/test-battery-charge-limit-detection.sh \
  tests/test-battery-care-control.sh \
  tests/test-battery-care-compatibility.sh \
  .github/workflows/validate-awtarchy.yml
```

Confirm there is no unrelated refactor or stable-release mutation.

- [ ] **Step 6: Update issue #147 with verified findings**

Record:

- current LG correction from selector `1` to literal `80`;
- detector/helper fail-closed parity;
- Lenovo/Tuxedo BAT1 behavior;
- complete simulated plugin classification coverage;
- exact test commands/results;
- explicit note that simulations validate Awtarchy logic but do not claim physical validation on every laptop.

- [ ] **Step 7: Open PR for review**

Use title:

```text
Harden Battery Care across TLP vendor plugins
```

PR body must reference `#147`, summarize safety changes, list confirmed defects fixed, and include exact validation evidence. Do not merge until explicitly approved by the maintainer.
