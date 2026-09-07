# AGENTS.md

Guidance for AI coding agents and LLMs working in the Awtarchy repository.

This file describes project-specific architecture, invariants, workflows, and validation expectations. It is intentionally separate from any user's general LLM personality or custom instructions.

## Core rule

Inspect the current repository before acting.

Awtarchy changes quickly. Current code, tests, CI, Git state, and the exact requested branch/tag/release take precedence over remembered architecture, old conversations, old release behavior, or assumptions based on similar projects.

If this file conflicts with the current implementation, verify the implementation and update this file as part of the relevant work when appropriate.

## Supplemental LLM working guidance

The project maintainer also publishes general evidence-first LLM working guidance at:

https://github.com/dillacorn/LLM-personality

Agents with access to that repository may consult it for additional guidance on evidence gathering, target fidelity, troubleshooting, scoped execution, validation, and communication style. It reflects working practices used while developing Awtarchy and can provide useful context for how changes are expected to be approached.

This external guidance is supplemental, not a dependency or source of Awtarchy implementation truth. Do not block work if it is unavailable. When instructions conflict, the current user request, exact requested target, current Awtarchy code/tests/CI/Git state, and this repository's project-specific guidance take precedence over the external personality repository.

Do not copy external instructions into Awtarchy source files or expand task scope solely because the external repository recommends a general workflow.

## Project identity

- Awtarchy is an overlay environment for Arch Linux. It is not a Linux distribution and does not ship its own ISO.
- Installation begins from a fresh vanilla Arch Linux system, installed manually or with `archinstall`.
- The project manages a Hyprland/Quickshell desktop environment plus installation, update, reset, review, troubleshooting, and backup-management tooling.
- The repository is designed for users comfortable with TTY login, shell interaction, Arch Linux maintenance, and direct configuration.
- Awtarchy is a local open-source utility. Do not introduce hosted-service assumptions or telemetry/data-collection behavior without an explicit project decision.

## System map

Use this only as an orientation map. Inspect the files themselves before making changes.

```text
Fresh Arch Linux
    |
    v
awtarchy-install.sh
    |
    +--> local/share/awtarchy/awtarchy-runtime.sh
    |       |
    |       +--> package/install logic
    |       +--> managed configuration
    |       +--> update/reset/review/troubleshoot/backup logic
    |
    +--> local/bin/awtarchy
            |
            v
      ~/.local/bin/awtarchy
            |
            v
      installed awtarchy-runtime.sh

Desktop configuration
    |
    +--> config/hypr/hyprland.lua
    +--> config/hypr/scripts/
    +--> config/quickshell/awtarchy/

Validation
    |
    +--> tests/
    +--> .github/workflows/validate-awtarchy.yml
```

## Current architecture

Do not assume old Awtarchy architecture still exists. Inspect these current entrypoints first.

### Installer

`awtarchy-install.sh`

- Install-only entrypoint.
- Applies the Awtarchy overlay.
- `--dry-run` previews installation behavior.
- On an existing Awtarchy installation, running it without `--reinstall` repairs/refreshes the installed command and runtime rather than reinstalling packages or replacing managed configs.
- `--reinstall` intentionally performs the full installer path.

### Installed maintenance command

`local/bin/awtarchy`

- Source for the installed `~/.local/bin/awtarchy` command.
- Handles maintenance-command startup, self-refresh behavior, installed state, release/config state, and git-testing state.
- The updater/launcher can refresh from `main` independently of the currently installed configuration release.

### Internal runtime

`local/share/awtarchy/awtarchy-runtime.sh`

- Internal install and maintenance runtime used by the installer/command architecture.
- Contains package catalogs, installer UI/state, update/reset/review behavior, backup handling, troubleshooting, and supporting logic.
- It is large by design. Do not split or substantially reorganize it merely for stylistic reasons.

### Hyprland

`config/hypr/hyprland.lua`

- Primary Hyprland configuration.
- Uses the project's `hl.*` Lua-style configuration API.
- Contains monitor defaults, environment, permissions, autostart, look/feel, input, bindings, submaps, and related desktop behavior.
- Preserve the existing Lua configuration approach unless a task explicitly changes that architecture.

### Quickshell

`config/quickshell/awtarchy/`

