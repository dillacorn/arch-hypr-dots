# Awtarchy v3.3.3 Technical Resolve

Awtarchy v3.3.3 is a technical-resolve-focused bug-fix release. It hardens update-time graphical session recovery, removes shared `/tmp` state from Hyprland submap and HyprPM runtime coordination, and fixes the edge cases uncovered during live laptop and desktop testing after v3.3.2.

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

## Update-time graphical session recovery

- The updater now reconstructs missing per-user runtime and D-Bus session context when an update is launched from a stripped or privilege-transitioned environment.
- Hyprland session values recovered from the target user's systemd user manager are exported so later updater children inherit the same live graphical session.
- PolicyKit activation no longer falsely reports that no live Hyprland session exists when the active session can be recovered.
- Hypridle restart keeps the recovered Wayland/Hyprland environment instead of being relaunched without compositor context.
- `hyprctl reload` no longer loses the recovered session variables and triggers a rollback in the reproduced stripped-environment path.
- Quickshell is no longer restarted without `XDG_RUNTIME_DIR`, D-Bus, Wayland, or Hyprland context. This prevents Qt from falling back to a generic X11 `quickshell` client and producing the invisible bordered window reproduced during testing.
- Existing valid caller runtime values are preserved; recovery only fills missing runtime/D-Bus values instead of overriding a working environment.

## Per-user Hyprland submap state

- Hyprland submap state no longer uses the shared `/tmp/hypr-submap` path.
- The shell, bar, quick-settings helper, and mouse-submap helper now use per-user runtime state with the existing cache fallback when a runtime directory is unavailable.
- Quickshell reads the same per-user `awtarchy-hypr-submap` state used by Hyprland and the supporting scripts.
- The VM and no-alt desktop launchers now use the Awtarchy Hyprland dispatch form instead of the stale legacy submap dispatch syntax.
- Focused regression coverage verifies that the managed submap paths no longer fall back to shared `/tmp` state.

## Per-user HyprPM runtime lock

- HyprPM auto-reload coordination no longer defaults to the shared `/tmp/hyprpm-auto-reload.lock` path.
- The lock now lives in the per-user Awtarchy runtime directory.
- The runtime directory is created before lock use, including the explicit repair path where it did not already exist.
- Focused regression coverage verifies recent per-user locks suppress duplicate live reconciliation and that repair can create a valid timestamped lock.

## Existing v3.3.x fixes retained

- Keeps the v3.3.2 Bluetooth state synchronization fix so the Quickshell UI follows the actual BlueZ controller power state across login and toggles.
- Keeps the v3.3.1 login update-notification reliability fixes and six-hour periodic check behavior.
- Keeps the v3.3.0 Awtarchy-owned terminal PolicyKit authentication architecture and its root-owned trusted runtime.

## Validation

- The update-session bug was reproduced under deliberately stripped environment variables on a real Awtarchy laptop, first exposing the PolicyKit session warning and then the child-process export failure that caused `hyprctl reload` rollback.
- The same stripped path exposed Quickshell starting without runtime, D-Bus, Wayland, or Hyprland context and creating a generic invisible X11 window.
- The final updater fix was runtime-tested on a second Awtarchy desktop. The update completed with exit code `0`, PolicyKit remained active, Hypridle restarted normally, Hyprland reported no config errors, and the submap remained `default`.
- In that final desktop test Quickshell had no normal Hyprland client windows (`[]`) and only the expected `awtarchy-bar` layer surfaces on both monitors; the invisible window and the earlier Wayland/runtime errors did not return.
- The per-user submap fix was runtime-tested with mouse submap on/off behavior and correct per-user state ownership.
- The HyprPM lock fix was runtime-tested on its exact branch head and then validated again against the combined post-fix `main` state.
- Pull-request validation passed for all three fixes, including Bash syntax, ShellCheck, updater integration, PolicyKit contracts, and focused regression coverage.
- Post-merge `main` validation passed on exact release target `4dc404135f9c718185d5ca4311f1d3372b11138a` before publication.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.3.3._
