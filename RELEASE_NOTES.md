# Release Notes

## Next release

### Installed `awtarchy` command

Awtarchy now installs a permanent command at `~/.local/bin/awtarchy` and keeps its runnable script under `~/.local/share/awtarchy/awtarchy.sh`.

Run `awtarchy` to open the main menu. The command checks the latest GitHub release when it starts and offers to update its installed command files before continuing. Configuration changes are still handled separately through preserve, reset, and review modes.

Direct commands include:

```bash
awtarchy update
awtarchy reset
awtarchy review
awtarchy clean-backups
awtarchy version
awtarchy check-update
awtarchy self-update
```

### Existing installation migration

Existing users must update manually one final time from their repository checkout so the installed command is added:

```bash
cd ~/awtarchy
git pull --ff-only
sudo ./awtarchy.sh install
```

The installer questionnaire and selected install stages still apply. After the command is installed, future command updates and managed configuration updates can be started with `awtarchy` without entering the repository directory.

The installed-version state now lives under `~/.local/state/awtarchy/version` rather than the disposable cache directory.
