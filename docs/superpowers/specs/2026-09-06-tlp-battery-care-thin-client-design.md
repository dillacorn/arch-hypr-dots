# TLP Battery Care Thin Client Design

## Scope

Keep Awtarchy's existing Quickshell Battery Care experience while removing Awtarchy's responsibility for laptop-vendor battery compatibility semantics.

TLP is the authority for battery-care capability, allowed threshold values, vendor-specific translations, kernel/EC quirks, and actual hardware writes. Awtarchy remains a UI/integration client.

This work starts from `main` commit `07dd758e8d81fe3379c63739388581688254f659`. Bluetooth issue #146 remains separate and must not be changed by this branch.

## Ownership boundary

### TLP owns

- battery plugin/vendor detection;
- whether charge thresholds or charge types are supported;
- allowed start/stop values reported by `tlp-stat -b`;
- validation of requested threshold values;
- vendor-specific conversion and kernel/sysfs writes;
- application of configured thresholds through `tlp start` / `tlp setcharge` / `tlp fullcharge`;
- future hardware support and compatibility fixes.

### Awtarchy owns

- the Quickshell Battery Care card and its normalized UI model;
- a small parser for stable/generic `tlp-stat -b` fields needed by the UI;
- persistence of standard TLP `START_CHARGE_THRESH_BATx` / `STOP_CHARGE_THRESH_BATx` settings;
- invoking TLP and surfacing its success/failure;
- preserving user configuration and refusing ambiguous/conflicting ownership;
- ordinary battery telemetry and health UI, which are separate from Battery Care writes.

Awtarchy must not contain an allowlist of TLP battery plugin names or vendor-specific write/read-back branches.

## TLPUI relationship

TLPUI is not a daemon or API and must not be imported as an internal Python dependency. Instead, Quickshell and TLPUI are sibling clients of the same TLP configuration and status interfaces.

TLPUI currently reads effective TLP configuration with `tlp-stat -c`, consumes TLP's configuration schema when available, and saves standard TLP configuration. Awtarchy should therefore persist only ordinary TLP configuration values that TLPUI can also display/edit.

`tlpui` is currently an official Arch `extra` package and must be installed through the normal pacman package path on laptops, not through AUR scanning.

## Configuration ownership

Retain a dedicated Awtarchy drop-in under `/etc/tlp.d/00-awtarchy-battery-care.conf` rather than editing `/etc/tlp.conf` directly.

Reasoning:

- `/etc/tlp.d/*.conf` is a documented TLP configuration surface;
- TLPUI's effective-config model understands drop-ins;
- a dedicated file gives Awtarchy a precise ownership boundary and safe removal/rollback target;
- editing `/etc/tlp.conf` would require rewriting a user-owned file and create unnecessary conflict risk.

If any other TLP config file already defines `START_CHARGE_THRESH_BAT*` or `STOP_CHARGE_THRESH_BAT*`, Awtarchy write controls fail closed rather than overriding user/TLPUI-managed threshold policy.

## Status model

The read-only detector consumes authoritative `tlp-stat -b` output through the existing root-owned battery-status helper when needed.

It may parse only generic TLP concepts:

- `Plugin:` for display/debug text only, never policy;
- `Supported features:`;
- advertised `START_CHARGE_THRESH_*` and `STOP_CHARGE_THRESH_*` parameter specifications;
- battery names exposed in TLP's battery status sections;
- generic reported current threshold values where TLP exposes them;
- Awtarchy's own managed target metadata/config ownership.

The detector must not read vendor-specific sysfs paths or interpret fields such as Lenovo `charge_types`, Samsung `battery_life_extender`, Sony `battery_care_limiter`, Huawei pairs, or vendor plugin names.

### Normalized UI modes

Awtarchy may normalize TLP's advertised stop specification into only these generic modes:

- `range`: TLP advertises a numeric range;
- `presets`: TLP advertises multiple numeric values;
- `unsupported`: TLP does not advertise a usable charge-threshold setting.

Selector/fixed vendor modes that cannot be represented by standard percentage values are not reimplemented. The UI may show TLP Battery Care as available but direct the user to TLPUI for advanced/vendor-defined modes instead of adding Awtarchy compatibility code.

## Write path

For a percentage target:

1. Re-read `tlp-stat -b` as root immediately before the write.
2. Require TLP to advertise charge-threshold capability and a usable stop specification.
3. Reject conflicting external threshold configuration.
4. Derive a generic start value only from TLP's advertised start specification:
   - if TLP reports no usable start control, use `0`, which TLP documents as the vendor default/disabled value;
   - for a numeric range/list, choose the highest valid advertised start value below the requested stop, preferring approximately five percentage points below where possible.