- Main Awtarchy shell/UI implementation.
- Includes the bar, launcher, flyouts, notifications, battery/network/audio surfaces, quick settings, and related UI state.
- Supporting shell integration lives primarily under `config/hypr/scripts/`.

Important current state owners include:

- `BarState.qml`: persistent bar/flyout sizing, placement, monitor-specific UI state, and related shell preferences. Its persisted state is under `$XDG_CACHE_HOME/awtarchy/quickshell-state.json` or the equivalent `~/.cache` fallback.
- `FlyoutManager.qml`: active flyout ownership, monitor targeting, cross-flyout handoff, focus-safe closing, and toggle debouncing.
- `BatteryState.qml`: shared battery/UPower state and battery time/charging estimates used by battery UI surfaces.

Before adding new persistent or shared UI state, inspect the existing singleton/state owner first. Do not create a second source of truth for behavior an existing state object already owns.

### PolicyKit authentication

Awtarchy owns its desktop PolicyKit authentication agent instead of delegating that role to `polkit-gnome`.

Repository sources:

- `config/hypr/scripts/awtarchy-polkit-agent/agent.py`: persistent headless system-bus registration and the PolicyKit/PAM authentication conversation.
- `config/hypr/scripts/awtarchy-polkit-agent/tui.py`: short-lived real terminal authentication UI, keyboard/mouse handling, and exact-window Hyprland lifecycle.
- `config/hypr/scripts/awtarchy-polkit-agent/launcher.sh`: validates the trusted runtime, sanitizes current-user Alacritty appearance values, and starts the isolated headless Python backend.
- `config/hypr/scripts/awtarchy-polkit-agent/alacritty.toml`: root-owned fallback terminal configuration for transient authentication windows.
- `config/hypr/scripts/awtarchy-polkit-agent/awtarchy-polkit-agent.service`: supervised headless user service.

Installed trusted runtime:

- `/usr/local/libexec/awtarchy/polkit-agent/`
- `/usr/local/lib/systemd/user/awtarchy-polkit-agent.service`

Important invariants:

- `polkit` and `python-gobject` are explicit Arch package dependencies. `polkit-gnome` is retired and may exist only as a controlled migration fallback.
- The persistent service is a headless `python3 -I .../agent.py` backend. Alacritty must not exist merely because the PolicyKit agent is idle.
- The real authentication frontend is a dedicated transient Alacritty terminal. Quickshell/QML does not participate in authentication and must not be reintroduced as an authentication backend/frontend without an explicit architecture change.
- The Python backend exports `org.freedesktop.PolicyKit1.AuthenticationAgent` on the system bus and uses `PolkitAgent.Session` for the PAM conversation.
- Each active request creates one anonymous inherited `AF_UNIX` `SOCK_SEQPACKET` socketpair between the root-owned backend and root-owned TUI. It has no filesystem path, listener, or reusable endpoint. The submitted response travels TUI -> anonymous socketpair -> `PolkitAgent.Session.response()` and nowhere else.
- Never log, persist, shell-expand, write to temporary files, pass in argv/environment, send through `sudo -S`, expose through a named/filesystem socket, or otherwise duplicate authentication responses.
- Hyprland starts/restarts `awtarchy-polkit-agent.service` after the Wayland/Hyprland session environment exists. Do not globally enable the unit at `default.target` where it can race `WAYLAND_DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE`, or `XDG_SESSION_ID` setup.
- Authentication Python, launcher code, TUI code, and fallback Alacritty configuration must run from the root-owned, non-user-writable runtime under `/usr/local`. Do not execute the live agent from `~/.config`, and do not add user-controlled Python/library/plugin search paths to the agent process.
- User Alacritty configuration may influence only explicitly sanitized visual appearance values. Shell commands, bindings, environment entries, plugins, and other executable configuration must never enter the authentication runtime.
- During authentication, target/focus/resize only the exact `awtarchy-polkit-agent` window. On success, cancellation, final denial, frontend crash, or backend cancellation, the transient TUI/Alacritty process must terminate completely. Do not park it on a special workspace or expose it as a scratchpad/task window.
- Preserve the approved terminal behavior: fixed 900x520 geometry, Details collapsed initially, targeted password-field/status redraws, SGR mouse support, keyboard navigation, three password attempts, real PAM status/error messages, and an `Authenticating` spinner with no artificial success delay.
- Backend diagnostics belong in the user journal. Python warnings/tracebacks must not appear in the authentication terminal's normal buffer.
- Migration must stop only the exact retired GNOME agent binary, verify the supervised headless Python backend, and restore GNOME when activation fails.
- Automatic `polkit-gnome` package removal is allowed only when Awtarchy recorded ownership of that package, live activation succeeded, and every rollback-capable update validation/cleanup step has already completed.
- Changes to this architecture require the focused PolicyKit contracts under `tests/` and permanent CI validation to remain aligned with the implementation.

