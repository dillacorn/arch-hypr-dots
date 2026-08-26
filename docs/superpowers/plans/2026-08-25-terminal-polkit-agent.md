# Terminal PolicyKit Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Quickshell-rendered Awtarchy PolicyKit agent with the approved real terminal TUI backed directly by PolicyKit/PAM.

**Architecture:** A root-owned user service launches Alacritty with a root-owned Python/PyGObject agent. The agent exports the PolicyKit authentication D-Bus interface, uses `PolkitAgent.Session` for PAM, and renders the approved mouse-capable terminal TUI while moving only its exact window between a hidden Hyprland special workspace and the active workspace.

**Tech Stack:** Bash, Python 3, PyGObject/GI (`Gio`, `GLib`, `Polkit`, `PolkitAgent`), Alacritty, Hyprland, systemd user services, GitHub Actions tests.

**Spec:** `docs/superpowers/specs/2026-08-25-terminal-polkit-agent-design.md`

## Global Constraints

- Authentication runtime source installed under `/usr/local/libexec/awtarchy/polkit-agent` is root-owned, non-symlink, and not group/world writable.
- No Quickshell/QML process participates in authentication.
- Password responses travel only into `PolkitAgent.Session.response()` and are never logged, persisted, passed in argv, temporary files, sockets, `sudo -S`, or `pkexec` stdin.
- The visible authentication UI remains a real terminal window with the approved 900x520 TUI behavior.
- `polkit` and `python-gobject` are explicit Arch dependencies.
- `polkit-gnome` remains available during Git testing and is restored automatically if activation/authentication fails.
- The service starts from Hyprland after Wayland/Hyprland environment setup; it is not globally enabled at `default.target`.

---

### Task 1: Replace the production security contract with terminal-agent expectations

**Files:**
- Modify: `tests/test-polkit-agent-secure.sh`
- Modify: `tests/test-polkit-agent-production-integration.sh`
- Modify: `tests/test-polkit-agent-runtime-rebuild.sh`
- Modify: `.github/workflows/polkit-agent-testing.yml`

**Interfaces:**
- Consumes: current Quickshell production-agent contract.
- Produces: failing tests that require `agent.py`, `tui.py`, `alacritty.toml`, Python GI dependencies, terminal mouse behavior, and no QML runtime.

- [ ] **Step 1: Rewrite the security test to require terminal runtime files**

Require `agent.py`, `tui.py`, `launcher.sh`, `alacritty.toml`, and the service. Reject `shell.qml`, Quickshell executable references, credential logging/persistence patterns, user-controlled Python/QML search paths, unsafe symlink/runtime modes, and non-absolute critical binaries.

- [ ] **Step 2: Extend production integration assertions**

Require the package catalog to contain both `polkit` and `python-gobject`, require the root-owned installer to stage/install all terminal-agent files, and retain late conditional GNOME removal assertions.

- [ ] **Step 3: Replace runtime-rebuild assertions**

Require staging/replacement of the complete terminal runtime set and rollback of a previous trusted runtime on activation failure.

- [ ] **Step 4: Add terminal parser contract to CI**

Run a focused Python test that feeds `b'\x1b[<0;43;16M'` and `b'\x1b[<0;43;16m'` through the production TUI parser and checks press/release coordinates.

- [ ] **Step 5: Run the branch workflow and verify RED**

Expected: failures because the branch still contains `shell.qml`, Quickshell launcher behavior, and no terminal agent Python files.

- [ ] **Step 6: Commit**

Commit message: `Define terminal Polkit agent contracts`.

---

### Task 2: Implement the terminal TUI and Hyprland window lifecycle

**Files:**
- Create: `config/hypr/scripts/awtarchy-polkit-agent/tui.py`
- Create: `config/hypr/scripts/awtarchy-polkit-agent/alacritty.toml`
- Delete: `config/hypr/scripts/awtarchy-polkit-agent/window-guard.sh`
- Test: `tests/test-polkit-agent-tui.py`

**Interfaces:**
- Consumes: an open `/dev/tty`; request metadata supplied by `agent.py`.
- Produces: `TerminalUI` with `show_request(...)`, `hide()`, `set_prompt(...)`, `set_status(...)`, `set_error(...)`, `clear_secret()`, `feed_bytes(data)`, and callbacks for submit/cancel/identity-cycle.

- [ ] **Step 1: Add parser tests**

Test standard keys, Tab/Shift+Tab, Enter/Esc, backspace, printable password bytes, and SGR mouse events including the exact live fixture `ESC[<0;43;16M/m`.

- [ ] **Step 2: Implement terminal raw-mode lifecycle**

Open `/dev/tty`, save `termios` state, enter alternate screen, enable SGR mouse reporting only while a request is visible, and always restore terminal state on shutdown.

