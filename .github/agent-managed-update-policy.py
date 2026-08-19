#!/usr/bin/env python3
from pathlib import Path
import sys


def patch_tests() -> None:
    path = Path("tests/test-quickshell-updater-migration.sh")
    text = path.read_text()

    insert_marker = "\nseed_old_home() {\n"
    if "hypr_conflict_parent=" not in text:
        insert = r'''

hypr_conflict_parent="${TMP}/hypr-conflict-archive"
hypr_conflict_root="${hypr_conflict_parent}/awtarchy-${TEST_COMMIT}"
mkdir -p "$hypr_conflict_parent"
cp -a -- "$archive_root" "$hypr_conflict_root"
hypr_default_line='hl.env("QT_SCALE_FACTOR", "1")'
hypr_local_line='hl.env("QT_SCALE_FACTOR", "1.25")'
hypr_release_line='hl.env("QT_SCALE_FACTOR", "1.5")'
replace_once \
  "$hypr_conflict_root/config/hypr/hyprland.lua" \
  "$hypr_default_line" \
  "$hypr_release_line"
printf '%s\n' '// hyprland conflict target marker' \
  >>"$hypr_conflict_root/config/quickshell/awtarchy/Bar.qml"
tar -czf "${TMP}/hypr-conflict-testing-commit.tar.gz" \
  -C "$hypr_conflict_parent" "$(basename "$hypr_conflict_root")"
'''
        if text.count(insert_marker) != 1:
            raise SystemExit("seed_old_home marker mismatch")
        text = text.replace(insert_marker, insert + insert_marker, 1)

    text = text.replace(
        "# preserve an actual QML customization and hyprland.lua, and repeat retired UI\n",
        "# replace a modified managed QML file with backup, preserve hyprland.lua, and repeat retired UI\n",
        1,
    )
    text = text.replace(
        "personal_launcher_sha=\"$(sha256sum \"$personal_launcher\" | awk '{print $1}')\"\n",
        "",
        1,
    )

    old = r'''[[ $personal_launcher_sha == "$(sha256sum "$personal_launcher" | awk '{print $1}')" ]] \
  || fail "updater replaced a genuine Launcher.qml customization"
'''
    new = r'''cmp -s "$personal_launcher" "$ROOT/config/quickshell/awtarchy/Launcher.qml" \
  || fail "updater did not restore the release Launcher.qml over a local managed-file edit"
repair_launcher_backup="$(
  find "$home/.config/quickshell/awtarchy" \
    -maxdepth 1 -type f -name 'Launcher.qml.backup*' \
    -exec grep -lF -- '// personal desktop launcher customization' {} + | head -n1
)"
[[ -n $repair_launcher_backup ]] \
  || fail "updater did not back up the overwritten Launcher.qml customization"
'''
    if text.count(old) != 1:
        raise SystemExit("repair Launcher assertion mismatch")
    text = text.replace(old, new, 1)

    start_marker = "# A real three-way conflict must offer a per-file decision."
    end_marker = 'failure_packages="${TMP}/failure-packages"\n'
    start = text.find(start_marker)
    end = text.find(end_marker, start)
    if start < 0 or end < 0:
        raise SystemExit("conflict regression block markers not found")

    replacement = r'''# Non-Hyprland managed files always take the release copy in preserve mode.
# Local edits are retained as backups and no per-file conflict prompt is shown.
conflict_release_home="${TMP}/conflict-release-home"
conflict_release_packages="${TMP}/conflict-release-packages"
conflict_release_managed="${TMP}/conflict-release-managed"
cp -a -- "$home" "$conflict_release_home"
cp -- "$package_state" "$conflict_release_packages"
cp -- "$managed_packages" "$conflict_release_managed"
replace_once \
  "$conflict_release_home/.config/quickshell/awtarchy/Launcher.qml" \
  "$launcher_default_line" \
  "$launcher_local_line"
env \
  "${update_env[@]}" \
  "HOME=$conflict_release_home" \
  "AWTARCHY_TEST_TARGET_HOME=$conflict_release_home" \
  "AWTARCHY_TEST_ARCHIVE=${TMP}/conflict-testing-commit.tar.gz" \
  "AWTARCHY_TEST_PACKAGE_STATE=$conflict_release_packages" \
  "AWTARCHY_MANAGED_PACKAGES_FILE=$conflict_release_managed" \
  "AWTARCHY_TEST_HYPRIDLE_STATE=${TMP}/conflict-release-hypridle.state" \
  "HYPRLAND_INSTANCE_SIGNATURE=" \
  "$conflict_release_home/.local/bin/awtarchy" git update \
  --branch "$TEST_BRANCH" --commit "$TEST_COMMIT" \
  >"${TMP}/conflict-release.out" 2>&1
grep -Fq "$launcher_release_line" \
  "$conflict_release_home/.config/quickshell/awtarchy/Launcher.qml" \
  || fail "preserve mode did not install the release Launcher.qml"
release_backup="$(
  find "$conflict_release_home/.config/quickshell/awtarchy" \
    -maxdepth 1 -type f -name 'Launcher.qml.backup*' \
    -exec grep -lF -- "$launcher_local_line" {} + | head -n1
)"
[[ -n "$release_backup" ]] \
  || fail "preserve mode did not back up the overwritten Launcher.qml"
grep -Fq '// conflict-policy target marker' \
  "$conflict_release_home/.config/quickshell/awtarchy/Bar.qml" \
  || fail "preserve mode did not finish unrelated managed updates"
! grep -Fq 'Managed-file merge conflict:' "${TMP}/conflict-release.out" \
  || fail "non-Hyprland conflict unexpectedly prompted for a per-file decision"
! grep -Fq 'Automatic merge conflict requires a terminal' "${TMP}/conflict-release.out" \
  || fail "non-Hyprland conflict still depends on conflict-policy prompting"

# hyprland.lua is the one preservation exception. When both the user and the
# release change overlapping lines, keep the local file automatically.
hypr_conflict_home="${TMP}/hypr-conflict-home"
hypr_conflict_packages="${TMP}/hypr-conflict-packages"
hypr_conflict_managed="${TMP}/hypr-conflict-managed"
cp -a -- "$home" "$hypr_conflict_home"
cp -- "$package_state" "$hypr_conflict_packages"
cp -- "$managed_packages" "$hypr_conflict_managed"
replace_once \
  "$hypr_conflict_home/.config/hypr/hyprland.lua" \
  "$hypr_default_line" \
  "$hypr_local_line"
env \
  "${update_env[@]}" \
  "HOME=$hypr_conflict_home" \
  "AWTARCHY_TEST_TARGET_HOME=$hypr_conflict_home" \
  "AWTARCHY_TEST_ARCHIVE=${TMP}/hypr-conflict-testing-commit.tar.gz" \
  "AWTARCHY_TEST_PACKAGE_STATE=$hypr_conflict_packages" \
  "AWTARCHY_MANAGED_PACKAGES_FILE=$hypr_conflict_managed" \
  "AWTARCHY_TEST_HYPRIDLE_STATE=${TMP}/hypr-conflict-hypridle.state" \
  "HYPRLAND_INSTANCE_SIGNATURE=" \
  "$hypr_conflict_home/.local/bin/awtarchy" git update \
  --branch "$TEST_BRANCH" --commit "$TEST_COMMIT" \
  >"${TMP}/hypr-conflict.out" 2>&1
grep -Fq "$hypr_local_line" \
  "$hypr_conflict_home/.config/hypr/hyprland.lua" \
  || fail "hyprland.lua merge conflict did not keep the local configuration"
! grep -Fq "$hypr_release_line" \
  "$hypr_conflict_home/.config/hypr/hyprland.lua" \
  || fail "hyprland.lua merge conflict installed the overlapping release line"
grep -Fq '// hyprland conflict target marker' \
  "$hypr_conflict_home/.config/quickshell/awtarchy/Bar.qml" \
  || fail "hyprland.lua conflict prevented unrelated managed updates"
! grep -Fq 'Managed-file merge conflict:' "${TMP}/hypr-conflict.out" \
  || fail "hyprland.lua conflict unexpectedly prompted for a decision"
grep -Fq 'Hyprland merge conflict; kept the local file and skipped overlapping release changes: .config/hypr/hyprland.lua' \
  "${TMP}/hypr-conflict.out" \
  || fail "hyprland.lua automatic preservation was not reported"

'''
    text = text[:start] + replacement + text[end:]
    path.write_text(text)