### Runtime and integration helpers

`config/hypr/scripts/`

- Hyprland/Quickshell integration and desktop helpers.
- Prefer existing helpers and established state paths over creating parallel mechanisms.
- Before adding a new helper, search for an existing script or runtime function that already owns the behavior.

### Tests and CI

`tests/`

`.github/workflows/validate-awtarchy.yml`

- Tests and CI are part of the project's behavioral specification.
- Read the affected tests before changing behavior they cover.
- Current CI explicitly asserts that a root `awtarchy.sh` file does not exist.
- Do not recreate, restore, or target a root `awtarchy.sh` based on older Awtarchy history or remembered architecture.
- Internal runtime help text or legacy compatibility references do not imply that a root `awtarchy.sh` source file should exist.

## Repository source vs installed system

Do not assume a repository file and the currently installed/active copy are identical.

Important distinctions:

- `local/bin/awtarchy` is repository source for the installed `~/.local/bin/awtarchy` command.
- `local/share/awtarchy/awtarchy-runtime.sh` is repository source for the installed runtime under the user's local data directory.
- Repository configuration under `config/` is source-managed content; the active user's configuration normally lives under `~/.config/` after installation/update.
- The installed maintenance command/runtime can refresh from `main` while the installed managed configuration remains associated with a stable release.
- User-owned state, current installed files, repository source, and published release content are separate evidence sources.

For runtime troubleshooting, inspect the installed state when possible. Do not infer the active system solely from the current repository checkout.

## Installed state model

Awtarchy deliberately keeps command/runtime state separate from managed configuration state.

Current important state files include:

- `~/.local/state/awtarchy/command-version`: identifies installed maintenance-command/runtime state and revision.
- `~/.local/state/awtarchy/config-version`: identifies installed configuration release/testing state.
- `~/.local/state/awtarchy/git-testing`: records active Git-testing branch/revision and stable-release context when Git testing is in use.
- `~/.local/state/awtarchy/baseline/`: updater baseline/metadata state used by managed update behavior.

Do not collapse these concepts into one "installed version" value. When debugging version/update behavior, identify which state is being discussed: command/runtime, stable config release, Git-testing config, or baseline/managed history.

Quickshell updater migration also uses:

`local/share/awtarchy/quickshell-managed-history.sha256`

This is managed-history data used to recognize known Awtarchy-managed Quickshell-era file states. Treat changes to it as updater/migration changes, not incidental generated-file cleanup. Inspect the updater tests before changing or regenerating it.

## Stable release vs runtime updates

Stable configuration and the maintenance runtime intentionally have different lifecycles.

- Stable `awtarchy update`, `reset`, and `review` operate on published release configuration.
- The maintenance command/runtime can receive fixes from `main` independently.
- Do not assume the currently installed config tag contains the latest updater/runtime fix.
- Do not assume the current `main` configuration has been released merely because the runtime refreshes from `main`.
- A branch is not a release tag. Stable `--tag` behavior is for exact published releases.

When changing this model, inspect `local/bin/awtarchy`, the runtime updater implementation, `tests/test-awtarchy-git-mode.sh`, updater/migration tests, and current release behavior together.

## Git-testing model

`awtarchy git` is an explicit unreleased testing mode and must remain separate from stable update/reset behavior.

Current tests enforce important safety properties:

- a selected remote branch is resolved explicitly;
- an exact commit override requires the selected branch;
- exact commits use a full 40-character SHA rather than an abbreviated SHA;
- the selected commit must belong to the selected branch;
- stable update paths must not accept hidden Git-testing commit overrides;
- repository branches must not be accepted as stable release tags.

Do not weaken these boundaries to make testing more convenient. If Git-testing behavior changes intentionally, update the implementation and focused tests together.

