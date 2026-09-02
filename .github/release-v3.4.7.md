# Awtarchy v3.4.7 Quickshell

Awtarchy v3.4.7 is a maintenance and reliability release. It adds package reconciliation for existing installations, hardens AUR recovery and package-alternative handling, fixes Git-testing package handoff and update-time Quickshell lifecycle races, and adds runtime measurement tooling used to validate shell behavior under real-session stress. Visual appearance and normal shell layout are intentionally unchanged.

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

Existing Awtarchy users:

```bash
awtarchy update
```

## Package reconciliation

- Adds the `awtarchy packages` maintenance flow so existing installations can install missing current Awtarchy packages and review explicitly retired packages without a reinstall or configuration reset.
- Package alternatives are handled as satisfied families instead of being incorrectly offered as missing when an equivalent choice is already installed.
- Existing AUR equivalence rules are respected for packages such as `alacritty` / `alacritty-graphics`, `qimgv` / `qimgv-git`, and the OBS PipeWire audio-capture variants.
- Selected AUR packages are processed individually so one broken or conflicting AUR package does not terminate the rest of reconciliation.
- AUR helper recovery can rebuild an installed standard `paru` or `yay` helper after a pacman/libalpm upgrade leaves it unable to start.
- Interrupted Ly setup can resume during reconciliation when Ly is installed but not yet enabled.

## Update and Git-testing reliability

- `awtarchy packages` now follows the exact active Git-testing revision instead of accidentally handing off to the installed `main` runtime.
- Managed updates stop the live Quickshell instance before mutating managed Quickshell files when a Hyprland session is active, avoiding update-time reload races while preserving the existing restart and rollback lifecycle.
- Headless and non-Hyprland update paths remain valid.
- Focused regression coverage protects package reconciliation, AUR recovery/equivalence behavior, Git-testing package handoff, and Quickshell update atomicity.

## Runtime analysis and validation

- Adds passive Quickshell runtime baseline collection for RSS, CPU, threads, direct helpers, thread types, monitor/workspace/client state, and bounded local logs.
- Adds mapped-open latency and usable-content readiness measurement for Launcher, Clipboard, Quick Settings, Network, and Bluetooth.
- Adds a consolidated transient stress runner plus labeled snapshots for manual lifecycle checks such as fullscreen lock/unlock, suspend/resume, monitor changes, and backend reconnects.
- Real-session testing found no short-run resource accumulation or measured Awtarchy runtime optimization target.
- Fullscreen + lock/unlock, suspend/resume, PipeWire/WirePlumber recovery on the Awtarchy side, non-focused monitor removal/reconnect, and focused-monitor removal/reconnect all passed the completed real-session checks.

## Validation

- Exact release target: `b9c2385dec61dab53002c08fcdf81a019b308691`.
- GitHub reported eight successful push workflows on that exact `main` commit before publication.
- `Validate Awtarchy` passed the repository's Bash syntax, ShellCheck, Quickshell desktop-entry validation, and full command/updater integration suite on the release target.
- The package-reconciliation, updater atomicity, Git-testing handoff, and runtime-stress changes were developed with focused regression coverage and passed their pull-request validation before merge.
- Runtime claims above are based on the completed real Hyprland session checks rather than static CI alone.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.4.7._