def patch_code() -> None:
    runtime = Path("local/share/awtarchy/awtarchy-runtime.sh")
    text = runtime.read_text()
    text = text.replace('CONFLICT_POLICY="prompt"', 'CONFLICT_POLICY="keep-local"', 1)

    start = text.find("select_merge_conflict_resolution() {\n")
    end = text.find("\ninstall_live_file() {\n", start)
    if start < 0 or end < 0:
        raise SystemExit("merge conflict prompt function markers not found")
    text = text[:start] + text[end + 1:]

    start = text.find("apply_plan() {\n")
    end = text.find("\nfix_managed_perms() {\n", start)
    if start < 0 or end < 0:
        raise SystemExit("apply_plan markers not found")

    new_apply_plan = r'''apply_plan() {
  local plan_file="$1"
  local class rel local_file target_file baseline_file merge_tmp
  while IFS=$'\t' read -r class rel local_file target_file baseline_file; do
    [[ -n "$class" ]] || continue
    validate_plan_row "$class" "$rel" "$local_file" "$target_file" "$baseline_file" \
      || { FAILED+=("${rel:-unsafe-plan-row}"); rollback_changes; return 1; }
    case "$class" in
      NEW|OUTDATED)
        install_live_file "$rel" "$target_file" "$local_file" 0 || return 1
        ;;
      USER)
        if [[ "$UPDATE_MODE" == "preserve" && "$rel" == ".config/hypr/hyprland.lua" ]]; then
          PRESERVED+=("$rel")
        else
          install_live_file "$rel" "$target_file" "$local_file" 1 || return 1
        fi
        ;;
      LEGACY)
        if [[ "$UPDATE_MODE" == "preserve" && "$rel" == ".config/hypr/hyprland.lua" ]]; then
          PRESERVED+=("$rel")
          warn "Legacy Hyprland difference retained because no trusted old baseline exists: $rel"
        else
          install_live_file "$rel" "$target_file" "$local_file" 1 || return 1
        fi
        ;;
      BOTH)
        if [[ "$UPDATE_MODE" == "preserve" && "$rel" == ".config/hypr/hyprland.lua" ]]; then
          merge_tmp="${TMPD}/merge/${rel}"
          mkdir -p -- "$(dirname "$merge_tmp")"
          if attempt_merge "$local_file" "$baseline_file" "$target_file" "$rel" "$merge_tmp"; then
            install_live_file "$rel" "$merge_tmp" "$local_file" 1 || return 1
            MERGED+=("$rel")
          else
            case "$CONFLICT_POLICY" in
              use-release)
                install_live_file "$rel" "$target_file" "$local_file" 1 || return 1
                warn "Explicit conflict policy installed the release Hyprland file and kept the local file as a backup: $rel"
                ;;
              abort)
                FAILED+=("$rel")
                warn "Explicit conflict policy aborted on Hyprland merge conflict: $rel"
                rollback_changes
                return 1
                ;;
              prompt|keep-local)
                PRESERVED+=("$rel")
                warn "Hyprland merge conflict; kept the local file and skipped overlapping release changes: $rel"
                ;;
              *)
                FAILED+=("$rel")
                warn "Unsupported merge conflict policy: $CONFLICT_POLICY"
                rollback_changes
                return 1
                ;;
            esac
          fi
        else
          install_live_file "$rel" "$target_file" "$local_file" 1 || return 1
        fi
        ;;
      REMOVED)
        remove_live_file "$rel" "$local_file" 0 || return 1
        ;;
      ORPHANED)
        if [[ "$UPDATE_MODE" == "preserve" ]]; then
          warn "A locally modified managed file was removed upstream; removing it from the live tree and keeping a backup: $rel"
        fi
        remove_live_file "$rel" "$local_file" 1 || return 1
        ;;
    esac
  done <"$plan_file"
}
'''
    text = text[:start] + new_apply_plan + text[end:]

    text = text.replace(
        "Update managed files and merge personal modifications (recommended)",
        "Update managed files and preserve hyprland.lua customizations (recommended)",
    )
    text = text.replace(
        "Update configs (merge personal modifications)",
        "Update configs (preserve Hyprland customizations)",
    )
    old_log = '  log "Selected update mode: ${UPDATE_MODE}"\n'
    new_log = (
        '  if [[ "$UPDATE_MODE" == "preserve" ]]; then\n'
        '    log "Selected update mode: preserve hyprland.lua; update other managed files"\n'
        '  else\n'
        '    log "Selected update mode: clean"\n'
        '  fi\n'
    )
    if text.count(old_log) != 1:
        raise SystemExit("selected update mode log marker mismatch")
    text = text.replace(old_log, new_log, 1)
    runtime.write_text(text)

    launcher = Path("local/bin/awtarchy")
    text = launcher.read_text().replace(
        "Update configs (merge personal modifications)",
        "Update configs (preserve Hyprland customizations)",
    )
    launcher.write_text(text)

    readme = Path("README.md")
    text = readme.read_text()
    text = text.replace(
        "awtarchy update          Update from the latest published release while preserving personal modifications",
        "awtarchy update          Update from the latest published release; preserve hyprland.lua and back up overwritten local managed-file edits",
        1,
    )
    text = text.replace(
        "Preserve mode keeps personalized managed files where possible, creates backups when required, migrates supported Hyprland customizations, and removes retired Awtarchy-managed shell packages and configuration that are no longer used.",
        "Preserve mode keeps hyprland.lua customizations where possible. Other Awtarchy-managed files are updated to the release copy, with local edits backed up before replacement. It also migrates supported Hyprland customizations and removes retired Awtarchy-managed shell packages and configuration that are no longer used.",
        1,
    )
    readme.write_text(text)


if len(sys.argv) != 2 or sys.argv[1] not in {"tests", "code"}:
    raise SystemExit("usage: agent-managed-update-policy.py tests|code")

if sys.argv[1] == "tests":
    patch_tests()
else:
    patch_code()