## Source-of-truth priority

When sources disagree, use this order unless the task explicitly targets historical behavior:

1. Exact user-requested target and current Git state.
2. Current implementation on that target.
3. Tests and CI that exercise the implementation.
4. Current release/tag metadata when release behavior is involved.
5. Current repository documentation.
6. Recent relevant Git history.
7. This `AGENTS.md` file.
8. Memory, prior conversations, or older architecture knowledge.

Never let memory override inspectable repository evidence.

## Target fidelity

The target named by the user is binding.

Before any write, verify the exact:

- repository;
- branch, tag, commit, PR, or release;
- file or artifact;
- relevant version/ref;
- surrounding implementation context.

Do not silently substitute a nearby target because it is easier to access.

Examples of forbidden substitution:

- release notes -> `README.md`;
- requested release -> another release or a recreated tag;
- testing branch -> `main`;
- named config -> a similar config;
- installed runtime -> repository source with assumed equivalence;
- exact file -> replacement file with a similar role.

If the exact target cannot be reached, leave other targets untouched and report the blocker.

After a write, re-read or otherwise verify the same exact target.

## Investigation vs modification

Treat these requests as read-only unless the user explicitly asks for changes:

- review;
- investigate;
- diagnose;
- explain;
- compare;
- research;
- plan.

When a user clearly requests a fix, change, update, or creation, perform the scoped change and validation without unnecessary reconfirmation.

Do not turn investigation into opportunistic cleanup.

## Change discipline

- Preserve existing behavior unless the requested change requires altering it.
- Make the smallest complete change that solves the verified problem.
- Preserve unrelated user-facing behavior and user-selected configuration.
- Do not rewrite unrelated sections while fixing a localized issue.
- Follow existing architecture, naming, helpers, state files, and workflows before inventing new ones.
- Do not invent package names, Arch/AUR availability, Hyprland keys, Quickshell APIs, config paths, commands, environment variables, services, or Git refs.
- Verify external APIs/package/config behavior when it may have changed.
- Preserve comments that encode real compatibility or safety rationale unless they are demonstrably obsolete.

## Managed configuration and updater work

Updater/reset behavior is high-risk because Awtarchy intentionally manages user configuration while also preserving selected user state and backups.

Before modifying update/reset/migration behavior:

- inspect the current installed-command path;
- inspect the runtime implementation;
- inspect relevant state/baseline/managed-history behavior;
- inspect migration and updater tests;
- determine which files are release-managed and which state is intentionally user-owned;
- understand backup/restore behavior before changing overwrite policy.

Do not fix updater failures by indiscriminately deleting user state or replacing all user configuration unless that behavior is explicitly intended and tested.

When recovery behavior is requested, preserve a safe rollback/fallback path where practical.

## Quickshell and desktop UI work

For Quickshell, bar, launcher, flyout, and quick-settings changes:

- inspect the actual QML component and its supporting scripts/state first;
- inspect shared singleton/state owners before introducing duplicate state;
- preserve existing edge/orientation behavior unless intentionally changing it;
- check top/bottom/left/right layouts when the feature is edge-sensitive;
- consider keyboard focus, pointer interaction, toggle/debounce behavior, spawn/despawn lifecycle, and multi-monitor state where applicable;
- prefer one existing source of state over duplicated QML/shell state;
- do not assume visual correctness from static code inspection alone.

`FlyoutManager.qml` intentionally coordinates flyout focus/handoffs to avoid focus gaps and cursor/window focus side effects. Treat lifecycle changes there as behavioral changes and validate them with the focused flyout tests.

Use existing tests as regression guards and add focused coverage when a bug can be reproduced deterministically.

## Hyprland work

- Treat `config/hypr/hyprland.lua` as the current primary configuration format.
- Follow existing `hl.*` conventions instead of converting sections back to `hyprland.conf` syntax.
- Verify current Hyprland syntax and behavior when version-sensitive.
- Plugin behavior may depend on Hyprland/hyprpm ABI state. Inspect current plugin/reload helpers before changing plugin startup behavior.
- Do not resurrect temporary regression patches after upstream behavior no longer requires them.

## Packages and installation

