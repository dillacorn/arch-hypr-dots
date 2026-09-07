# Awtarchy v3.5.6 Quickshell

Awtarchy v3.5.6 simplifies Battery Care by making TLP the hardware and compatibility authority while keeping Awtarchy's Quickshell controls as a thin generic client. It also includes conservative battery telemetry hardening, bounded clipboard thumbnail rendering, and diagnostics for the still-unresolved Bluetooth resume issue.

## Install and update

Fresh installation: [INSTALL.md](https://github.com/dillacorn/awtarchy/blob/main/INSTALL.md)

Existing Awtarchy installations and stable updates: [UPDATING.md](https://github.com/dillacorn/awtarchy/blob/main/UPDATING.md)

Quick update:

```bash
awtarchy update
```

## Battery Care

- TLP now owns vendor/plugin detection, supported threshold values, hardware quirks, validation, and battery writes.
- Awtarchy's Quickshell Battery Care UI remains as a generic client for numeric ranges and percentage presets explicitly advertised by TLP.
- Awtarchy persists only standard TLP threshold settings in its owned `/etc/tlp.d/00-awtarchy-battery-care.conf` drop-in and applies them through TLP.
- Selector-style and other hardware-specific modes stay read-only in Awtarchy and can be managed through TLPUI instead of duplicating TLP's hardware policy.
- TLPUI uses Arch's normal repository package path alongside TLP after resolving the `power-profiles-daemon` conflict.

## Real-hardware fixes

- Battery Care policy verification now handles protected root-only `/etc/sudoers.d` directories correctly without weakening owner, mode, symlink, marker, or `visudo` checks.
- Stop-only TLP interfaces can use TLP's normalized logical threshold readback when no standard `power_supply` stop-threshold file exists, while still rejecting values outside TLP's advertised range or presets.
- Real Sony hardware with TLP 1.10.2 was validated with full charging restored at logical 100%/off and with the 80% preset enabled.

## Other maintenance

- Battery telemetry is conservative around dead or phantom packs and falls back to normal UPower state whenever raw evidence is insufficient.
- Clipboard thumbnails retain first-frame rendering, bounded ImageMagick memory/map/disk resources, and timeout protection.
- A one-run suspend/resume diagnostic collector is included for Bluetooth issue #146. It is observational only; v3.5.6 does not claim to fix the intermittent Bluetooth resume behavior.

## Validation

- Exact release target: `1295e13b9323463b735f1793e5251ca4a2529eef`.
- Battery Care PR #156 passed all 22 pull-request workflows on exact reviewed head `00db570a85a5616a4309c398d7e06dee9228da85`.
- Final full-charge and 80% Battery Care states were validated on real Sony hardware before merge.
- All 10 push workflows for the exact merged release target completed successfully, including the full `Validate Awtarchy` integration suite.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.5.6._
