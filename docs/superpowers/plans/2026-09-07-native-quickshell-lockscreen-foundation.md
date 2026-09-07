# Native Quickshell Lockscreen Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and test Awtarchy's dedicated native Quickshell session-lock process without replacing Hyprlock production entrypoints yet.

**Architecture:** A separate `awtarchy-lock` Quickshell configuration owns `WlSessionLock`, one `WlSessionLockSurface` per output, shared PAM authentication, and narrow IPC state. `config/hypr/scripts/awtarchy_lock.sh` is the only shell manager for starting/querying the dedicated lock process. The normal Awtarchy Quickshell shell and all existing Hyprlock production entrypoints remain untouched in this foundation slice.

**Tech Stack:** Bash, Quickshell 0.3.1 QML, `Quickshell.Wayland.WlSessionLock`, `Quickshell.Services.Pam.PamContext`, `Quickshell.Io.FileView`, existing `qs` CLI/IPC.

**Spec:** `docs/superpowers/specs/2026-09-07-native-quickshell-lockscreen-foundation-design.md`

## Global Constraints

- Work only on `feature/quickshell-lockscreen`.
- Do not merge to `main` without a separate explicit authorization.
- Hyprlock remains installed and remains the active production lock path during this foundation slice.
- Production locking must use `WlSessionLock`; an ordinary fullscreen window is not an acceptable security substitute.
- Password/authentication responses must never enter argv, environment variables, shell commands, files, logs, notifications, or IPC.
- The lock process must use the dedicated Quickshell configuration name `awtarchy-lock` and must never broadly kill or signal unrelated Quickshell processes.
- `wait-secure` may report success only after the lock IPC reports compositor-secure state.
- Real Hyprland runtime validation is required before any later Hyprlock retirement work.
- Preserve current package/update/managed-history behavior in this first slice.

---

### Task 1: Add the failing lockscreen foundation regression

**Files:**
- Create: `tests/test-quickshell-lockscreen-foundation.sh`
- Inspect only: `.github/workflows/validate-awtarchy.yml`

**Interfaces:**
- Consumes: approved foundation spec and current Hyprlock entrypoints.
- Produces: a deterministic contract that fails until `awtarchy-lock` QML and `awtarchy_lock.sh` exist.

- [ ] **Step 1: Write the failing test**

Create a Bash regression that sets:

```bash
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_DIR="$ROOT/config/quickshell/awtarchy-lock"
MANAGER="$ROOT/config/hypr/scripts/awtarchy_lock.sh"
HYPRIDLE="$ROOT/config/hypr/hypridle.conf"
HYPRLAND="$ROOT/config/hypr/hyprland.lua"
POWER_MENU="$ROOT/config/quickshell/awtarchy/PowerMenu.qml"
```

The test must fail with clear messages unless all of these contracts hold:

```text
config/quickshell/awtarchy-lock/shell.qml exists
config/quickshell/awtarchy-lock/LockSurface.qml exists
config/quickshell/awtarchy-lock/LockAuth.qml exists
config/quickshell/awtarchy-lock/LockTheme.qml exists
config/hypr/scripts/awtarchy_lock.sh exists
```

Then assert production lock structure with literal/ERE checks:

```text
shell.qml imports Quickshell.Wayland
shell.qml contains WlSessionLock
LockSurface.qml contains WlSessionLockSurface
LockAuth.qml imports Quickshell.Services.Pam
LockAuth.qml contains PamContext
shell.qml exposes an IpcHandler target named lock
manager contains CONFIG_NAME="awtarchy-lock"
manager supports lock, status, wait-secure, stop-test
manager contains no killall
manager contains no generic pkill
manager never targets config name awtarchy
```

Assert secret-handling boundaries:

```text
LockAuth.qml must not import Quickshell.Io Process for authentication
LockAuth.qml must not contain Quickshell.execDetached
LockAuth.qml must not contain environment writes
manager must not accept or forward a password argument
```

Assert the default visual identity:

```text
LockSurface.qml references the local Awtarchy ASCII source path
LockSurface.qml or LockTheme.qml has an opaque black fallback
```

Finally prove this slice has not switched production entrypoints yet:

```bash
grep -Fq 'lock_cmd = pidof hyprlock || hyprlock' "$HYPRIDLE"
grep -Fq 'hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"), {})' "$HYPRLAND"
grep -Fq 'command: "hyprlock"' "$POWER_MENU"
```

Use exact current source text after inspecting each file; do not weaken the test if an entrypoint is represented differently.

- [ ] **Step 2: Run the regression and verify RED**

Run:

```bash
bash tests/test-quickshell-lockscreen-foundation.sh
```

Expected: nonzero with the first missing dedicated lockscreen file/manager contract. The failure must be caused by the missing feature, not test syntax.

