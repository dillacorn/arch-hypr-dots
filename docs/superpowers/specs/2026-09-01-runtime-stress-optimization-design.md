# Runtime Stress Analysis and Optimization Design

## Objective

Implement the first evidence-gathering stage of GitHub Issue #101 on a fresh branch from current `main`, using reusable real-session tooling to measure Awtarchy/Quickshell runtime behavior before any optimization work is attempted.

The first implementation is measurement-only. It must not change production runtime behavior merely because older analysis branches contained experimental QML changes.

## Source-of-truth and branch strategy

Work from `analysis/runtime-stress-optimization`, created directly from current `main` commit `8fa9d1bdb8076494e420b18f7f26677ec80eacfb`.

Three older branches are reference material only:

- `analysis/runtime-stress-baseline`
- `analysis/runtime-ui-latency`
- `analysis/runtime-content-readiness`

They are stale relative to current `main` and must not be merged or rebased wholesale. Useful measurement logic may be reimplemented or selectively ported after checking it against current Quickshell IPC, titles, state ownership, and tests. Their old QML behavior changes are not part of this first stage.

Once all useful measurement logic has been recovered and verified on the fresh branch, those three branches can be deleted.

## Stage 1 architecture

Stage 1 adds four focused measurement tools under `config/hypr/scripts/` plus focused tests under `tests/`.

### 1. Runtime baseline collector

`awtarchy_runtime_baseline.sh`

Collect a reproducible snapshot of the active Awtarchy session:

- Quickshell PID
- uptime
- RSS
- thread count
- sampled CPU usage
- direct child/helper processes
- Hyprland version
- Quickshell version
- monitor state
- active workspace
- current clients
- Awtarchy command/config/git-testing state where present
- bounded local Quickshell log tail
- current persisted Quickshell state where present

The collector is read-only with respect to processes, services, desktop configuration, and user-selected state. Missing optional data is reported as unavailable instead of aborting the entire collection.

### 2. UI mapped-open latency collector

`awtarchy_ui_latency.sh`

Measure repeated IPC-open to mapped-client latency for current Awtarchy surfaces that expose stable IPC and identifiable Hyprland clients, including where currently supported:

- launcher
- clipboard
- Quick Settings
- network
- Bluetooth

The collector opens and closes only Awtarchy transient UI surfaces. It must restore them to the closed state on normal exit, timeout, or interruption.

Each surface records per-cycle values and min/median/average/max summaries plus timeout/IPC failure counts.

### 3. Content-readiness collector

`awtarchy_content_readiness.sh`

Measure the difference between a surface merely mapping and becoming useful.

Initial targets:

- launcher: mapped time and first usable result/readiness time
- clipboard: mapped time, first entry, first visible row, and first thumbnail readiness when thumbnail candidates exist

Current production QML must be inspected before adding any diagnostic IPC properties. If current components already expose sufficient state, reuse it. If diagnostic properties are necessary, they must be read-only, narrowly scoped, and have no effect on normal UI behavior.

### 4. Consolidated stress runner

`awtarchy_runtime_stress.sh`

Provide one real-session command that creates a timestamped run directory under:

`${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy/logs/runtime-stress-YYYYMMDD-HHMMSS/`

The default automated run performs only safe, reversible session activity:

1. pre-stress runtime baseline
2. UI mapped-open latency cycles
3. content-readiness cycles
4. repeated transient UI open/close stress
5. post-stress runtime baseline
6. summary of measurable deltas and failures

The runner must also support an explicit `snapshot <label>` checkpoint mode that records a labeled runtime baseline without performing UI stress. This is the supported capture path for before/after evidence around user-performed disruptive scenarios.

The runner must not automatically suspend the machine, disconnect monitors, restart NetworkManager/BlueZ/PipeWire/WirePlumber, power-cycle displays, or perform other disruptive host actions.

## Disruptive and hardware-dependent scenarios

Issue #101 also requires behavior that cannot be proven safely by a generic automated script:

- lock/unlock while fullscreen video or games are active
- suspend/resume
- monitor power-off/on
- monitor disconnect/reconnect
- focused-monitor removal
- mixed monitor scales/orientations
- backend restart/reconnect for BlueZ, NetworkManager, PipeWire/WirePlumber, and hyprsunset
- audio-device hotplug
- Bluetooth hardware/device loss
- gamescope/fullscreen behavior
- multi-hour memory/resource growth

Stage 1 makes these tests easier to capture without silently automating them. Use `awtarchy_runtime_stress.sh snapshot <label>` before and after the relevant user-performed event so the same collector format records comparable evidence.

No runtime issue is considered fixed solely from static inspection or CI. Real-session claims require actual session evidence.

## Measurement rules

- Record raw per-cycle values, not only averages.
- Use median as the primary latency comparison statistic, with min/average/max retained for context.
- Record timeout and IPC failure counts separately from successful timings.
- Record pre/post RSS, thread count, and helper/process counts so short stress runs can expose obvious growth.
- Do not claim a memory leak from one short run. Long-session growth requires repeated snapshots over a meaningful session.
- Do not claim an optimization unless a reproducible before/after comparison demonstrates improvement without behavioral regression.

## Testability

Measurement scripts must support fixture-driven tests without requiring a real Hyprland session where practical.

Use overridable paths/timing values for tests, such as:

- procfs root
- sample duration
- cycle count
- timeout
- poll interval
- XDG state/cache roots

Tests must assert that collectors:

- identify the intended Quickshell instance without self-matching search commands
- label unavailable data cleanly
- avoid network access unless a future measurement explicitly requires it
- do not mutate configuration or service state
- restore transient surfaces to the closed state
- produce deterministic report paths/content under fixtures
- calculate summaries correctly
- preserve failures/timeouts in reports instead of dropping them

## Validation

For every new or changed Bash measurement script:

- `bash -n`
- ShellCheck using repository conventions
- focused fixture-driven test
- `git diff --check` equivalent

The final Stage 1 branch should also pass the normal Awtarchy pull-request CI before being treated as ready for real-session collection.

Automated validation proves collector correctness only. It does not prove real UI latency, compositor behavior, hardware behavior, or resource usage on the user's machine.

## Stage 1 success criteria

Stage 1 is complete when:

- the fresh branch contains current-main-compatible collectors instead of stale branch merges
- one command can gather a reproducible safe real-session stress bundle
- `snapshot <label>` can capture comparable before/after checkpoints for disruptive manual tests
- baseline CPU/RSS/thread/helper data is captured
- launcher/clipboard/Quick Settings/network/Bluetooth mapped-open latency is measurable where current IPC supports it
- launcher and clipboard usable-content readiness is measurable
- pre/post stress deltas and failures are summarized
- focused tests and normal CI pass
- at least one real Awtarchy session report is collected and reviewed

## Optimization stage

After Stage 1 evidence exists, each actual problem should be handled as a separate measured change on top of the analysis branch or as a focused follow-up branch/PR when isolation is clearer.

Potential findings may include:

- redundant polling or helper spawning
- repeated synchronous `hyprctl`/state reads
- expensive model rebuilds
- stale UI/backend state
- lifecycle races around startup, resume, unlock, fullscreen, monitor changes, or backend reconnects

Issue #100 should be pulled into implementation only where #101 measurements prove duplicated backend state or polling is a real reliability/efficiency problem. Do not refactor shared state merely because duplication looks possible from static code inspection.

## Non-goals for Stage 1

- no broad QML refactor
- no shared-state consolidation without evidence
- no service/backend restart automation
- no configuration reset or user-state mutation
- no production telemetry or remote reporting
- no optimization claim before measured before/after evidence
