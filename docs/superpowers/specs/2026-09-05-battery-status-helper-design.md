# Battery Care Read-Only Status Helper Design

## Status

Approved architecture for making Awtarchy Battery Care consume current TLP battery-care status on real systems where `tlp-stat -b` requires root privileges.

This design extends the open Battery Care hardening work on `hardening/tlp-battery-compatibility`. It does not broaden Battery Care write privileges and does not change the authenticated write path through `/usr/local/libexec/awtarchy/power-profile-helper`.

## Problem

Current TLP requires root privileges for `tlp-stat -b`. Awtarchy's Quickshell Battery Care detector runs as the desktop user, so calling `/usr/bin/tlp-stat -b` directly can fail on real hardware even though fixture-based detector tests pass.

That breaks the detector's authoritative source for:

- the selected TLP battery plugin;
- the plugin's supported features;
- vendor-reported threshold ranges or presets;
- current vendor-specific battery-care state.

The failure is especially dangerous after the vendor compatibility hardening because Awtarchy intentionally relies on TLP as the compatibility authority instead of guessing from model names or raw sysfs nodes.

## Goal

Provide Quickshell with read-only access to the exact TLP battery report required by Battery Care without granting passwordless battery-setting privileges, accepting arbitrary commands, or prompting for authentication merely to open the Battery Care flyout.

## Security Boundary

A new root-owned helper will be installed at:

`/usr/local/libexec/awtarchy/battery-status-helper`

The helper has exactly one operation: execute the fixed command `/usr/bin/tlp-stat -b` and return its output and exit status.

The helper must:

- use a fixed root-owned interpreter;
- require effective UID 0;
- accept zero positional arguments;
- reject any arguments instead of forwarding them;
- invoke the fixed absolute `/usr/bin/tlp-stat` path;
- execute only the fixed `-b` option;
- not use `eval`, shell command construction, caller-provided paths, or caller-provided subcommands;
- not write battery settings or configuration;
- not invoke `/usr/bin/tlp`;
- sanitize the execution environment so caller-controlled shell variables cannot alter command lookup or TLP behavior;
- preserve the real `tlp-stat -b` stdout, stderr, and exit status for the detector.

A dedicated sudoers rule will permit only the exact zero-argument helper invocation for the target Awtarchy user:

`<user> ALL=(root) NOPASSWD: /usr/local/libexec/awtarchy/battery-status-helper`

The existing write helper remains outside this rule. There must still be no `NOPASSWD` rule for `/usr/local/libexec/awtarchy/power-profile-helper`.

## Detector Flow

`config/hypr/scripts/quickshell_battery_care.sh` remains the user-session Battery Care detector.

For authoritative TLP status it will:

1. Prefer the trusted installed status helper when present.
2. Invoke it through `sudo -n` so the read path never launches an authentication prompt.
3. Capture the helper's stdout as the TLP battery report.
4. If the helper is unavailable, retain the existing direct `tlp-stat -b` path as a compatibility and test fallback.
5. If neither path yields a valid TLP battery report, preserve existing fail-closed behavior instead of fabricating writable support.

The detector continues to own normalization of TLP plugin semantics into Awtarchy's JSON contract. The privileged helper does not parse or reinterpret vendor behavior.

## Installation and Repair

`local/share/awtarchy/awtarchy-power-profile.sh` remains the laptop power backend reconciler and will own deployment of the status helper and its sudoers policy.

On laptop installs and updates it will:

- validate the repository helper source before installation;
- install the helper root-owned and non-user-writable under `/usr/local/libexec/awtarchy`;
- verify the staged helper before atomic activation;
- create or repair a root-owned `0440` sudoers drop-in for the target user;
- validate the sudoers file with `visudo -cf` before activation;
- refuse unsafe symlinked or writable destination paths;
- leave the authenticated `power-profile-helper` policy unchanged.

The existing runtime already invokes the laptop power reconciler on fresh installs and normal updates, so no parallel installer path should be introduced.

## Failure Behavior

Opening Battery Care must not prompt for a password merely to read status.

If `sudo -n` cannot execute the helper, the detector may use the direct `tlp-stat -b` fallback. If that also fails, Battery Care must report unsupported or unavailable state according to the existing detector contract and must not enable write controls based on guessed capabilities.

A failed read must never trigger configuration changes, `tlp start`, `tlp fullcharge`, or rollback code.

## Test Strategy

The implementation will follow test-driven development.

Regression coverage must prove:

- the status helper is root-only and zero-argument;
- arbitrary arguments are rejected;
- the helper executes only `/usr/bin/tlp-stat -b`;
- caller environment cannot substitute another `tlp-stat` executable;
- the detector succeeds when direct `tlp-stat -b` is deliberately root-only but the installed helper path is available through a fake non-interactive sudo boundary;
- the detector remains fail-closed when neither privileged nor direct status access succeeds;
- fresh-install/update reconciliation installs and repairs the helper and its exact sudoers rule;
- the sudoers rule grants no access to `power-profile-helper`;
- existing Sony, Lenovo, LG, ASUS, ThinkPad, Tuxedo, mixed-BAT0/BAT1, rollback, and unknown-plugin tests remain green;
- permanent Awtarchy CI executes the new focused tests.

The RED regression that exposed this architecture gap is the existing `test-power-profile-helper-update.sh` failure:

`FAIL: read-only Battery Care status helper is missing`

## Non-Goals

This change does not:

- make Battery Care writes passwordless;
- change TLP vendor semantics;
- add a model database;
- bypass TLP with direct vendor writes;
- solve `tlp fullcharge` requiring AC power;
- change Quickshell's rendering of informational TLP stderr;
- alter the separate Bluetooth suspend/resume issue.

## Completion Criteria

The change is ready for merge only when the exact PR head has a fresh passing full validation run, the privilege-boundary regression is green, the existing Battery Care vendor suites remain green, and a hostile audit finds no additional defect. The broader audit counter remains reset whenever a new real defect is found.