- [ ] **Step 3: Implement approved TUI rendering**

Port the approved concept layout: magenta header, real message, targeted password redraw, collapsed Details, red Cancel, green Authenticate, keyboard hint line, and PAM status/error line. Keep password contents out of render state; rendering stores only display length.

- [ ] **Step 4: Implement input dispatch**

Use buffered byte parsing rather than delimiter-sensitive shell reads. Mouse hit-testing uses terminal cell coordinates calculated during render. Empty Authenticate reports `Password not entered.` without invoking submit.

- [ ] **Step 5: Implement exact-window Hyprland lifecycle**

Locate only the window whose class/title is `awtarchy-polkit-agent` via `hyprctl -j clients`. Hide it on `special:awtarchy-polkit-agent`; on request move it to the previously focused normal workspace, float, resize to 900x520, center, and focus using absolute `/usr/bin/hyprctl` calls.

- [ ] **Step 6: Add root-owned Alacritty config**

Use a minimal config with stable monospaced font/window behavior. Launcher command-line `-e` remains authoritative for the child process.

- [ ] **Step 7: Run focused tests**

Run Python TUI/parser tests and `git diff --check`.

- [ ] **Step 8: Commit**

Commit message: `Add terminal Polkit TUI`.

---

### Task 3: Implement the real PolicyKit authentication agent

**Files:**
- Create: `config/hypr/scripts/awtarchy-polkit-agent/agent.py`
- Test: `tests/test-polkit-agent-secure.sh`

**Interfaces:**
- Consumes: `TerminalUI`; system bus; `Polkit.Authority`; `PolkitAgent.Session`.
- Produces: registered object `/org/awtarchy/PolkitAgent` implementing `org.freedesktop.PolicyKit1.AuthenticationAgent`.

- [ ] **Step 1: Export the authentication D-Bus object**

Use `Gio.bus_get_sync(Gio.BusType.SYSTEM, None)` and `Gio.DBusConnection.register_object()` with the official `BeginAuthentication` and `CancelAuthentication` signatures.

- [ ] **Step 2: Register for the current Unix session**

Resolve `Polkit.UnixSession.new_for_process_sync(os.getpid(), None)`, obtain `Polkit.Authority.get_sync(None)`, then call `register_authentication_agent_sync(subject, locale, '/org/awtarchy/PolkitAgent', None)`.

- [ ] **Step 3: Convert allowed identities safely**

Accept supported `unix-user` identities, prefer the current UID, expose multiple supported identities to the TUI, and fail the request if no supported Unix-user identity exists.

- [ ] **Step 4: Implement `PolkitAgent.Session` conversation**

Create `PolkitAgent.Session.new(identity, cookie)`, connect `request`, `show-info`, `show-error`, and `completed`, then call `initiate()`. Route the current TUI response directly to `session.response(response)` and immediately clear the UI secret buffer.

- [ ] **Step 5: Implement completion/cancellation semantics**

Hold the `BeginAuthentication` `Gio.DBusMethodInvocation` until session completion. Return success with `invocation.return_value(None)` after gained authorization; return `org.freedesktop.PolicyKit1.Error.Cancelled` for user/polkit cancellation. Cancel only a matching active cookie.

- [ ] **Step 6: Enforce one active request**

Reject overlapping requests without modifying the active session/request state.

- [ ] **Step 7: Add signal/shutdown cleanup**

On SIGTERM/SIGINT cancel active session, unregister the authentication agent, unexport the D-Bus object, restore the TTY, and exit cleanly.

- [ ] **Step 8: Run syntax/static security tests**

Run `python3 -m py_compile` for both Python files plus focused security tests.

- [ ] **Step 9: Commit**

Commit message: `Implement terminal Polkit agent`.

---

### Task 4: Replace the Quickshell launcher/service with Alacritty terminal runtime

**Files:**
- Modify: `config/hypr/scripts/awtarchy-polkit-agent/launcher.sh`
- Modify: `config/hypr/scripts/awtarchy-polkit-agent/awtarchy-polkit-agent.service`
- Delete: `config/hypr/scripts/awtarchy-polkit-agent/shell.qml`

**Interfaces:**
- Consumes: root-owned runtime files and current Hyprland/Wayland environment.
- Produces: one supervised Alacritty process running `/usr/bin/python3 .../agent.py`.

- [ ] **Step 1: Rewrite launcher verification**

Verify `/usr/bin/alacritty`, `/usr/bin/python3`, `/usr/bin/hyprctl`, runtime directory, `agent.py`, `tui.py`, and `alacritty.toml`; reject symlinks or unsafe ownership/modes.

- [ ] **Step 2: Sanitize environment**

