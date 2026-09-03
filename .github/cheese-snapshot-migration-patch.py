from pathlib import Path

runtime_path = Path("local/share/awtarchy/awtarchy-runtime.sh")
reconciler_path = Path("local/share/awtarchy/awtarchy-package-reconcile.sh")

runtime = runtime_path.read_text(encoding="utf-8")
reconciler = reconciler_path.read_text(encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


runtime = replace_once(
    runtime,
    '  "Multimedia:ffmpeg avahi nss-mdns mpv exiv2 zathura zathura-pdf-mupdf mousai"\n',
    '  "Multimedia:ffmpeg avahi nss-mdns mpv snapshot exiv2 zathura zathura-pdf-mupdf mousai"\n',
    "Snapshot catalog",
)

runtime_ui_marker = "# ──────────────────────────────────────────────────────────────────────────────\n# Built-in raw-key terminal UI\n"
runtime_helper = '''migrate_cheese_to_snapshot_stage() {
  local reconciler="$1" runtime_source="$2"
  local managed_file="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}"

  [[ -f "$reconciler" && ! -L "$reconciler" ]] \\
    || die "Package replacement reconciler is unavailable or unsafe: ${reconciler}"
  [[ -r "$runtime_source" && ! -L "$runtime_source" ]] \\
    || die "Package replacement runtime is unavailable or unsafe: ${runtime_source}"

  AWTARCHY_RUNTIME="$runtime_source" \\
    AWTARCHY_MANAGED_PACKAGES_FILE="$managed_file" \\
    bash "$reconciler" --migrate-replacements
}

'''
if "migrate_cheese_to_snapshot_stage()" not in runtime:
    runtime = replace_once(
        runtime,
        runtime_ui_marker,
        runtime_helper + runtime_ui_marker,
        "runtime migration helper",
    )

runtime = replace_once(
    runtime,
    "  prepare_base_install\n  install_arch_repo_apps_stage\n  if [[ \"$IS_LAPTOP\" == true && \"$IS_VM\" == false ]]; then\n",
    "  prepare_base_install\n  install_arch_repo_apps_stage\n  migrate_cheese_to_snapshot_stage \\\n    \"${REPO_DIR}/local/share/awtarchy/awtarchy-package-reconcile.sh\" \\\n    \"${BASH_SOURCE[0]}\"\n  if [[ \"$IS_LAPTOP\" == true && \"$IS_VM\" == false ]]; then\n",
    "installer migration call",
)

runtime = replace_once(
    runtime,
    "  ensure_quickshell_update_prerequisites\n  snapshot_quickshell_update_legacy_paths\n",
    "  ensure_quickshell_update_prerequisites\n  migrate_cheese_to_snapshot_stage \\\n    \"${repo_dir}/local/share/awtarchy/awtarchy-package-reconcile.sh\" \\\n    \"${repo_dir}/local/share/awtarchy/awtarchy-runtime.sh\"\n  snapshot_quickshell_update_legacy_paths\n",
    "updater migration call",
)

reconciler = replace_once(
    reconciler,
    "REVIEW_ONLY=0\n",
    "REVIEW_ONLY=0\nMIGRATE_REPLACEMENTS_ONLY=0\n",
    "replacement mode variable",
)

reconciler = replace_once(
    reconciler,
    'SYSTEM_TYPE="unknown"\nLY_STATUS="not installed"\nAUR_SCAN_BIN="/usr/bin/aur-scan"\n',
    'SYSTEM_TYPE="unknown"\nLY_STATUS="not installed"\nCHEESE_REPLACEMENT_NEEDED=0\nAUR_SCAN_BIN="/usr/bin/aur-scan"\n',
    "replacement state variable",
)

reconciler = replace_once(
    reconciler,
    "    --review)\n      REVIEW_ONLY=1\n      ;;\n",
    "    --review)\n      REVIEW_ONLY=1\n      ;;\n    --migrate-replacements)\n      MIGRATE_REPLACEMENTS_ONLY=1\n      ;;\n",
    "replacement argument",
)

reconciler = replace_once(
    reconciler,
    "  detect_system_type\n  detect_ly_status\n\n",
    "  detect_system_type\n  detect_ly_status\n  package_installed cheese && CHEESE_REPLACEMENT_NEEDED=1\n\n",
    "replacement detection",
)

reconciler = replace_once(
    reconciler,
    "  printf 'Ly TTY login manager: %s\\n' \"$LY_STATUS\"\n  printf '\\n'\n  print_list 'Missing required Awtarchy packages:' \"${MISSING_REQUIRED[@]}\"\n",
    "  printf 'Ly TTY login manager: %s\\n' \"$LY_STATUS\"\n  printf '\\n'\n  printf '%s\\n' 'Required package replacements:'\n  if (( CHEESE_REPLACEMENT_NEEDED == 1 )); then\n    printf '  - cheese -> snapshot\\n'\n  else\n    printf '  (none)\\n'\n  fi\n  printf '\\n'\n  print_list 'Missing required Awtarchy packages:' \"${MISSING_REQUIRED[@]}\"\n",
    "replacement review output",
)

replacement_helper = '''apply_cheese_snapshot_replacement() {
  (( CHEESE_REPLACEMENT_NEEDED == 1 )) || return 0

  require_sudo
  log "Replacing retired Cheese camera app with Snapshot..."
  if ! package_installed snapshot; then
    as_root pacman -S --needed --noconfirm snapshot
  fi
  record_managed_packages snapshot
  as_root pacman -Rns --noconfirm cheese
  forget_managed_packages cheese
  CHEESE_REPLACEMENT_NEEDED=0
  log "Replaced Cheese with Snapshot."
}

'''
if "apply_cheese_snapshot_replacement()" not in reconciler:
    reconciler = replace_once(
        reconciler,
        "flatpak_scope() {\n",
        replacement_helper + "flatpak_scope() {\n",
        "replacement apply helper",
    )

reconciler = replace_once(
    reconciler,
    "collect_state\n\nif (( REVIEW_ONLY == 1 )); then\n",
    "collect_state\n\nif (( MIGRATE_REPLACEMENTS_ONLY == 1 )); then\n  apply_cheese_snapshot_replacement\n  exit 0\nfi\n\nif (( REVIEW_ONLY == 1 )); then\n",
    "replacement-only execution",
)

reconciler = replace_once(
    reconciler,
    "selected_values retired_values retired_flags selected_retired\n\ninstall_arch=(\"${MISSING_REQUIRED[@]}\" \"${selected_arch[@]}\")\n",
    "selected_values retired_values retired_flags selected_retired\n\nif (( CHEESE_REPLACEMENT_NEEDED == 1 )); then\n  array_contains cheese \"${selected_retired[@]}\" || selected_retired+=(cheese)\nfi\n\ninstall_arch=(\"${MISSING_REQUIRED[@]}\" \"${selected_arch[@]}\")\nif (( CHEESE_REPLACEMENT_NEEDED == 1 )) && ! package_installed snapshot; then\n  install_arch+=(snapshot)\nfi\nsort_unique_array install_arch\n",
    "interactive replacement plan",
)

reconciler = replace_once(
    reconciler,
    "printf '\\nNo current installed package will be removed merely because it was not selected.\\n\\n' >/dev/tty\n",
    "printf '\\nNo current installed package will be removed merely because it was not selected; explicit replacements may be migrated.\\n\\n' >/dev/tty\n",
    "replacement plan notice",
)

runtime_path.write_text(runtime, encoding="utf-8")
reconciler_path.write_text(reconciler, encoding="utf-8")
print("Applied Cheese -> Snapshot migration integration.")
