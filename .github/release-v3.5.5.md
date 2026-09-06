# Awtarchy v3.5.5 Quickshell

Awtarchy v3.5.5 is a Battery Care compatibility and safety release. It rolls the tested Sony Battery Care OFF correction from the v3.5.4 post-release maintenance path into a new stable configuration release and hardens Battery Care across the current TLP vendor-plugin surface.

## Getting started

Awtarchy is an Arch Linux overlay/environment, not a Linux distribution or an Arch Linux installer. Install it onto a working minimal Arch Linux system.

If you are starting from zero:

1. Download the official Arch Linux ISO from the [Arch Linux download page](https://archlinux.org/download/).
2. Boot the Arch Linux ISO.
3. Install a working minimal Arch Linux system first.
   - For most users, Awtarchy recommends the official `archinstall` guided installer included with the Arch ISO as the easiest path. Run `archinstall` from the live environment and complete a minimal Arch installation.
   - A normal manual Arch installation using the [ArchWiki Installation Guide](https://wiki.archlinux.org/title/Installation_guide) is also fine.
4. Boot into the installed Arch system.

Once you have a working minimal Arch installation, install Awtarchy:

```bash
sudo pacman -S git --noconfirm
git clone https://github.com/dillacorn/awtarchy
cd awtarchy
sudo ./awtarchy-install.sh
```

## Existing Awtarchy users

```bash
awtarchy update
```

## Battery Care compatibility hardening

- Battery Care now treats TLP as the compatibility authority and explicitly separates detected capability from Awtarchy-validated write support.
- Current validated TLP vendor backends receive the appropriate controls; unknown future plugins remain visible as detected but non-writable until their semantics are reviewed.
- TLP `generic` and hardware without a validated battery-care interface remain unavailable for writes instead of being guessed from generic sysfs state.
- Sony `sony_laptop` raw `battery_care_limiter=0` remains normalized to logical `100% / off`, preserving the real-hardware-tested v3.5.4 post-release fix.
- Current LG behavior uses literal `80%` for Battery Care enabled and `100%` for disabled instead of the obsolete selector interpretation.
- Lenovo Standard/Long_Life charge types, Lenovo legacy conservation mode, Samsung battery-life extender behavior, Huawei paired thresholds, Tuxedo discrete targets, Toshiba fixed targets, MacBook presets, MSI hardware-managed start behavior, and ThinkPad readback quirks are normalized according to current upstream TLP interfaces.
- Writable support is independently enforced in both the unprivileged detector and the privileged helper so the UI cannot advertise a write path the helper does not understand.

## Multi-battery and recovery correctness

- Divergent BAT0/BAT1 charge limits now appear as an explicit mixed/indeterminate state instead of silently treating the first battery as authoritative.
- Per-battery threshold values remain visible when packs disagree, and restoring full charge can intentionally normalize the mixed state.
- Current Lenovo charge types are checked across every reported battery, so one successful pack cannot hide a failed second-pack write.
- Lenovo and Tuxedo managed configuration now writes the required BAT1 settings where applicable.
- Full-charge recovery attempts every reported battery even if an earlier pack fails, then returns failure if any pack could not be restored.
- Rollback now verifies the actual hardware state after restoring the previous configuration or full-charge defaults. A rollback is not reported as successful merely because the configuration file was restored.
- Unknown or unreadable current state is presented as `Unknown` rather than being fabricated as `Off`.

## Read-only TLP status and privilege hardening

- Current TLP requires privileged access for authoritative `tlp-stat -b` battery reporting, so Awtarchy now installs a dedicated root-owned read-only status helper.
- The status helper accepts zero arguments and executes only the fixed `/usr/bin/tlp-stat -b` command with a sanitized environment.
- Only that read-only helper receives a narrowly scoped passwordless sudo rule. Battery-setting operations remain behind the authenticated `power-profile-helper` write path.
- Quickshell uses non-interactive `sudo -n` for status reads, so opening the Battery Care UI cannot unexpectedly request a sudo password.
- The laptop power reconciler installs and repairs the helper and sudoers policy as root and verifies the protected policy without weakening its permissions.
- The sudoers account is derived from the real invoking UID rather than trusting a caller-controlled `$USER` environment variable.
- A stale installed status helper cannot make Battery Care appear writable after TLP itself has been removed; the detector fails closed when no authoritative TLP report is available.

## Managed update safety

- Current managed hashes for the changed Battery Care detector and Quickshell card are recorded so future stable updates can recognize shipped Awtarchy states correctly.
- Permanent CI now covers compatibility classification, current vendor profiles, write gating, multi-battery behavior, rollback verification, the read-only status helper, helper installation/repair, updater migration, and updater bootstrap.
- The published v3.5.4 tag remains unchanged; v3.5.5 publishes the audited Battery Care state from a new exact release target.

## Validation

- Exact release target: `609e5aebe02bd53460ebd80d3cd12993d4707744`.
- PR #148 passed all 19 pull-request workflows on exact reviewed head `e87f7b11413921f3b5e16b56ea56caec79e45f91`.
- Three consecutive hostile audit passes were completed against the frozen PR head after the discovered stale-status-helper and spoofed-`USER` privilege-boundary defects were fixed with RED/GREEN regressions.
- All nine push workflows completed successfully on exact merged release target `609e5aebe02bd53460ebd80d3cd12993d4707744`.
- `Validate Awtarchy` passed Bash syntax, ShellCheck, Quickshell desktop-entry validation, the full command/updater integration suite, Battery Care compatibility/vendor/multi-battery/rollback tests, helper install/repair tests, updater migration, and updater bootstrap on the merged release target.
- The Sony OFF path was separately validated on real Sony hardware with TLP 1.10.2: disabling Battery Care changed the raw limiter from `80` to `0`, removed Awtarchy's managed threshold file, and TLP reported logical `100% (off)`.
- The broader vendor matrix validates Awtarchy's parsing and decisions against current upstream TLP semantics. It does not claim every supported laptop firmware implementation has been physically tested.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.5.5._