5. Write ordinary TLP `START_CHARGE_THRESH_BATx` and `STOP_CHARGE_THRESH_BATx` values for battery names TLP actually reports. Do not infer BAT0/BAT1 from vendor identity.
6. Run `tlp start` and trust its exit status/validation. Do not duplicate plugin-specific hardware read-back verification.
7. Re-run `tlp-stat -b` for UI refresh/debug status only. Do not reject a successful TLP operation because firmware reports a vendor-specific transformed value.

TLP itself documents that `tlp setcharge` validates configuration and that some hardware reports values differently from what was written. Therefore Awtarchy must not second-guess successful TLP writes with its own vendor-specific verifier.

## Disable path

Disabling Awtarchy Battery Care removes only Awtarchy's managed drop-in and asks TLP to restore/apply its remaining effective configuration.

Use `tlp fullcharge` only as the temporary hardware action needed to permit full charge when no remaining configured threshold policy exists. Do not encode vendor-specific OFF values.

If external threshold configuration exists, Awtarchy must not claim that Battery Care is globally disabled; the remaining TLP/TLPUI policy is authoritative.

## Quickshell behavior

Preserve the existing Battery Care card layout and normal percentage slider/preset interaction as far as TLP's advertised numeric interface supports it.

Remove UI policy based on `pluginName`, including Lenovo-specific fixed-mode handling. `controlsAvailable` depends only on normalized generic capability, TLP availability, and config ownership/conflict state.

When TLP reports Battery Care but not a generic numeric control, show a concise read-only state such as:

`Advanced Battery Care is available through TLP/TLPUI.`

Do not invent a generic toggle for vendor-defined selector modes.

## Authentication

Do not expand this refactor into a new authentication architecture. Preserve the existing privileged-helper boundary for this branch unless current tests prove it must change for correctness.

A separate change can migrate Battery Care authorization to the project's PolicyKit agent if desired.

## Package integration

On laptop installs:

- `tlp`, `tlp-pd`, and `tlpui` are official repository packages;
- install them through pacman's normal repository package flow;
- remove the special AUR-scanner installation path for `tlpui` and update its installer regression test accordingly.

## Migration

Existing `/etc/tlp.d/00-awtarchy-battery-care.conf` files remain valid standard TLP drop-ins. Do not delete them merely because the backend implementation is simplified.

The new detector should read the managed file without relying on old vendor metadata. If a legacy managed file contains standard threshold assignments, preserve it and allow TLP to interpret it.

## Tests

Use TDD. Replace vendor-matrix tests with contract tests against TLP's generic interface.

Required coverage:

1. numeric range advertised by TLP -> Quickshell range control;
2. numeric preset list -> preset control;
3. stop-only interface -> generic target with start `0`;
4. no charge-threshold capability -> controls unavailable;
5. unknown/future plugin name with valid generic range -> works without code changes;
6. vendor/fixed/selector output without a numeric percentage spec -> read-only/TLPUI fallback, not a new Awtarchy branch;
7. TLP rejects an invalid/application request -> helper reports failure and preserves/restores the previous Awtarchy drop-in;
8. successful `tlp start` is authoritative even if read-back differs from the requested numeric value;
9. reported battery names determine which `BATx` config keys are written;
10. external threshold config remains a fail-closed conflict;
11. existing Awtarchy managed drop-in remains compatible;
12. `tlpui` is installed as an official repository package rather than via AUR scanner.

Tests simulating specific vendors may remain only when they exercise a generic TLP contract. They must not assert that Awtarchy has special code for that vendor.

## Expected removals

Delete or retire code whose only purpose is Awtarchy-owned hardware compatibility, including:

- plugin writable allowlists;
- per-plugin write translations;
- per-plugin dual-battery lists;
- per-plugin enabled/OFF verification;
- Sony direct sysfs fallback;
- Lenovo/Samsung/Huawei/etc. state parsing;
- tests whose purpose is parity of Awtarchy vendor tables.

## Acceptance criteria

- Quickshell Battery Care remains usable for TLP-advertised numeric threshold hardware.
- A new TLP plugin with the same generic numeric interface requires no Awtarchy code change.
- No privileged or unprivileged Battery Care code branches on a vendor/plugin name for write policy.
- All battery hardware writes go through TLP.
- TLP's success/failure is authoritative; Awtarchy does not maintain firmware-specific read-back rules.
- Existing user-managed TLP threshold configuration is never silently overwritten.
- TLPUI sees the same effective standard TLP settings Awtarchy manages.
- `tlpui` installs from Arch `extra` through the repository package path.
- Bluetooth issue #146 and its diagnostic behavior remain unchanged.
- Focused battery tests, installer tests, Bash syntax checks, ShellCheck where available, managed-history validation, and repository CI pass before merge.