- [ ] **Step 3: Commit the RED checkpoint**

```bash
git add tests/test-quickshell-lockscreen-foundation.sh
git commit -m "Test native Quickshell lockscreen foundation"
```

Record the exact RED commit SHA in issue #162.

---

### Task 2: Implement shared theme and PAM authentication state

**Files:**
- Create: `config/quickshell/awtarchy-lock/LockTheme.qml`
- Create: `config/quickshell/awtarchy-lock/LockAuth.qml`

**Interfaces:**
- Consumes: `~/.config/quickshell/awtarchy/theme.json`, current user's PAM `login` stack.
- Produces: `LockTheme` color properties; `LockAuth.submit(response)`, `busy`, `statusText`, `statusIsError`, `responseVisible`, and `authenticated()`.

- [ ] **Step 1: Add focused assertions to the regression for theme/auth behavior**

Require `LockTheme.qml` to read only the local Awtarchy `theme.json` path and provide black/foreground/muted/error fallbacks. Require `LockAuth.qml` to:

```text
leave PamContext.user unset
use config: "login" or the default login configuration
call pam.start()
call pam.respond(pendingResponse)
clear pendingResponse immediately after respond
emit authenticated only for PamResult.Success
leave failures locked
```

- [ ] **Step 2: Run the regression and verify it remains RED**

```bash
bash tests/test-quickshell-lockscreen-foundation.sh
```

Expected: failure because production QML does not exist yet.

- [ ] **Step 3: Implement `LockTheme.qml`**

Use a local `FileView` with `watchChanges: true`, `blockLoading: true`, and `printErrors: false`. Parse JSON with `JSON.parse()` inside `try/catch`; return safe fallbacks on empty/invalid content. Expose at least:

```qml
readonly property color background: value("dark", "#000000")
readonly property color foreground: value("foreground", "#d0d0d0")
readonly property color muted: value("muted", "#666666")
readonly property color accent: value("focus", "#4a4a4a")
readonly property color error: value("critical", "#ff5555")
readonly property string fontFamily: "NotoSansM Nerd Font Mono"
```

The actual lock surface still uses literal opaque black for the stock background; this theme object controls text/accent/error treatment.

- [ ] **Step 4: Implement `LockAuth.qml`**

Use `PamContext` directly. Keep the response only in a QML property:

```qml
property string pendingResponse: ""
property string statusText: ""
property bool statusIsError: false
readonly property bool busy: pam.active
readonly property bool responseVisible: pam.responseVisible
signal authenticated()

function submit(response) {
    if (pam.active || response.length === 0)
        return false;
    pendingResponse = response;
    statusText = "Authenticating…";
    statusIsError = false;
    if (!pam.start()) {
        pendingResponse = "";
        statusText = "Authentication could not start";
        statusIsError = true;
        return false;
    }
    return true;
}
```

On `responseRequiredChanged`, call `pam.respond(pendingResponse)`, then immediately set `pendingResponse = ""`. On `completed`, emit `authenticated()` only for `PamResult.Success`; otherwise set a concise failure status. Do not log the PAM message or response. PAM informational/error messages may update sanitized on-screen status only.

- [ ] **Step 5: Run the focused regression**

```bash
bash tests/test-quickshell-lockscreen-foundation.sh
```

Expected: still RED because the lock shell/surface/manager are not complete, while the auth/theme assertions pass.

- [ ] **Step 6: Commit the auth/theme unit**

```bash
git add config/quickshell/awtarchy-lock/LockTheme.qml \
        config/quickshell/awtarchy-lock/LockAuth.qml \
        tests/test-quickshell-lockscreen-foundation.sh
git commit -m "Add lockscreen PAM and theme state"
```

---

### Task 3: Implement the real multi-monitor lock surface and lock root

**Files:**
- Create: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Create: `config/quickshell/awtarchy-lock/shell.qml`

**Interfaces:**
- Consumes: `LockAuth`, `LockTheme`, local Awtarchy ASCII file.
- Produces: real compositor lock surfaces, shared unlock behavior, IPC `lock.state()` and `lock.stopTest()`.

- [ ] **Step 1: Extend the regression for real-session-lock behavior**

Require:

```text
WlSessionLock.locked is true in production startup
WlSessionLock.surface creates LockSurface/WlSessionLockSurface
IPC state returns secure only from WlSessionLock.secure
successful LockAuth.authenticated sets locked false
failed auth path has no unlock assignment
LockSurface password input uses echoMode Password by default
Escape clears input/status only
Enter calls the shared auth submit function
```

- [ ] **Step 2: Run and verify RED**

```bash
bash tests/test-quickshell-lockscreen-foundation.sh
```

