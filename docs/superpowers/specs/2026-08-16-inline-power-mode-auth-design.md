# Inline Power Mode Authorization Design

## Goal

Replace the terminal-based Power Mode setup/repair flow with an inline Quickshell authorization flow while keeping privileged package and service changes behind a fixed, root-owned helper.

## Recommended architecture

Use a dedicated helper at `/usr/local/libexec/awtarchy/power-profile-helper`.

The helper is the only component allowed to perform privileged Power Mode setup/repair actions. It must use a fixed interpreter, reject arbitrary commands and arguments, and expose only the exact operations Awtarchy needs for TLP/tlp-pd or power-profiles-daemon setup. Quickshell and user-writable config files must never be trusted as privileged code.

The helper is installed and repaired by the Awtarchy updater using the same defensive pattern as the existing sched-ext helper: root-owned destination, non-writable permissions, fixed interpreter validation, Bash syntax validation, atomic staging, source/staged hash verification, and post-install verification.

## Quickshell flow

`PowerModeCard.qml` keeps normal Power Saver / Balanced / Performance profile switching unchanged.

When setup or conflict repair is required, the card opens an inline masked password field. The password is kept only long enough to write it to a child process stdin channel and is immediately cleared from the visible field and transient QML state.

A user-space backend entrypoint invokes `sudo -S -p '' /usr/local/libexec/awtarchy/power-profile-helper <fixed-action>`. The password must never appear in argv, environment variables, files, logs, or persistent state.

The UI disables duplicate submissions while authorization is running and reports success or the first useful error inline. After success it re-probes the backend and exposes the normal Power Mode buttons without opening a terminal.

## Privileged helper contract

The helper supports only narrowly defined actions, not arbitrary shell execution:

- `setup`: detect whether TLP is installed and ensure the matching supported backend is installed and enabled.
- `resolve-tlp-conflict`: when literal `tlp` and literal `power-profiles-daemon` packages are both installed, remove only `power-profiles-daemon`, install `tlp-pd`, and enable `tlp.service` plus `tlp-pd.service`.

The helper must use absolute paths for privileged executables where practical, exact package-name checks, and explicit service names. It must reject extra arguments, unknown actions, non-Linux/unsupported environments, and non-laptop setup requests.

Normal profile changes continue through the Power Profiles D-Bus interface and do not invoke sudo or the privileged helper.

## Security properties

- No privileged execution of files under the user's home directory.
- No broad `NOPASSWD` rule for pacman, systemctl, shell, or the helper.
- No arbitrary package names, service names, commands, paths, or shell fragments accepted from Quickshell.
- No password in command arguments, environment, files, logs, or persistent application state.
- Root-owned helper cannot be writable by group or other users and is never followed through a symlink during updater installation.
- Setup is one-shot authenticated work; profile switching remains unprivileged through the existing D-Bus backend.
- Existing polkit/session authentication behavior is left untouched.

## Error handling

Authentication failure leaves the system unchanged and keeps the inline prompt open with a concise error.

Package or service failure is surfaced inline and must not be reported as success. The UI re-probes backend state only after the helper exits successfully.

Conflict resolution requires an explicit UI action so merely opening Quick Settings never removes packages.

## Validation

Add regression coverage for:

- masked inline password entry and stdin-only transport;
- absence of terminal setup launching from `PowerModeCard.qml`;
- helper rejection of unknown actions and extra arguments;
- fixed privileged command/package/service allowlist;
- exact package detection so virtual providers cannot create false conflicts;
- updater installation/repair of the root-owned helper with interpreter, syntax, ownership, mode, symlink, and hash checks;
- no broad `NOPASSWD` or arbitrary-shell privilege boundary;
- preservation of normal TLP profile switching;
- Bash syntax, ShellCheck, updater integration, security-boundary tests, and the full Awtarchy validation workflow.

After implementation, review the exact `main` diff with the Codex Security diff-scan methodology before declaring the change ready for hardware testing.
