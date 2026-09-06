# Awtarchy v3.5.6 Quickshell

Awtarchy v3.5.6 is primarily an architectural correction to Battery Care. It deliberately backs away from the large Awtarchy-maintained TLP vendor/plugin compatibility layer introduced in v3.5.5 and returns hardware compatibility ownership to TLP, where it belongs.

## Existing Awtarchy users

```bash
awtarchy update
```

## Why Battery Care is changing again

v3.5.5 expanded Awtarchy's own Battery Care backend logic to understand current TLP vendor plugins, firmware-specific OFF values, selector modes, readback quirks, multi-battery translations, and other hardware behavior.

That worked, but it also made Awtarchy a second battery-hardware policy engine beside TLP. Every new laptop quirk or TLP plugin change could then require another Awtarchy compatibility update. That is unnecessary maintenance and increases the chance that Awtarchy and upstream TLP disagree about the same hardware.

v3.5.6 intentionally backpedals on that design.

- **TLP remains the battery hardware backend and compatibility authority.** TLP owns vendor/plugin detection, valid threshold values, hardware quirks, validation, and writes.
- **Awtarchy's Quickshell Battery Care UI remains.** It is now a thin generic client for numeric charge-threshold controls that TLP explicitly advertises.
- **TLPUI is installed as the advanced sibling UI**, not imported as an Awtarchy backend or library. Hardware-specific selector/advanced modes that do not map cleanly to generic percentages are left to TLP/TLPUI instead of being reimplemented in Awtarchy.
- Awtarchy persists only standard TLP threshold settings in its owned `/etc/tlp.d/00-awtarchy-battery-care.conf` drop-in and asks TLP to apply them with `tlp setcharge`.
- The old special AUR path for `tlpui` is gone. `tlp`, `tlp-pd`, and `tlpui` are installed through Arch's normal repository package path after the `power-profiles-daemon` conflict is resolved.

This keeps the polished Quickshell controls while removing hardware compatibility administration that upstream TLP is already designed to own.

## Battery Care behavior

- Generic TLP-advertised numeric ranges and percentage presets remain writable from Quickshell without checking a vendor/plugin allowlist.
- Future TLP plugins exposing the same generic percentage interface can work without an Awtarchy vendor-specific code change.
- TLP `charge type` and other selector-style modes remain read-only in Awtarchy and can be managed through TLPUI.
- Stop-only interfaces use TLP's generic semantics, including `START_CHARGE_THRESH=0` where no usable start control is advertised.
- Standard TLP configuration suffixes are derived from TLP's advertised parameter names rather than guessed from vendor identity or physical battery names.
- External user/TLPUI threshold configuration still fails closed instead of being silently overwritten.
- Multi-battery handling remains conservative, and full-charge recovery attempts every TLP-reported physical battery.
- All Battery Care hardware writes go through TLP; Awtarchy no longer writes vendor-specific battery sysfs controls directly or tries to second-guess successful TLP writes with its own firmware-specific verifier.

## Real-hardware fixes found during testing

Two issues were found only after testing the refactor on real Arch/Sony hardware and were fixed before release.

### Protected sudoers directories

Awtarchy's read-only `tlp-stat -b` helper policy was valid, but the post-install verifier tried to inspect `/etc/sudoers.d/awtarchy-battery-status-*` as the desktop user. On a correctly protected root-owned `0750` `/etc/sudoers.d`, that user cannot traverse the directory, so installation falsely failed.

Policy-file inspection now uses the existing root boundary while retaining the owner, mode, symlink, marker, and `visudo` safety checks. The existing-policy guard is root-aware too, so a foreign policy cannot be hidden by directory permissions and accidentally replaced.

### Stop-only TLP logical readback

Some hardware exposes its logical applied threshold in TLP's Battery Care report without a standard `power_supply` stop-threshold file. Awtarchy previously showed `Unknown` or a generic `On` state in that case.

The detector can now consume TLP's normalized logical percentage from the generic Battery Care report, but only when the value matches TLP's advertised range/presets. It does not interpret the vendor path or raw hardware encoding.

Real Sony hardware with TLP 1.10.2 was validated at both ends:

- full charging restored -> Awtarchy normalized `target=100`, `enabled=false`;
- 80% selected -> TLP reported `80%`, the managed drop-in used `START_CHARGE_THRESH_BAT0=0` and `STOP_CHARGE_THRESH_BAT0=80`, and Awtarchy normalized `target=80`, `enabled=true`.

## Other maintenance included since v3.5.5

- Battery telemetry was centralized and hardened to avoid treating dead/phantom battery reports as real usable packs without sufficient evidence.
- Clipboard thumbnail rendering keeps the v3.5.5 post-release resource hardening: first-frame rendering, bounded ImageMagick resources, and timeout protection.
- A one-run Bluetooth suspend/resume diagnostic collector is included for issue #146. It is observational only; v3.5.6 does **not** claim to fix the intermittent Bluetooth resume behavior because the real failure has not reproduced reliably enough to justify a behavioral patch.

## Validation

- Exact release target: `1295e13b9323463b735f1793e5251ca4a2529eef`.
- PR #156 passed all 22 pull-request workflows on exact reviewed head `00db570a85a5616a4309c398d7e06dee9228da85`.
- The final Battery Care states were validated on real Sony hardware before merge.
- All 10 push workflows for the exact merged release target completed successfully. `Validate Awtarchy` passed Bash syntax, ShellCheck, desktop-entry validation, and the complete command/updater integration suite on its verification rerun.
- Battery Care CI covers generic future plugins, numeric ranges/presets, selector rejection, stop-only readback, protected sudoers policy handling, write rollback, multi-battery behavior, TLPUI package integration, managed-history migration, and the absence of Awtarchy vendor-specific write policy.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.5.6._