Expected: failure on missing `shell.qml`/`LockSurface.qml` behavior.

- [ ] **Step 3: Implement `shell.qml`**

Use a separate shell id/config and no dependency on normal Awtarchy shell state:

```qml
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root

    LockTheme { id: theme }
    LockAuth {
        id: auth
        onAuthenticated: {
            sessionLock.locked = false;
            quitAfterUnlock.start();
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: true
        surface: Component {
            LockSurface {
                auth: auth
                theme: theme
            }
        }
    }

    IpcHandler {
        target: "lock"
        function state(): string {
            return sessionLock.secure ? "secure"
                : sessionLock.locked ? "starting" : "unlocked";
        }
        function stopTest(): bool {
            if (sessionLock.secure)
                return false;
            sessionLock.locked = false;
            Qt.quit();
            return true;
        }
    }

    Timer {
        id: quitAfterUnlock
        interval: 100
        repeat: false
        onTriggered: Qt.quit()
    }
}
```

Use the exact Quickshell 0.3.1 types/properties verified from upstream docs. Do not add a normal `Window` fallback to production mode.

- [ ] **Step 4: Implement `LockSurface.qml`**

Root it directly in `WlSessionLockSurface` with `color: "#000000"`. Read the logo locally through a `FileView` pointed at:

```text
$XDG_CONFIG_HOME/fastfetch/ascii/awtarchy.txt
```

with `$HOME/.config` fallback. Build a centered/scaled terminal-like column containing logo, current time, date, username, password input, underline, and auth status. Use `Timer` for local time refresh and no network/weather process.

Password behavior:

```qml
Keys.onReturnPressed: auth.submit(password.text)
Keys.onEnterPressed: auth.submit(password.text)
Keys.onEscapePressed: {
    password.text = "";
    auth.clearStatus();
}
```

On shared auth failure/busy changes, clear or refocus the local password field appropriately. Consume unhandled pointer/wheel input on the full surface.

- [ ] **Step 5: Run the regression**

```bash
bash tests/test-quickshell-lockscreen-foundation.sh
```

Expected: still RED only for the missing manager contracts; all lock/auth/surface static contracts pass.

- [ ] **Step 6: Commit the lock surface/root unit**

```bash
git add config/quickshell/awtarchy-lock/shell.qml \
        config/quickshell/awtarchy-lock/LockSurface.qml \
        tests/test-quickshell-lockscreen-foundation.sh
git commit -m "Add native Quickshell session lock"
```

---

### Task 4: Implement the dedicated lock manager

**Files:**
- Create: `config/hypr/scripts/awtarchy_lock.sh`
- Modify: `tests/test-quickshell-lockscreen-foundation.sh`

**Interfaces:**
- Consumes: `qs -c awtarchy-lock`, IPC target `lock` with `state()` and `stopTest()`.
- Produces: `awtarchy_lock.sh lock|status|wait-secure [seconds]|stop-test`.

- [ ] **Step 1: Extend the regression with behaviorally testable manager stubs**

Create a temporary fake `qs` executable controlled by a state file. Test these cases:

```text
status + no IPC -> unlocked
status + IPC starting -> starting
status + IPC secure -> secure
wait-secure transitions starting -> secure -> exit 0
wait-secure remains starting until timeout -> nonzero
stop-test + secure -> refuses and never invokes stopTest
stop-test + starting -> invokes stopTest
lock + already starting/secure -> does not launch another instance
lock + unlocked -> starts only config awtarchy-lock
```

Make the manager injectable with `QS_BIN=${QS_BIN:-qs}` and a short test poll interval such as `AWTARCHY_LOCK_POLL_INTERVAL` so tests do not sleep real seconds.

- [ ] **Step 2: Run and verify RED**

```bash
bash tests/test-quickshell-lockscreen-foundation.sh
```

Expected: manager behavior tests fail because the manager does not exist.

- [ ] **Step 3: Implement `awtarchy_lock.sh`**

Required constants/interfaces:

```bash
CONFIG_NAME="awtarchy-lock"
QS_BIN="${QS_BIN:-qs}"
POLL_INTERVAL="${AWTARCHY_LOCK_POLL_INTERVAL:-0.05}"
```

Implement a narrow IPC helper:

```bash
ipc_state() {
    "$QS_BIN" -c "$CONFIG_NAME" ipc call lock state 2>/dev/null | tail -n1
}
```

Normalize only exact `starting`, `secure`, or `unlocked`; unavailable IPC means `unlocked` for status purposes.

`lock` behavior:

```text
if state is starting/secure: return success
otherwise launch `qs -c awtarchy-lock` detached
poll briefly until IPC becomes starting/secure
return nonzero if the dedicated config never becomes reachable
```

