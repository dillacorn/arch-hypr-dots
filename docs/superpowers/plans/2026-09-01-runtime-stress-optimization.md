# Runtime Stress Analysis and Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add current-main-compatible, measurement-only runtime analysis tooling for Issue #101 so Awtarchy performance and lifecycle problems can be reproduced and compared before optimization.

**Architecture:** Add three focused collectors plus one orchestrating stress runner under `config/hypr/scripts/`. Fixture-driven Bash tests validate the collectors without a live Hyprland session, while narrowly scoped read-only Quickshell IPC properties expose launcher and clipboard readiness. A dedicated workflow runs the focused tests on pull requests; normal Awtarchy CI remains the broader regression gate.

**Tech Stack:** Bash, procfs, `ps`, `hyprctl`, Quickshell `qs` IPC, `jq`, QML read-only IPC properties, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-01-runtime-stress-optimization-design.md`

## Global Constraints

- Work only on `analysis/runtime-stress-optimization` unless explicitly changed.
- Stage 1 is measurement-only; do not alter normal runtime behavior to optimize anything yet.
- Do not merge or rebase the three stale analysis branches wholesale.
- Missing optional runtime data must be reported as unavailable rather than aborting the full baseline collection.
- The default stress run may open/close Awtarchy transient UI but must not suspend the machine, restart system services, disconnect monitors, power-cycle displays, or mutate user configuration.
- Diagnostic QML properties must be read-only and must not change normal UI behavior.
- Raw per-cycle timings, timeout counts, and IPC failures must be preserved in reports.
- Median is the primary latency comparison statistic; min/average/max remain visible.
- Short-run RSS growth is evidence for follow-up, not proof of a memory leak.
- Real compositor/hardware claims require real-session evidence after automated validation.

---

### Task 1: Runtime baseline collector

**Files:**
- Create: `tests/test-runtime-baseline-collector.sh`
- Create: `config/hypr/scripts/awtarchy_runtime_baseline.sh`
- Create: `.github/workflows/validate-runtime-stress-analysis.yml`

**Interfaces:**
- Consumes: current Linux user session, optional `qs`, optional `hyprctl`, `/proc`, `ps`, XDG state/cache roots.
- Produces: stdout report and `${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy/logs/runtime-baseline-YYYYMMDD-HHMMSS.log`.

- [ ] **Step 1: Write the failing fixture test**

Create a fixture-driven shell test that stubs `ps`, `qs`, `hyprctl`, `uname`, `date`, and `getconf`; points `AWTARCHY_PROC_ROOT` at a fake proc tree; and asserts all of the following output exists:

```text
Awtarchy runtime baseline
Read-only collector: yes
Quickshell PID: 4242
Quickshell uptime seconds: 321
Quickshell RSS KiB: 65432
Quickshell threads: 2
Quickshell CPU sample 1: 1.2%
Quickshell CPU sample 2: 2.4%
Hyprland 0.fixture
quickshell fixture
```

Also assert monitor/workspace/client JSON, config-version, git-testing state, persisted Quickshell state, a bounded Quickshell log tail, helper-process listing, deterministic report-path creation, and that stubbed `curl`/`wget` are never invoked.

- [ ] **Step 2: Add the focused workflow and verify RED**

Create `.github/workflows/validate-runtime-stress-analysis.yml` with a pull-request job that installs `shellcheck` and runs:

```bash
bash -n tests/test-runtime-baseline-collector.sh
shellcheck tests/test-runtime-baseline-collector.sh
bash tests/test-runtime-baseline-collector.sh
```

Open a draft PR from `analysis/runtime-stress-optimization` to `main`. Expected: focused workflow fails because `awtarchy_runtime_baseline.sh` does not exist.

- [ ] **Step 3: Implement the minimal baseline collector**

Implement `awtarchy_runtime_baseline.sh` with these testability inputs:

```text
AWTARCHY_PROC_ROOT=/proc
AWTARCHY_SAMPLE_SECONDS=2
XDG_STATE_HOME=${HOME}/.local/state
XDG_CACHE_HOME=${HOME}/.cache
QUICKSHELL_CONFIG_NAME=awtarchy
```

Required behavior:

```text
1. Prefer `qs -c awtarchy list --json` for the active Quickshell PID.
2. Fall back to a `ps` snapshot only if the instance list cannot provide a valid PID.
3. Record uptime, RSS, thread count, two `%cpu` samples, and an interval CPU value when procfs tick data is available.
4. Record direct Quickshell children/helpers.
5. Record Hyprland/Quickshell versions, monitors, active workspace, and clients.
6. Record Awtarchy config-version, command-version, git-testing, persisted Quickshell state, and a bounded local Quickshell log tail when present.
7. Save exactly the same report printed to stdout.
```

Do not call network tools or change runtime state.

- [ ] **Step 4: Verify GREEN**

Focused workflow must run:

```bash
bash -n config/hypr/scripts/awtarchy_runtime_baseline.sh
bash -n tests/test-runtime-baseline-collector.sh
shellcheck config/hypr/scripts/awtarchy_runtime_baseline.sh tests/test-runtime-baseline-collector.sh
bash tests/test-runtime-baseline-collector.sh
```

Expected: all commands exit 0.

---

### Task 2: Mapped-open latency collector

**Files:**
- Create: `tests/test-runtime-ui-latency.sh`
- Create: `config/hypr/scripts/awtarchy_ui_latency.sh`
- Modify: `.github/workflows/validate-runtime-stress-analysis.yml`

**Interfaces:**
- Consumes: `qs -c awtarchy ipc call <surface> open|close`, `hyprctl -j clients`, `jq`.
- Produces: per-cycle mapped-open timings and min/median/average/max summaries for launcher, clipboard, Quick Settings, network, and Bluetooth.

- [ ] **Step 1: Write the failing fixture test**

Stub `qs`, `hyprctl`, `jq`, `date`, `sleep`, and `awk` so each surface becomes mapped after deterministic polling. Assert the collector:

```text
- uses these IPC targets: launcher, clipboard, quicksettings, network, bluetooth
- uses these current titles:
  Awtarchy Application Search
  Awtarchy Clipboard History
  Awtarchy Quick Settings
  Awtarchy Network
  Awtarchy Bluetooth
- records every cycle
- reports timeout and IPC error counts separately
- reports min, median, average, and max
- closes all measured surfaces on EXIT
```

- [ ] **Step 2: Verify RED**

Add the test to the focused workflow. Expected: failure because `awtarchy_ui_latency.sh` does not exist.

- [ ] **Step 3: Implement the minimal latency collector**

Support:

```text
AWTARCHY_UI_LATENCY_CYCLES=5
AWTARCHY_UI_LATENCY_TIMEOUT_MS=2000
AWTARCHY_UI_LATENCY_POLL_MS=5
AWTARCHY_UI_LATENCY_SETTLE_MS=180
```

Measure from immediately before `qs ... ipc call <target> open` until `hyprctl -j clients` reports the matching mapped title. Before each cycle, close all measured surfaces and wait until the target title is unmapped. Use an EXIT trap to close all surfaces.

- [ ] **Step 4: Verify GREEN**

Run syntax, ShellCheck, and the focused fixture test for both Task 1 and Task 2 scripts/tests.

---

### Task 3: Usable-content readiness diagnostics and collector

**Files:**
- Create: `tests/test-runtime-content-readiness.sh`
- Create: `config/hypr/scripts/awtarchy_content_readiness.sh`
- Modify: `config/quickshell/awtarchy/Launcher.qml`
- Modify: `config/quickshell/awtarchy/ClipboardMenu.qml`
- Modify: `.github/workflows/validate-runtime-stress-analysis.yml`

**Interfaces:**
- Launcher IPC target `launcher` exposes:
  - `diagnosticResultCount: int`
  - `diagnosticReady: bool`
- Clipboard IPC target `clipboard` exposes:
  - `diagnosticEntryCount: int`
  - `diagnosticFirstRowReady: bool`
  - `diagnosticThumbnailCandidateCount: int`
  - `diagnosticThumbnailReadyCount: int`
  - `diagnosticListLoading: bool`
- Collector reads properties through `qs -c awtarchy ipc prop get <target> <property>`.

- [ ] **Step 1: Write the failing contract/fixture test**

The test must first assert the QML files contain the exact read-only diagnostic property names above. It must then stub IPC property responses over time and assert the collector records:

```text
launcher: mapped time, ready time, result count
clipboard: mapped time, first entry time, first visible row time,
           first thumbnail time when candidates exist, candidate count
```

If clipboard has zero thumbnail candidates and loading is complete, the collector must report `first_thumbnail=n/a` rather than time out.

- [ ] **Step 2: Verify RED**

Add the test to the focused workflow. Expected: failure because current production QML does not expose these properties and the collector does not exist.

- [ ] **Step 3: Add minimal read-only QML diagnostics**

In `Launcher.qml` inside the existing `IpcHandler { target: "launcher" ... }`, add only:

```qml
readonly property int diagnosticResultCount: appList.count
readonly property bool diagnosticReady: launcherWindow.visible
    && root.launcherPositioned
    && launcherPanel.opacity >= 0.99
    && search.activeFocus
    && appList.count > 0
    && appList.currentItem !== null
```

In `ClipboardMenu.qml` inside the existing `IpcHandler { target: "clipboard" ... }`, add only read-only properties derived from current existing UI/backend state:

```qml
readonly property int diagnosticEntryCount: root.entries.length
readonly property bool diagnosticFirstRowReady: clipboardWindow.visible
    && panel.opacity >= 0.99
    && clipboardList.count > 0
    && clipboardList.currentItem !== null
    && clipboardList.currentItem.opacity >= 0.99
readonly property int diagnosticThumbnailCandidateCount: Object.keys(root.thumbnailKnown).length
readonly property int diagnosticThumbnailReadyCount: root.entries.filter(entry =>
    entry && entry.thumb && String(entry.thumb).length > 0).length
readonly property bool diagnosticListLoading: root.listLoading
```

Do not add timers, writes, process launches, state refreshes, or behavior changes for diagnostics.

- [ ] **Step 4: Implement `awtarchy_content_readiness.sh`**

Support cycle/timeout/poll/settle environment overrides parallel to the mapped-open collector. Record raw cycle lines and min/median/average/max summaries for launcher mapped/ready and clipboard mapped/first-entry/first-visible/first-thumbnail timings.

- [ ] **Step 5: Verify GREEN**

Run syntax/ShellCheck for the new Bash files/tests, the focused readiness test, and existing relevant Quickshell tests:

```bash
bash tests/test-quickshell-clipboard-load-state.sh
bash tests/test-quickshell-clipboard-progressive.sh
bash tests/test-quickshell-clipboard-thumbnails.sh
bash tests/test-launcher-keyboard-focus.sh
bash tests/test-quickshell-production-readiness.sh
```

---

### Task 4: Consolidated stress runner and checkpoint mode

**Files:**
- Create: `tests/test-runtime-stress-runner.sh`
- Create: `config/hypr/scripts/awtarchy_runtime_stress.sh`
- Modify: `.github/workflows/validate-runtime-stress-analysis.yml`

**Interfaces:**
- Consumes the three collectors from Tasks 1–3.
- Produces `${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy/logs/runtime-stress-YYYYMMDD-HHMMSS/` containing component reports plus `summary.log`.
- CLI:

```text
awtarchy_runtime_stress.sh run
awtarchy_runtime_stress.sh snapshot <label>
```

- [ ] **Step 1: Write the failing runner test**

Stub the three collector scripts and assert `run` executes in this order:

```text
baseline pre
ui latency
content readiness
transient open/close stress
baseline post
summary
```

Assert `snapshot resume-before` creates a timestamped checkpoint report with a sanitized label and does not run UI stress. Reject labels containing path separators or traversal.

Assert the runner never invokes `systemctl`, `loginctl`, `hyprctl dispatch dpms`, or other disruptive actions.

- [ ] **Step 2: Verify RED**

Add the test to the focused workflow. Expected: failure because `awtarchy_runtime_stress.sh` does not exist.

- [ ] **Step 3: Implement `run`**

`run` must create one run directory, invoke collectors with report paths captured into that directory, execute repeated safe open/close cycles through Quickshell IPC, then summarize:

```text
pre/post Quickshell RSS
pre/post thread count
pre/post direct helper count
collector timeout/IPC failure lines
paths to all component reports
```

The runner must not label short-run RSS growth as a memory leak.

- [ ] **Step 4: Implement `snapshot <label>`**

Sanitize labels to `[A-Za-z0-9._-]+`. Save a baseline snapshot under the current runtime-stress log area so the user can capture before/after evidence around manually performed suspend/resume, fullscreen, monitor, or backend-reconnect tests.

- [ ] **Step 5: Verify GREEN and full focused suite**

The dedicated workflow must run:

```bash
bash -n config/hypr/scripts/awtarchy_runtime_baseline.sh
bash -n config/hypr/scripts/awtarchy_ui_latency.sh
bash -n config/hypr/scripts/awtarchy_content_readiness.sh
bash -n config/hypr/scripts/awtarchy_runtime_stress.sh
bash -n tests/test-runtime-baseline-collector.sh
bash -n tests/test-runtime-ui-latency.sh
bash -n tests/test-runtime-content-readiness.sh
bash -n tests/test-runtime-stress-runner.sh
shellcheck config/hypr/scripts/awtarchy_runtime_baseline.sh \
  config/hypr/scripts/awtarchy_ui_latency.sh \
  config/hypr/scripts/awtarchy_content_readiness.sh \
  config/hypr/scripts/awtarchy_runtime_stress.sh \
  tests/test-runtime-baseline-collector.sh \
  tests/test-runtime-ui-latency.sh \
  tests/test-runtime-content-readiness.sh \
  tests/test-runtime-stress-runner.sh
bash tests/test-runtime-baseline-collector.sh
bash tests/test-runtime-ui-latency.sh
bash tests/test-runtime-content-readiness.sh
bash tests/test-runtime-stress-runner.sh
```

Normal pull-request CI must also pass before Stage 1 is called implementation-ready.

---

### Task 5: Real-session handoff and stale-analysis cleanup

**Files:**
- Modify only if required by validation findings; no production optimization is planned in this task.

**Interfaces:**
- Consumes: green Stage 1 branch and real Awtarchy session.
- Produces: first real-session evidence bundle for Issue #101.

- [ ] **Step 1: Run the safe real-session bundle**

On an Awtarchy Hyprland session:

```bash
~/.config/hypr/scripts/awtarchy_runtime_stress.sh run
```

Review raw cycle timings, timeouts, IPC failures, pre/post RSS, thread counts, and helper counts.

- [ ] **Step 2: Capture one checkpoint pair**

Example:

```bash
~/.config/hypr/scripts/awtarchy_runtime_stress.sh snapshot fullscreen-before
# manually exercise fullscreen lock/unlock behavior
~/.config/hypr/scripts/awtarchy_runtime_stress.sh snapshot fullscreen-after
```

- [ ] **Step 3: Classify findings**

For each observed problem, record whether it is:

```text
reproducible runtime bug
measurable performance problem
possible resource growth requiring longer sampling
hardware/session-specific behavior
no issue observed
```

No optimization is implemented until a finding has current evidence.

- [ ] **Step 4: Delete stale analysis branches only after recovery is verified**

After the new branch contains all useful current-compatible measurement functionality and the real-session command works, delete:

```text
analysis/runtime-stress-baseline
analysis/runtime-ui-latency
analysis/runtime-content-readiness
```

Do not delete them before verifying the recovered tools.
