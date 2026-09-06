# TLP Battery Care Thin Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve Awtarchy's Quickshell Battery Care UI while delegating battery hardware compatibility and validation entirely to TLP.

**Architecture:** Quickshell consumes a normalized, generic `tlp-stat -b` model. The privileged helper persists standard TLP threshold settings and invokes TLP, but contains no vendor/plugin policy or hardware read-back semantics. TLPUI remains a sibling client of the same TLP configuration rather than an API dependency.

**Tech Stack:** Bash, QML/Quickshell, TLP 1.10.x CLI/status interfaces, Arch Linux package management, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-06-tlp-battery-care-thin-client-design.md`

## Global Constraints

- Start from `main` commit `07dd758e8d81fe3379c63739388581688254f659`.
- Do not modify Bluetooth issue #146 behavior or diagnostics.
- Never write battery sysfs directly; hardware writes remain TLP-mediated.
- Preserve `/etc/tlp.d/00-awtarchy-battery-care.conf` as Awtarchy's owned persistence boundary.
- Never silently overwrite threshold configuration from any other TLP config file.
- No Awtarchy Battery Care code may branch on a TLP plugin/vendor name for write policy.
- TLP command success/failure is authoritative; no vendor-specific hardware read-back verifier remains.
- Use GitHub Actions as the executable test environment because the current sandbox cannot resolve GitHub for a local clone.

---

### Task 1: Replace vendor compatibility policy with a generic TLP contract

**Files:**
- Modify: `tests/test-battery-care-compatibility.sh`
- Modify later after RED: `config/hypr/scripts/quickshell_battery_care.sh`
- Modify later after RED: `local/libexec/awtarchy/power-profile-helper`

**Interfaces:**
- Consumes: `tlp-stat -b` fields `Supported features`, `START_CHARGE_THRESH_*`, `STOP_CHARGE_THRESH_*`.
- Produces: existing detector JSON shape with generic `supported`, `writable`, `backend`, `mode`, range/preset data, managed/config-conflict state.

- [ ] **Step 1: Rewrite the compatibility regression first**

The test must assert:

```text
- detector/helper contain no battery_plugin_writable allowlist
- a fictional plugin `future-vendor` advertising STOP 50..100 is supported+writable+range
- `generic` with no battery-care feature remains unsupported
- numeric capability is determined by TLP output rather than plugin identity
```

- [ ] **Step 2: Open/update a draft PR and verify GitHub Actions fails for the expected old allowlist/future-plugin behavior**

Expected: focused battery compatibility job fails because current code marks `future-vendor` non-writable and still contains `battery_plugin_writable()`.

- [ ] **Step 3: Simplify the detector minimally**

Remove:

```text
battery_plugin_writable()
SONY_BATTERY_CARE_PATH fallback
plugin-name mode cases
Lenovo/Samsung/Sony/Huawei state decoding
sysfs threshold fallback as a writable/capability source
```

Keep only TLP-advertised generic range/preset parsing, Awtarchy managed config state, conflict detection, and display-only plugin text.

- [ ] **Step 4: Run CI and verify the compatibility test passes before moving to helper writes**

Expected: detector-side generic compatibility regression is green; helper-side test may remain red until Task 2.

### Task 2: Make privileged writes generic and TLP-authoritative

**Files:**
- Modify: `tests/test-battery-care-control.sh`
- Modify: `local/libexec/awtarchy/power-profile-helper`

**Interfaces:**
- Consumes: generic TLP start/stop specs immediately before each write.
- Produces: `battery-set <percentage>` and `battery-disable`; removes `battery-enable-fixed`.

- [ ] **Step 1: Rewrite helper tests before production code**

Cover:

```text
future-vendor + 50..100 range -> accepted
stop-only spec -> START=0
range/list start spec -> generic valid start chosen below stop
invalid requested target -> rejected before config replacement
TLP start failure -> previous managed drop-in restored
successful TLP start + transformed/different read-back -> still succeeds
external config -> fail closed
selector-only 0..1 spec -> no percentage write path
```

- [ ] **Step 2: Verify RED in GitHub Actions**

Expected: current helper fails the future-plugin case and still contains plugin translations/read-back verification.

- [ ] **Step 3: Replace helper plugin policy with generic parsing**

Delete plugin allowlists, per-plugin translations, `battery_dual_config_plugin()`, `verify_enabled_state()`, `verify_disabled_state()`, and plugin-specific rollback verification.

`battery-set` must:

```text
read tlp-stat -b
validate generic numeric STOP spec
derive START only from advertised generic START spec
write Awtarchy drop-in
run tlp start
rollback the drop-in and re-run tlp start if TLP fails
```

`battery-disable` must remove only the Awtarchy drop-in, apply remaining TLP configuration, and use TLP's full-charge operation only as a generic temporary full-charge action when appropriate.

- [ ] **Step 4: Verify helper tests and compatibility tests green**

### Task 3: Remove plugin policy from Quickshell while preserving the UI

**Files:**
- Modify: `tests/test-battery-care-detector-profiles.sh`
- Modify: `config/quickshell/awtarchy/BatteryCareCard.qml`
- Modify: `tests/test-battery-care-sony-unprivileged.sh`

**Interfaces:**
- Consumes: generic detector range/preset/managed/conflict fields.
- Produces: existing Battery Care card with percentage slider/presets where TLP exposes numeric targets; read-only advanced/TLPUI fallback otherwise.

- [ ] **Step 1: Change UI/profile tests first**

Required assertions:

```text
future-vendor numeric range behaves identically to a known plugin
0..1 selector-only stop spec is read-only/advanced rather than exposed as 1%
QML has no pluginName/fixedUnknownTarget/battery-enable-fixed policy
unavailable privileged TLP report does not resurrect capability from Sony-specific sysfs
```

- [ ] **Step 2: Verify RED**

Expected: current detector/QML fail because they special-case plugin names and Sony sysfs.

- [ ] **Step 3: Simplify BatteryCareCard.qml**

`controlsAvailable` becomes generic TLP numeric capability + no conflict. Toggle OFF uses `battery-disable`; toggle ON uses `battery-set` with the selected generic target. Preserve visual layout and existing range/preset controls.

- [ ] **Step 4: Verify focused UI/detector tests green**

### Task 4: Install TLPUI from official Arch repositories without reintroducing installer policy

**Files:**
- Modify: `tests/test-quickshell-backend-readiness.sh`
- Modify: `local/share/awtarchy/awtarchy-power-profile.sh`
- Modify if connector editing permits exact safe replacement: `local/share/awtarchy/awtarchy-runtime.sh`
- Modify if runtime changes: `tests/test-installer-aur-scanner-delegation.sh`

**Interfaces:**
- Consumes: official Arch packages `tlp`, `tlp-pd`, `tlpui`.
- Produces: laptop power reconciler installs all three through pacman and records only newly installed packages as Awtarchy-managed.

- [ ] **Step 1: Add failing backend-readiness regression**

Require `tlpui` alongside `tlp` and `tlp-pd` in `install_laptop_backend()`.

- [ ] **Step 2: Verify RED**

Expected: current reconciler installs only `tlp` and `tlp-pd`.

- [ ] **Step 3: Add `tlpui` to the existing pacman-managed reconciler**

Use the same `newly_managed` and `record_managed` behavior as TLP/TLP-PD. Do not add a new installer subsystem.

- [ ] **Step 4: Remove the obsolete runtime AUR-only `tlpui` install block if the exact large-file target can be updated safely through available GitHub tooling**

If the connector cannot replace the large runtime file without reconstructing unrelated content, do not perform a partial/unsafe replacement. Keep the now-redundant block temporarily and report that exact limitation; because pacman reconciliation installs `tlpui` first, the old block must only encounter an already-installed package before it can invoke AUR tooling. Verify actual call order before relying on this.

### Task 5: Retire obsolete vendor regression files and align CI/managed history

**Files:**
- Modify as required: `.github/workflows/validate-awtarchy.yml`
- Modify as required: `local/share/awtarchy/quickshell-managed-history.sha256`
- Modify: `AGENTS.md` only if current architecture guidance needs the new ownership boundary recorded.

- [ ] **Step 1: Search CI for every affected focused battery test and ensure generic replacements remain permanently run**
- [ ] **Step 2: Update managed-history hashes only through the repository's established managed-history procedure/tests**
- [ ] **Step 3: Run/inspect all PR CI checks**

Required final evidence:

```text
battery compatibility tests: pass
battery control tests: pass
detector profile tests: pass
battery status-helper tests: pass
power-profile/backend readiness tests: pass
installer tests: pass
bash -n coverage: pass
shellcheck coverage where configured: pass
managed-history/updater tests: pass
full validate-awtarchy workflow: pass
```

- [ ] **Step 4: Review diff for forbidden vendor ownership**

Search changed Battery Care production files for plugin-name cases and direct battery sysfs writes. Any remaining vendor branch must be either display-only evidence or removed before completion.

- [ ] **Step 5: Leave branch/PR unmerged unless the maintainer explicitly requests merge for this refactor**
