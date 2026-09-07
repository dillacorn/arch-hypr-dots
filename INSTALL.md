# Installing Awtarchy

Awtarchy is an Arch Linux overlay/environment, not a Linux distribution and not an Arch Linux installer. Start with a working vanilla Arch Linux system, then apply Awtarchy on top of it.

## Install Arch first

For a new machine:

1. Download the official Arch Linux ISO from the [Arch Linux download page](https://archlinux.org/download/).
2. Boot the Arch ISO.
3. Install Arch Linux.
   - Recommended: run the official `archinstall` guided installer and choose the **Minimal** profile.
   - Manual installation is also supported; follow the [ArchWiki Installation Guide](https://wiki.archlinux.org/title/Installation_guide).
4. Boot into the installed Arch system and log in.

Awtarchy expects a minimal vanilla Arch base. It does not require a custom ISO or a separate distribution installation.

## Install Awtarchy

Install Git, clone the repository, and run the installer:

```bash
sudo pacman -S git --noconfirm
git clone https://github.com/dillacorn/awtarchy
cd awtarchy
sudo ./awtarchy-install.sh
```

The installer collects the relevant hardware/package choices before applying the overlay.

After installation, use:

```bash
awtarchy
```

The installed maintenance command lives at `~/.local/bin/awtarchy`.

## Preview before installing

The dry-run path shows the installer questionnaire and planned work without applying system changes:

```bash
./awtarchy-install.sh --dry-run
```

## Running the installer again

On an existing Awtarchy installation, running the installer normally repairs/refreshes the installed maintenance command and runtime without intentionally performing a full reinstall or replacing release-managed configuration.

Use the full reinstall path only when that is actually intended:

```bash
sudo ./awtarchy-install.sh --reinstall
```

For normal Awtarchy upgrades, do not rerun the installer. Use the maintenance command documented in [UPDATING.md](UPDATING.md).
