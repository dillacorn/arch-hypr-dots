# Visual Theme Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Awtarchy's filename-list theme picker with a safe visual theme browser that previews palette data and applies only an explicitly selected theme through the existing theme apply helper.

**Architecture:** Add one read-only catalog helper that parses theme data into JSON without sourcing theme files. Replace `ThemePicker.qml` with a responsive card-grid browser that owns only ephemeral browse state and delegates all actual theme application to `quickshell_theme_apply.sh`. Keep `Theme.qml`, theme files, active-theme state, existing IPC, Quick Settings entrypoints, and wallpaper behavior unchanged.

**Tech Stack:** Bash, Python 3 standard library, QML/QtQuick, Quickshell, jq/ShellCheck/Bash tests, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-28-visual-theme-browser-design.md`

## Global Constraints

- `config/hypr/scripts/quickshell_theme_apply.sh` remains the only production path that mutates theme state or app configuration.
- Never source or execute files under `config/hypr/themes/` while building the catalog.
- Preview browsing is non-destructive and must not modify wallpaper, `theme.json`, Hyprland, app configs, or active-theme state.
- Preserve the existing `themes` IPC target and `ThemePicker.openForScreen(activeScreen)` Quick Settings integration.
- Use existing Python 3 only; add no new package dependency.
- Managed-history changes are append-only and must preserve current Bluetooth, Night Light, and bar-customization hashes.
- True live desktop preview remains out of scope for this branch.

---

### Task 1: Theme catalog reader

**Files:**
- Create: `config/hypr/scripts/quickshell_theme_catalog.sh`
- Create: `tests/test-quickshell-theme-catalog.sh`

**Interfaces:**
- Consumes: `${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/*`
- Produces: stdout JSON array of `{name, display_name, palette, borders, apps}` objects.
- Exit contract: `0` with valid JSON; non-zero for unreadable directory or malformed required preview palette.

- [ ] **Step 1: Write the failing catalog test**

The test must create an isolated fake config tree with two themes plus a backup file and a malicious-looking assignment that would create a marker if executed. It must assert deterministic ordering, backup exclusion, exact palette/app fields, readable display names, and absence of the marker.

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="${ROOT}/config/hypr/scripts/quickshell_theme_catalog.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

config="${TMP}/config"
mkdir -p "${config}/hypr/themes"
marker="${TMP}/executed"

cat >"${config}/hypr/themes/zeta_theme" <<EOF
QS_BACKGROUND="#111111"
QS_FOREGROUND="#eeeeee"
QS_HOVER="#222222"
QS_FOCUS="#333333"
QS_ACTIVE="#181818"
QS_URGENT="#ff0000"
QS_DARK="#090909"
QS_CHARGING="#00ff00"
QS_CRITICAL="#ff0000"
QS_MUTED="#888888"
NEW_ACTIVE_BORDER="eeeeeeff"
NEW_INACTIVE_BORDER="111111ff"
MICRO_COLORSCHEME="zenburn"
ALACRITTY_THEME="wombat.toml"
SPEEDCRUNCH_COLORSCHEME="zeta_theme"
EVIL="\$(touch ${marker})"
EOF
cp "${config}/hypr/themes/zeta_theme" "${config}/hypr/themes/zeta_theme.backup"
sed 's/zeta_theme/alpha-theme/g' "${config}/hypr/themes/zeta_theme" >"${config}/hypr/themes/alpha-theme"

json="$(XDG_CONFIG_HOME="$config" bash "$CATALOG")"
jq -e 'length == 2 and .[0].name == "alpha-theme" and .[1].name == "zeta_theme"' <<<"$json" >/dev/null
jq -e '.[0].display_name == "Alpha Theme"' <<<"$json" >/dev/null
jq -e '.[1].palette.background == "#111111" and .[1].apps.alacritty == "wombat.toml"' <<<"$json" >/dev/null
[[ ! -e "$marker" ]]
printf '%s\n' 'Quickshell theme catalog test passed.'
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
bash -n tests/test-quickshell-theme-catalog.sh
bash tests/test-quickshell-theme-catalog.sh
```

Expected: FAIL because `quickshell_theme_catalog.sh` does not exist.

- [ ] **Step 3: Implement the catalog helper**

Use Bash only as a stable entrypoint and Python 3 standard library for strict literal parsing. Accept only lines matching `^[A-Z0-9_]+="[^"\n]*"$`; never use `source`, `eval`, `bash -c`, or shell expansion on theme contents. Require the ten `QS_*` preview keys and normalize filenames into display names.

- [ ] **Step 4: Run catalog test to verify GREEN**

Run:

```bash
bash -n config/hypr/scripts/quickshell_theme_catalog.sh
bash -n tests/test-quickshell-theme-catalog.sh
shellcheck config/hypr/scripts/quickshell_theme_catalog.sh tests/test-quickshell-theme-catalog.sh
bash tests/test-quickshell-theme-catalog.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/hypr/scripts/quickshell_theme_catalog.sh tests/test-quickshell-theme-catalog.sh
git commit -m "Add theme catalog reader"
```

### Task 2: Visual picker regression contract

**Files:**
- Create: `tests/test-quickshell-theme-picker.sh`
- Test: `config/quickshell/awtarchy/ThemePicker.qml`
- Test: `config/quickshell/awtarchy/QuickSettings.qml`
- Test: `config/hypr/scripts/theme_select.sh`

**Interfaces:**
- Consumes: existing `ThemePicker.qml` and entrypoints.
- Produces: a focused static regression that defines the new browser contract before implementation.

- [ ] **Step 1: Write the failing picker regression**

The test must assert:

```bash
grep -Fq 'quickshell_theme_catalog.sh' "$PICKER"
grep -Fq 'GridView {' "$PICKER"
grep -Fq 'text: "Apply Theme"' "$PICKER"
grep -Fq 'active-theme' "$PICKER"
grep -Fq 'function applySelectedTheme()' "$PICKER"
grep -Fq 'applyProcess.exec([root.applyBackend, selected.name])' "$PICKER"
grep -Fq 'Qt.Key_Left' "$PICKER"
grep -Fq 'Qt.Key_Right' "$PICKER"
grep -Fq 'Qt.Key_Home' "$PICKER"
grep -Fq 'Qt.Key_End' "$PICKER"
grep -Fq 'target: "themes"' "$PICKER"
grep -Fq 'ThemePicker.openForScreen(activeScreen)' "$QUICK_SETTINGS"
grep -Fq 'ipc call themes toggle' "$THEME_SELECT"
! grep -Fq "find '" "$PICKER"
```

It must also reject any call to `applyBackend` from hover or selection-change handlers by limiting apply execution to `applySelectedTheme()`.

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
bash -n tests/test-quickshell-theme-picker.sh
bash tests/test-quickshell-theme-picker.sh
```

Expected: FAIL because the old picker still uses a filename `find` list and no `GridView`/catalog helper.

- [ ] **Step 3: Commit only the failing test**

```bash
git add tests/test-quickshell-theme-picker.sh
git commit -m "Define visual theme picker contract"
```

### Task 3: Replace ThemePicker with the visual browser

**Files:**
- Modify: `config/quickshell/awtarchy/ThemePicker.qml`
- Test: `tests/test-quickshell-theme-picker.sh`

**Interfaces:**
- Consumes: `quickshell_theme_catalog.sh` JSON and `quickshell_theme_apply.sh <filename>`.
- Preserves public methods: `openForScreen(target)`, `openFocused()`, `close()`, `toggleFocused()`.
- Preserves IPC methods: `themes.toggle()`, `themes.open()`, `themes.close()`.
- Produces ephemeral `themes`, `activeThemeName`, search/filter state, selected index, and visual card grid.

- [ ] **Step 1: Implement catalog loading and active-theme readback**

Replace the shell `find` process with:

```qml
readonly property string catalogBackend: configHome + "/hypr/scripts/quickshell_theme_catalog.sh"
readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
readonly property string activeThemePath: stateHome + "/awtarchy/active-theme"
```

Use one `Process` for catalog JSON and one read-only process/file view for active-theme identity. Parse invalid catalog JSON as an empty list with a visible error message instead of crashing the shell.

- [ ] **Step 2: Implement filtering and deterministic selection**

Provide functions with stable names:

```qml
function filteredThemes()
function selectedTheme()
function resetSelection()
function moveSelection(delta)
function moveSelectionRow(delta)
function applySelectedTheme()
```

`resetSelection()` selects the active theme if visible, otherwise index `0`, otherwise `-1`.

- [ ] **Step 3: Replace ListView with a responsive GridView**

Use a centered layershell `PanelWindow`, preferred near 900x600 but clamped to the target screen. Each delegate must visually render palette background, active/focus surfaces, readable label text, swatches, active marker, and current selection state using the delegate's own catalog colors rather than global `Theme.*` colors for the preview area.

- [ ] **Step 4: Add explicit apply/cancel footer**

`Apply Theme` invokes only `applySelectedTheme()`. Card click changes selection only. `Cancel`/Escape closes without applying.

- [ ] **Step 5: Implement keyboard grid navigation**

Search field handles Left/Right/Up/Down/Home/End/Enter/Escape. Row movement uses the actual current column count so two-column and three-column layouts behave correctly.

- [ ] **Step 6: Run picker regression to verify GREEN**

Run:

```bash
bash tests/test-quickshell-theme-picker.sh
bash tests/test-quickshell-theme-catalog.sh
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add config/quickshell/awtarchy/ThemePicker.qml tests/test-quickshell-theme-picker.sh
git commit -m "Replace theme picker with visual browser"
```

### Task 4: Shipped-theme catalog validation

**Files:**
- Modify: `tests/test-quickshell-theme-catalog.sh`
- Test: `config/hypr/themes/*`

**Interfaces:**
- Consumes: all shipped theme files.
- Produces: proof every shipped theme can render a complete preview and that catalog order covers all stock files exactly once.

- [ ] **Step 1: Extend the test against repository themes**

Run the helper with a temporary config whose `hypr/themes` is populated from repository stock themes, then assert every catalog object contains valid six-digit `#RRGGBB` preview fields and 8-digit border strings.

```bash
jq -e 'all(.[].palette[]; test("^#[0-9a-fA-F]{6}$"))' <<<"$stock_json" >/dev/null
jq -e 'all(.[].borders[]; test("^[0-9a-fA-F]{8}$"))' <<<"$stock_json" >/dev/null
```

Compare catalog names to sorted non-backup filenames.

- [ ] **Step 2: Run test**

```bash
bash tests/test-quickshell-theme-catalog.sh
```

Expected: PASS for every current stock theme.

- [ ] **Step 3: Commit**

```bash
git add tests/test-quickshell-theme-catalog.sh
git commit -m "Validate shipped theme previews"
```

### Task 5: Managed updater and permanent CI coverage

**Files:**
- Modify: `local/share/awtarchy/quickshell-managed-history.sha256`
- Modify: `.github/workflows/validate-awtarchy.yml`
- Test: `tests/test-quickshell-updater-migration.sh`
- Test: `tests/test-quickshell-theme-catalog.sh`
- Test: `tests/test-quickshell-theme-picker.sh`

**Interfaces:**
- Consumes: final current SHA-256 values of `ThemePicker.qml` and new `quickshell_theme_catalog.sh`.
- Produces: updater recognition and permanent validation of both focused tests.

- [ ] **Step 1: Add focused tests to permanent CI**

Add both tests to Bash syntax, ShellCheck where applicable, and integration execution in `.github/workflows/validate-awtarchy.yml`.

- [ ] **Step 2: Append current managed hashes**

Append exact current SHA-256 entries for:

```text
.config/quickshell/awtarchy/ThemePicker.qml
.config/hypr/scripts/quickshell_theme_catalog.sh
```

Do not remove or reorder historical entries.

- [ ] **Step 3: Run updater and theme regressions**

```bash
bash tests/test-quickshell-theme-catalog.sh
bash tests/test-quickshell-theme-picker.sh
bash tests/test-quickshell-theme-legacy-micro.sh
bash tests/test-quickshell-updater-migration.sh
bash tests/test-quickshell-production-readiness.sh
bash tests/test-quick-settings-layout.sh
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/validate-awtarchy.yml local/share/awtarchy/quickshell-managed-history.sha256
git commit -m "Validate visual theme browser"
```

### Task 6: Final branch validation and real-session handoff

**Files:**
- Verify all modified files on `feature/theme-revamp`.

**Interfaces:**
- Produces: exact 40-character branch commit suitable for `awtarchy git update --branch feature/theme-revamp --commit <sha>`.

- [ ] **Step 1: Run full automated validation**

```bash
bash -n config/hypr/scripts/quickshell_theme_catalog.sh
bash -n config/hypr/scripts/quickshell_theme_apply.sh
shellcheck config/hypr/scripts/quickshell_theme_catalog.sh config/hypr/scripts/quickshell_theme_apply.sh
bash tests/test-quickshell-theme-catalog.sh
bash tests/test-quickshell-theme-picker.sh
bash tests/test-quickshell-theme-legacy-micro.sh
bash tests/test-quickshell-production-readiness.sh
bash tests/test-quickshell-updater-migration.sh
bash tests/test-quick-settings-layout.sh
git diff --check main...HEAD
```

Also run the permanent `Validate Awtarchy` workflow against the feature branch or equivalent exact-head validation workflow.

- [ ] **Step 2: Verify repository preservation contracts**

Confirm no changes to:

```text
config/quickshell/awtarchy/BluetoothMenu.qml
config/hypr/scripts/hyprsunset_ctl.sh
```

and confirm the current Bluetooth and Night Light regression workflows/tests remain green.

- [ ] **Step 3: Real-session checklist**

After installing the exact feature commit:

1. Open the theme picker from the existing shortcut/desktop entry.
2. Confirm cards render immediately with readable palette previews.
3. Search by filename/display name.
4. Navigate all cards with arrows/Home/End.
5. Click multiple cards and confirm the live desktop does not change.
6. Press Escape and confirm the current theme remains unchanged.
7. Reopen, select a different theme, press Enter, and confirm the existing apply pipeline updates shell/apps.
8. Reopen and confirm the newly applied theme is marked Active.
9. Open from Quick Settings and confirm the same browser appears on the correct monitor.
10. Confirm current wallpaper is unchanged throughout.
11. Test on at least one smaller display/scale configuration for clipping and grid-column behavior.

- [ ] **Step 4: Do not merge until runtime confirmation**

Provide the exact branch and commit for testing. Merge/release only after explicit user approval.