# TLP Battery Compatibility Hardening Design

## Scope

Harden Awtarchy Battery Care so arbitrary laptop hardware is handled according to the exact TLP battery plugin semantics instead of broad numeric assumptions. The work is based on current `main` at `eb0f9bf39c87fa97d0948b87be00220d1a8ba4be` and tracks issue #147.

This is not a laptop-model database. TLP remains the hardware/vendor compatibility authority. Awtarchy consumes TLP's plugin identity, advertised ranges/presets, and read-back state, then enables writes only for plugin semantics Awtarchy explicitly understands.

## Safety model

Battery writes remain root-owned and TLP-mediated. Quickshell and user-writable scripts never write battery sysfs directly.

A write is allowed only when all of the following are true:

1. TLP reports battery-care capability.
2. The exact TLP plugin is in Awtarchy's validated writable compatibility set.
3. The requested target is valid for that plugin's upstream TLP semantics.
4. No external user-managed TLP threshold configuration conflicts with Awtarchy's managed file.
5. TLP applies the requested state successfully.
6. Plugin-specific read-back verification confirms the resulting hardware state.

On write or verification failure, keep the existing rollback behavior.

Unknown future TLP plugins must fail closed. Awtarchy may report that TLP detected battery-care capability, but it must not expose active write controls until the plugin semantics are understood and covered by tests.

## Trust boundary

The compatibility policy exists on both sides of a deliberate trust boundary:

- `config/hypr/scripts/quickshell_battery_care.sh` is user-owned read-only detection/UI data.
- `local/libexec/awtarchy/power-profile-helper` becomes root-owned when installed and is the authority for privileged writes.

Do not make the root helper source or execute a user-writable compatibility file merely to avoid duplication. Keep small explicit plugin cases in both files and add regression coverage that enforces parity between the detector and helper writable plugin sets.

## Detector contract

Extend the detector output with explicit write eligibility rather than overloading `supported`:

- `supported`: a battery-care interface/capability was detected.
- `writable`: Awtarchy has validated semantics for this exact backend and may expose write controls.
- `compatibility`: one of `validated`, `unvalidated`, or `unsupported`.

Expected states:

```text
Known validated TLP plugin
    supported=true
    writable=true
    compatibility=validated

Unknown TLP plugin with battery-care features
    supported=true
    writable=false
    compatibility=unvalidated

TLP generic / no battery-care feature
    supported=false
    writable=false
    compatibility=unsupported

Kernel/sysfs threshold information without a validated TLP write path
    supported=true
    writable=false
    compatibility=unvalidated
```

`BatteryCareCard.qml` must require `writable=true` in addition to its existing backend/config checks before enabling controls. The backend/plugin identity and detector detail remain visible so unsupported hardware fails clearly instead of silently disappearing.

## Current upstream TLP compatibility profiles

The current upstream TLP `bat.d/` plugin surface is the source of truth. Awtarchy should classify current plugins as follows.

### Validated normal/range semantics

These use ordinary stop-threshold percentages, with plugin-specific start rules derived from TLP's advertised range or `don't care` wording:

- `asus`: stop `1..100`; stop-only semantics.
- `cros-ec`: stop `1..100`; start `0..99` when supported.
- `dell`: start `50..95`, stop `55..100`.
- `huawei`: start `0..99`, stop `1..100`; read-back uses the Huawei threshold pair.
- `msi`: stop `10..100`; start is hardware-enforced as stop minus 10.
- `system76`: start `0..99`, stop `1..100`.
- `thinkpad`: start `0..99`, stop `1..100`; preserve the existing firmware read-back quirk handling for enabled state.
- `thinkpad-legacy`: start `2..96`, stop `6..100`; preserve the existing non-exact enabled-state verification behavior.
- `wilco-ec`: start `50..95`, stop `55..100`.

### Validated preset/fixed-percentage semantics

- `macbook`: stop `80` or `100`; hardware controls the corresponding start behavior.
- `sony`: stop `50`, `80`, or logical `100(off)`; raw `sony_laptop` read-back `0` means logical `100/off`.
- `tuxedo`: dynamic discrete start/stop sets reported by TLP, commonly start `40/50/60/70/80/95` and stop `60/70/80/90/100`.
- `lg`: stop `80(on)` or `100(off)` on current upstream TLP.
- `toshiba`: stop `80(on)` or `100(off)`.

### Validated selector/boolean semantics

These must not be treated as ordinary percentages internally:

- `lenovo`: `0 = Standard`, `1 = Long_Life` through `charge_types`.
- `lenovo-legacy`: `0 = off`, `1 = on` through `conservation_mode`.
- `samsung`: `0 = off/100%`, `1 = on/80%` through `battery_life_extender`.

### Unsupported/fail-closed

- `generic`: TLP's catch-all explicitly reports no battery-care features and provides no threshold writes.
- `lg-legacy`: current upstream TLP has removed this plugin. Awtarchy must not keep advertising it as a current validated writable backend. If an old TLP installation reports it, treat it as unvalidated/fail-closed unless a separately verified legacy compatibility path is intentionally restored later.
- Any new plugin name not listed above: detected but unvalidated, no writes.

## Verified current defects to correct

### Current LG write translation is wrong for current TLP

Current Awtarchy treats `lg` and `lg-legacy` together and translates an 80% target to `STOP_CHARGE_THRESH_BAT0=1`.

Current upstream TLP's `lg` plugin validates and writes literal stop values `80` and `100`. The existing test fixture incorrectly models current `lg` as a selector backend, so it currently protects the wrong behavior.

Fix:

- current `lg` writes literal `80` for the health limit;
- OFF continues through TLP's full-charge/default path and verifies `100`;
- remove current writable support for `lg-legacy` rather than applying current `lg` semantics to an obsolete plugin.

### Dual-battery config coverage is incomplete

Current Awtarchy writes BAT1 config for several dual-battery plugins, but current upstream TLP also uses per-battery `BAT0/BAT1` config suffixes for at least:

- `lenovo`
- `tuxedo`

Add those to Awtarchy's dual-config policy so both batteries receive the managed state where TLP exposes both.

Keep shared/single-config backends such as Sony, Samsung, LG, Lenovo legacy, MacBook, Huawei, System76, and Wilco EC on their upstream-defined config behavior.

### Detector/helper support policy can disagree

The detector currently treats TLP feature strings as enough to mark a plugin writable, while the privileged helper has its own explicit allowlist. A new TLP plugin can therefore appear writable in Quickshell and then be rejected by the helper.

Fix:

- detector and helper each expose an explicit validated writable plugin set;
- tests compare the two sets for exact parity;
- unknown plugins remain visible as unvalidated but controls are disabled.

## Write-path behavior

### Percentage/range plugins

Keep the existing TLP-advertised range/preset parsing. Derive start thresholds only where TLP reports an actual start range/list. For `don't care`/stop-only plugins, keep a neutral config value only where TLP ignores that parameter; tests must validate the resulting TLP path rather than assuming all plugins consume both thresholds.