Unset Python injection variables (`PYTHONPATH`, `PYTHONHOME`, `PYTHONSTARTUP`, `PYTHONINSPECT`, `PYTHONUSERBASE`) plus library/plugin injection variables. Launch using `env -i` while preserving only required Wayland/Hyprland/session bus/locale variables.

- [ ] **Step 3: Launch terminal explicitly**

Run `/usr/bin/alacritty --config-file <root-owned-config> --class awtarchy-polkit-agent,awtarchy-polkit-agent --title awtarchy-polkit-agent -e /usr/bin/python3 -I <runtime>/agent.py`.

- [ ] **Step 4: Update service failure behavior**

Keep `Restart=on-failure`, `RestartPreventExitStatus=78`, and no `[Install]` enablement target.

- [ ] **Step 5: Remove QML runtime**

Delete `shell.qml` and all production Quickshell references.

- [ ] **Step 6: Run launcher/security tests**

Run `bash -n`, Python compile, static security tests, and `git diff --check`.

- [ ] **Step 7: Commit**

Commit message: `Launch Polkit agent in terminal`.

---

### Task 5: Integrate terminal runtime into install/update migration

**Files:**
- Modify: `local/share/awtarchy/awtarchy-runtime.sh`
- Modify: `config/hypr/scripts/awtarchy-polkit-agent-live-test.sh`
- Modify: `AGENTS.md`
- Test: `tests/test-polkit-agent-production-integration.sh`
- Test: `tests/test-polkit-agent-runtime-rebuild.sh`

**Interfaces:**
- Consumes: terminal runtime files from Tasks 2-4.
- Produces: root-owned installation/update/live-test flow with GNOME fallback.

- [ ] **Step 1: Add explicit package dependency**

Add `python-gobject` alongside explicit `polkit` without reintroducing `polkit-gnome` as a fresh-install dependency.

- [ ] **Step 2: Update trusted runtime staging/install**

Stage/install `launcher`, `agent.py`, `tui.py`, and `alacritty.toml`; install the service separately. Remove QML/window-guard staging references.

- [ ] **Step 3: Update live activation verification**

Verify the service MainPID resolves to `/usr/bin/alacritty`, verify the child command is `/usr/bin/python3 -I /usr/local/libexec/awtarchy/polkit-agent/agent.py`, and ensure GNOME exact binary is inactive before declaring success.

- [ ] **Step 4: Update live-test controller**

Install the terminal runtime, start it, report terminal-agent status, trigger `/usr/bin/pkexec --disable-internal-agent /usr/bin/true`, and retain automatic GNOME rollback on registration/service failure or explicit stop.

- [ ] **Step 5: Preserve late GNOME removal ordering**

Do not change the existing rule: package removal is allowed only after successful live activation and after all rollback-capable update work completes.

- [ ] **Step 6: Update `AGENTS.md`**

Replace Quickshell-agent architecture text with terminal agent, Python/PyGObject, root-owned terminal config, direct PolicyKit session, and credential-path invariants.

- [ ] **Step 7: Run full branch validation**

Run runtime syntax, Python compile, production integration, secure contract, runtime rebuild, TUI parser tests, and `git diff --check`.

- [ ] **Step 8: Commit**

Commit message: `Integrate terminal Polkit migration`.

---

### Task 6: Live desktop validation and final branch cleanup

**Files:**
- Modify/delete only after successful live validation: `config/hypr/scripts/awtarchy-polkit-agent-live-test.sh`, `.github/workflows/polkit-agent-testing.yml`, superseded Quickshell-only design documentation as appropriate.

**Interfaces:**
- Consumes: installed testing-branch terminal agent.
- Produces: merge-ready production branch after real authentication succeeds.

- [ ] **Step 1: Update the user's testing branch**

Run `awtarchy git update --branch polkit-agent-concept-testing`.

- [ ] **Step 2: Install/start/status the root-owned test runtime**

Use the live-test controller. Expected status: Awtarchy terminal agent active, GNOME inactive, trusted runtime verified.

- [ ] **Step 3: Trigger real harmless authentication**

Run controller `test`, which invokes `/usr/bin/pkexec --disable-internal-agent /usr/bin/true`. Verify the approved terminal TUI appears, mouse and keyboard controls work, wrong password produces the real PAM error, correct password completes successfully, and the window hides afterward.

- [ ] **Step 4: Verify failure rollback**

Use controller `stop` or an intentionally stopped service path and verify GNOME can be restored without logout/reboot.

- [ ] **Step 5: Remove testing-only artifacts**

After successful live validation, remove the live-test controller and branch-only workflow from the production diff; keep production tests in the normal validation workflow as appropriate.

- [ ] **Step 6: Final verification**

Run the complete repository validation suite and compare branch against `main`. Do not merge until this passes and the user explicitly authorizes merge.