- Package lists live in the current runtime implementation. Inspect them rather than copying package lists from documentation or memory.
- Distinguish official Arch packages, AUR packages, and Flatpak application IDs.
- Do not silently move a package between these sources.
- Preserve laptop/desktop, GPU, filesystem, optional-package, and user-choice behavior unless the requested task changes it.
- Installation assumptions must remain compatible with a fresh vanilla Arch base.

## Git workflow

Before Git writes, verify repository, current branch/ref, remote state, and the requested destination.

- Use testing branches when the user requests testing/isolation.
- If the user explicitly requests a direct `main` change, `main` is the target.
- Do not merge merely because a branch passes tests unless merge was requested or already authorized by the user's workflow instruction.
- Do not force-push, rewrite history, delete branches/tags/releases, or recreate published artifacts unless explicitly requested.
- Keep commit messages concise and human-readable.
- Preserve unrelated working changes.

## Releases and tags

### Standard stable release notes

Inspect the latest published stable release for release-specific context, but do not blindly copy its structure, length, or repeated setup text. `INSTALL.md` and `UPDATING.md` are the canonical user instructions for installation and maintenance; release notes should link to them instead of duplicating them.

A normal Awtarchy stable release body must include:

- the release title and a short overview of the release;
- an **Install and update** section linking to the canonical `main` versions of `INSTALL.md` and `UPDATING.md`; it may also include `awtarchy update` inline for convenience;
- feature/change sections appropriate to the release;
- a **Validation** section grounded in tests and CI that actually passed for the release target;
- a final **Post-release updates** section containing a version-specific placeholder such as `_Placeholder for possible tested post-release patches to vX.Y.Z._`.

Release notes should be proportionate to the release. Routine patch/minor releases should default to a short overview and concise categorized bullets focused on user-visible behavior. Avoid copying debugging chronology, implementation internals, or test-by-test detail when a PR, issue, documentation page, or full-changelog link is a better home for it. Major architectural, migration, or security releases may be substantially longer when the additional explanation is useful. There is no fixed word-count ceiling; concision is a review standard, not a mechanical length failure.

Installation and update procedures belong in `INSTALL.md` and `UPDATING.md`. Repeat procedural detail in release notes only when that release itself changes the procedure and users need migration-specific instructions.

### Mandatory stable release gate

Release-note structure is enforced mechanically. Do not rely on memory or a manually repeated checklist when creating or editing a stable release.

Before any `gh release create` or `gh release edit` operation:

1. Save the proposed release body to a file.
2. Save the latest published stable release body to a second file for context/comparison.
3. Run the permanent validator and require a zero exit status:

```bash
python3 .github/scripts/validate-stable-release-notes.py \
  --version vX.Y.Z \
  --notes /path/to/proposed-release.md \
  --previous /path/to/previous-stable-release.md
```

A release bridge or other automated release writer must run this validator as a hard pre-write dependency. If validation fails, the release write must not execute. The validator enforces objective structure such as canonical guide links, Validation, and the version-specific post-release placeholder; it must not impose an arbitrary word-count limit.

After publishing or editing a release, re-read the complete published body into a file and run the same validator against that published body before declaring the release complete. Continue to verify the release name, draft/prerelease state, target commit, and tag SHA separately; release-note validation does not replace tag/target verification.

`tests/test-stable-release-notes-validator.sh`, `tests/test-install-update-docs.sh`, and `.github/workflows/validate-stable-release-notes.yml` are the permanent regression guards for this contract. Update the validator and its tests together when the intentionally supported stable-release structure changes.

A GitHub release, Git tag, branch, release notes body, and repository documentation are different targets.

When working on a release:

- identify the exact release/tag first;
- inspect the published target where possible;
- edit only the requested release artifact;
- do not move or recreate a tag just to change release notes;
- do not substitute `README.md` for release notes;
- do not increment the version unless explicitly requested;
- verify the published release state after modification.

### Editing an existing published release body

If the exact GitHub release must be edited but the connected GitHub tool does not expose Release read/write actions, do not declare the release inaccessible and do not substitute `README.md`, another ref, or a recreated tag. A proven fallback is a one-use GitHub Actions release bridge on an isolated helper branch.