### Selector plugins

Keep explicit translations:

- Lenovo/Lenovo legacy enable -> selector `1`.
- Samsung 80% -> selector `1`.
- Disable -> TLP `fullcharge`/vendor default path, followed by selector-specific OFF verification.

### OFF handling

Do not infer OFF globally from `value >= 100` when a plugin has special raw semantics.

Required explicit OFF verification remains:

- Lenovo -> `Standard`.
- Lenovo legacy -> `conservation_mode=0`.
- Samsung -> `battery_life_extender=0`.
- Huawei -> stop component `100`.
- Sony -> raw `battery_care_limiter=0`.

Ordinary percentage plugins may use `100` read-back when that is the upstream TLP default/off state.

## UI behavior

`BatteryCareCard.qml` should not gain laptop-model logic. It consumes normalized detector output only.

Controls are enabled when:

```text
supported && writable && backend == tlp && !config_conflict
```

plus the existing requirement that the normalized mode has a usable fixed/preset/range control.

Unknown/unvalidated plugin example:

```text
TLP · <plugin>
Battery Care detected but not validated by Awtarchy
Write controls are disabled for this backend.
```

Generic/no-capability hardware remains unavailable rather than presenting a broken toggle.

## Regression strategy

Keep existing `tests/test-battery-care-control.sh`, but correct its LG fixture so it models current upstream TLP rather than selector semantics.

Add a focused table-driven compatibility test, preferably `tests/test-battery-care-compatibility.sh`, that covers every current upstream plugin classification without requiring physical hardware.

The test must verify:

1. Detector/helper writable plugin-set parity.
2. Unknown plugin with `charge threshold` features is visible but non-writable.
3. `generic` is unsupported/non-writable.
4. Detector mode/target normalization for each profile family.
5. Current LG applies literal `80`, not selector `1`.
6. Lenovo and Tuxedo managed config includes BAT1 where applicable.
7. Sony OFF raw `0` remains accepted.
8. Lenovo, Lenovo legacy, Samsung, Huawei, and ThinkPad special verification stays covered.
9. Tuxedo discrete start selection chooses an advertised value below the selected stop target.
10. Failure/read-back mismatch still rolls back the previous managed configuration.

The tests are simulations of TLP's documented/upstream semantics. They prove Awtarchy's parsing, authorization, translation, and rollback decisions. They do not claim every BIOS/EC/kernel implementation has been physically validated.

## CI

Add the focused compatibility test to the same validation area that already runs `test-battery-charge-limit-detection.sh`, `test-battery-care-control.sh`, and `test-battery-care-annotated-range.sh`. Include Bash syntax and ShellCheck coverage consistent with the existing workflow.

## Files expected to change

- `config/hypr/scripts/quickshell_battery_care.sh`
- `config/quickshell/awtarchy/BatteryCareCard.qml`
- `local/libexec/awtarchy/power-profile-helper`
- `tests/test-battery-care-control.sh`
- new focused battery compatibility test under `tests/`
- `.github/workflows/validate-awtarchy.yml`
- managed-history data only if the normal Awtarchy managed-file rules require it for the changed release-managed QML/script surfaces; inspect updater tests before touching it.

Do not modify the published v3.5.4 tag or add another v3.5.4 post-release bridge as part of this branch. This work is unreleased hardening on `main` ancestry unless the maintainer separately requests stable-release delivery.

## Acceptance criteria

- Every current upstream TLP battery plugin is explicitly classified.
- Current validated plugin names match between detector and privileged helper.
- Unknown future plugin names cannot expose writable Quickshell controls.
- `generic` remains unavailable/non-writable.
- Current LG uses upstream `80/100` semantics.
- Lenovo and Tuxedo dual-battery configuration matches TLP's BAT0/BAT1 behavior.
- Existing Sony raw-0 OFF behavior remains fixed.
- All privileged writes remain TLP-mediated, verified, and rollback-capable.
- Focused battery tests and relevant repository CI pass before the branch is proposed for merge.