Do not use `killall`, generic `pkill`, `qs kill` without the dedicated config, or process-name matching.

`wait-secure` accepts only a positive numeric timeout, polls IPC until exact `secure`, fails on timeout, and never treats `starting` as success.

`stop-test` first reads state. Exact `secure` must refuse with a nonzero exit. Only non-secure reachable state may call:

```bash
"$QS_BIN" -c "$CONFIG_NAME" ipc call lock stopTest
```

- [ ] **Step 4: Run focused GREEN**

```bash
bash -n config/hypr/scripts/awtarchy_lock.sh
bash tests/test-quickshell-lockscreen-foundation.sh
```

Expected: PASS.

- [ ] **Step 5: Run ShellCheck**

```bash
shellcheck config/hypr/scripts/awtarchy_lock.sh
```

Expected: PASS when ShellCheck is installed.

- [ ] **Step 6: Commit the manager unit**

```bash
git add config/hypr/scripts/awtarchy_lock.sh \
        tests/test-quickshell-lockscreen-foundation.sh
git commit -m "Add Awtarchy lock manager"
```

---

### Task 5: Wire permanent validation without switching production locking

**Files:**
- Modify: `.github/workflows/validate-awtarchy.yml`
- Modify if required by current test organization: `tests/test-quickshell-production-readiness.sh`

**Interfaces:**
- Consumes: focused foundation regression.
- Produces: normal CI coverage preventing the dedicated lock foundation from silently regressing.

- [ ] **Step 1: Add a RED CI-contract assertion to the focused test if needed**

Inspect the current validation workflow and follow its existing pattern for Quickshell-focused tests. Add exactly one invocation of:

```bash
bash tests/test-quickshell-lockscreen-foundation.sh
```

Do not create a new workflow unless the current workflow structure requires one.

- [ ] **Step 2: Verify YAML/diff locally**

Run:

```bash
bash tests/test-quickshell-lockscreen-foundation.sh
git diff --check
```

If the repository has an existing workflow syntax validator, run it as well.

- [ ] **Step 3: Run directly related existing regressions**

Run at minimum:

```bash
bash tests/test-quickshell-process-lifecycle.sh
bash tests/test-quickshell-production-readiness.sh
bash tests/test-quickshell-resume-recovery.sh
```

Only add more tests when inspection shows they cover files/behavior changed in this slice.

- [ ] **Step 4: Commit CI integration**

```bash
git add .github/workflows/validate-awtarchy.yml tests
git commit -m "Validate native Quickshell lockscreen"
```

---

### Task 6: Final branch verification and handoff for real-session testing

**Files:**
- No production changes unless verification finds a defect.
- Update issue #162 progress comment after exact-head verification.

**Interfaces:**
- Consumes: complete foundation branch.
- Produces: exact tested head SHA and the minimum real Hyprland test instructions needed before production migration.

- [ ] **Step 1: Verify branch target and diff**

Run:

```bash
git status --short
git branch --show-current
git diff --check
git diff --stat main...HEAD
```

Expected: clean worktree on `feature/quickshell-lockscreen`; diff limited to the approved foundation spec/plan, dedicated lock QML, manager, focused tests, and CI wiring.

- [ ] **Step 2: Run all focused validation again**

```bash
bash -n config/hypr/scripts/awtarchy_lock.sh
shellcheck config/hypr/scripts/awtarchy_lock.sh
bash tests/test-quickshell-lockscreen-foundation.sh
bash tests/test-quickshell-process-lifecycle.sh
bash tests/test-quickshell-production-readiness.sh
bash tests/test-quickshell-resume-recovery.sh
```

- [ ] **Step 3: Push the exact branch head and inspect CI**

Push `feature/quickshell-lockscreen`, record the full 40-character SHA, and wait for the normal PR/branch validation available for this repository. Do not merge.

- [ ] **Step 4: Update issue #162**

Record:

```text
branch: feature/quickshell-lockscreen
exact head: <40-char SHA>
RED checkpoint: <40-char SHA>
focused tests: pass/fail with exact commands
CI: exact-head status
production entrypoints: still Hyprlock
runtime validation: still required
```

- [ ] **Step 5: Give the maintainer one consolidated runtime test**

The first real-session test should use the dedicated manager directly, not `SUPER + L`:

```bash
~/.config/hypr/scripts/awtarchy_lock.sh lock
```

Before asking the maintainer to run it, verify that `awtarchy git feature/quickshell-lockscreen` is the correct current repository-supported way to install/test the branch. The runtime test must cover successful password unlock and one wrong-password retry first. Multi-monitor/DPMS/suspend/crash-recovery tests follow only after basic lock/unlock succeeds.

Do not call Hyprlock replaced or remove any Hyprlock dependency in this foundation plan.