- Start from the current `main` commit on a temporary helper branch. Do not merge the helper branch merely to edit release notes.
- Add a narrowly guarded one-use job to an existing PR-triggered workflow on that helper branch, then open a specifically named temporary PR to trigger it. Keep the job conditional on the exact PR title/head branch.
- Give only that job `permissions: contents: write`; keep repository-wide workflow permissions unchanged.
- Before writing, use `gh release view` and record the exact release name/target plus the exact tag SHA. Generate the new body from the currently published body so unrelated release-note sections are preserved.
- Update only the existing body with `gh release edit <tag> --notes-file <file>`. Never recreate, delete, or move the tag/release just to change notes.
- Immediately re-read with `gh release view`, compare the complete published body to the intended body, and verify the tag SHA and release metadata are unchanged.
- Keep temporary workflow YAML valid. For generated multiline text inside `run: |`, prefer escaped `\n` strings or another indentation-safe form rather than unindented multiline literals.
- Close the temporary PR and delete helper branches/workflow machinery after verification.
- If a direct authenticated Release update action is available in the current tool surface, prefer it over the temporary bridge.

Release/update behavior may include post-release runtime changes from `main`; inspect current implementation and release state rather than assuming the tag contains every updater fix.

## Validation strategy

Choose validation that can actually prove the requested claim.

### Always useful

- inspect the final diff/change;
- verify the exact target after writing;
- run `git diff --check` when operating in a local checkout or equivalent whitespace validation when available.

### Bash

For changed Bash files, use relevant combinations of:

```text
bash -n <changed-file>
shellcheck <changed-file>
```

Respect existing project-specific ShellCheck exclusions from CI rather than "fixing" deliberate patterns blindly.

### Tests

Run the narrowest directly affected test(s) first, then broader tests when the scope warrants it.

Relevant test families include, but are not limited to:

- installer/command/updater integration;
- Quickshell lifecycle and production readiness;
- updater migration/bootstrap behavior;
- Git-testing mode and stable-release separation;
- bar/flyout/input behavior;
- battery/network/audio helpers;
- security boundaries;
- troubleshooting;
- Lua validation.

Use `.github/workflows/validate-awtarchy.yml` as the current reference for the complete CI validation set.

### Runtime claims

Static checks, syntax validation, lint, and CI do not automatically prove interactive Hyprland/Quickshell runtime behavior.

If a claim depends on real compositor, hardware, suspend/resume, GPU, display, audio, Bluetooth, battery firmware, or other host-specific behavior:

- exhaust available automated checks first;
- distinguish simulated/tested behavior from real runtime confirmation;
- use user-provided runtime output as evidence;
- request the smallest consolidated runtime test only when tools cannot prove the behavior.

Do not call a runtime issue fixed merely because the code looks correct.

## Security and privilege boundaries

Awtarchy contains privileged installation and helper paths.

- Preserve privilege dropping and target-user resolution behavior.
- Treat sudoers, root helpers, system paths, permissions, and command execution boundaries as security-sensitive.
- Do not weaken validation merely to make a test or install path easier.
- Inspect `tests/test-security-boundaries.sh` and relevant helper-specific tests when changing privileged behavior.
- Never expose credentials, tokens, SSH keys, or secrets in logs, commits, release notes, or responses.

## Documentation discipline

Documentation should describe the current project, not remembered historical architecture.

- Keep install directions consistent with the supported fresh-Arch installation model.
- Distinguish stable release instructions from unreleased `main` behavior.
- Do not claim a feature is released merely because it exists on `main`.
- When documentation and implementation diverge, determine which is intended before changing either.

## Maintaining this file

This is a living guide, not an inventory of every feature.

Update `AGENTS.md` when any of these materially change:

- architecture or major entrypoints;
- ownership of shared/persistent state;
- managed-vs-user-owned configuration boundaries;
- updater, stable-release, or Git-testing model;
- security/privilege boundaries;
- important compatibility invariants;
- required validation strategy;
- a recurring agent mistake reveals a missing project rule.

Do not update it merely because a normal UI feature, label, package, animation, or localized implementation detail changed unless that change establishes a durable rule future agents need to know.

Prefer durable rules and pointers to source-of-truth files over exhaustive inventories. Do not turn this file into a changelog, package manifest, or duplicate of the README/tests.

The goal is simple: give an unfamiliar agent enough verified project context to avoid damaging assumptions, then make it inspect the actual target before it acts.
