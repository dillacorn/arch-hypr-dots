# Release Notes

## Next release

### Install-only entrypoint

The repository installer is now named `awtarchy-install.sh` and is limited to initial installation or an intentional full reinstall.

After installation, Awtarchy uses:

```text
~/.local/bin/awtarchy
~/.local/share/awtarchy/awtarchy-runtime.sh
```

The `awtarchy` command owns command updates, config updates, config resets, review mode, version reporting, and backup cleanup. Its menu no longer exposes installation actions.

### Existing-install detection

When `awtarchy-install.sh` detects the installed `~/.local/bin/awtarchy` command, it prints the maintenance commands and exits without rerunning the installer.

When it detects a legacy Awtarchy installation without the command, it performs a command-only migration. It installs the command, internal runtime, and version state without reinstalling packages or replacing managed configs.

Legacy detection uses Awtarchy state, the previous cache version stamp, the managed-package manifest, or a matching set of Awtarchy-managed shell and Hyprland files.

An intentional complete reinstall remains available with:

```bash
sudo ./awtarchy-install.sh --reinstall
```

### Direct maintenance commands

```bash
awtarchy update
awtarchy reset
awtarchy review
awtarchy clean-backups
awtarchy version
awtarchy check-update
awtarchy self-update
```

Command self-updates and managed-config updates are separate operations. Self-update downloads an exact GitHub release archive, validates both Bash files, and replaces the installed command and runtime atomically.

### Existing installation migration

Existing users must update manually one final time from their repository checkout so the installed command is added:

```bash
cd ~/awtarchy
git pull --ff-only
sudo ./awtarchy-install.sh
```

The installer detects the legacy installation and performs only the command migration. Afterward, future maintenance starts with `awtarchy` and no repository directory is required.

Persistent version state is stored under:

```text
~/.local/state/awtarchy/command-version
~/.local/state/awtarchy/config-version
```
