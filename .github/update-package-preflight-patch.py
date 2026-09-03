from pathlib import Path

root = Path('.')
reconciler = root / 'local/share/awtarchy/awtarchy-package-reconcile.sh'
launcher = root / 'local/bin/awtarchy'

text = reconciler.read_text()
old = 'REVIEW_ONLY=0\nMIGRATE_REPLACEMENTS_ONLY=0\n'
new = 'REVIEW_ONLY=0\nMIGRATE_REPLACEMENTS_ONLY=0\nNEEDS_ACTION_ONLY=0\n'
assert old in text
text = text.replace(old, new, 1)

old = '''    --migrate-replacements)\n      MIGRATE_REPLACEMENTS_ONLY=1\n      ;;\n'''
new = '''    --migrate-replacements)\n      MIGRATE_REPLACEMENTS_ONLY=1\n      ;;\n    --needs-action)\n      NEEDS_ACTION_ONLY=1\n      ;;\n'''
assert old in text
text = text.replace(old, new, 1)

old = '''collect_state\n\nif (( MIGRATE_REPLACEMENTS_ONLY == 1 )); then\n'''
new = '''package_reconciliation_needs_action() {\n  (( CHEESE_REPLACEMENT_NEEDED == 1 \\n      || ${#MISSING_REQUIRED[@]} > 0 \\n      || ${#MISSING_ARCH[@]} > 0 \\n      || ${#MISSING_AUR[@]} > 0 \\n      || ${#MISSING_FLATPAK_IDS[@]} > 0 \\n      || ${#RETIRED_MANAGED[@]} > 0 ))\n}\n\ncollect_state\n\nif (( NEEDS_ACTION_ONLY == 1 )); then\n  if package_reconciliation_needs_action; then\n    exit 10\n  fi\n  exit 0\nfi\n\nif (( MIGRATE_REPLACEMENTS_ONLY == 1 )); then\n'''
assert old in text
text = text.replace(old, new, 1)
reconciler.write_text(text)

text = launcher.read_text()
old = '''run_package_reconciler() {\n  if config_is_git_testing; then\n    run_git_testing_package_reconciler "$@"\n    return $?\n  fi\n\n  require_package_reconciler\n  AWTARCHY_RUNTIME="$RUNTIME" bash "$PACKAGE_RECONCILER" "$@"\n}\n\nrun_failure_reports() {\n'''
new = '''run_package_reconciler() {\n  if config_is_git_testing; then\n    run_git_testing_package_reconciler "$@"\n    return $?\n  fi\n\n  require_package_reconciler\n  AWTARCHY_RUNTIME="$RUNTIME" bash "$PACKAGE_RECONCILER" "$@"\n}\n\noffer_package_reconciliation_before_update() {\n  local arg="" answer="" rc=0\n\n  for arg in "$@"; do\n    [[ $arg == --review-only ]] && return 0\n  done\n\n  if [[ ! -t 0 || ! -t 1 || ! -r /dev/tty || ! -w /dev/tty ]]; then\n    return 0\n  fi\n\n  require_package_reconciler\n  if AWTARCHY_RUNTIME="$RUNTIME" bash "$PACKAGE_RECONCILER" --needs-action >/dev/null 2>&1; then\n    return 0\n  else\n    rc=$?\n  fi\n\n  if (( rc != 10 )); then\n    printf 'WARN: Could not determine Awtarchy package drift; continuing with the config update.\\n' >&2\n    return 0\n  fi\n\n  printf '\\nAwtarchy detected missing, replaced, or retired Awtarchy-managed packages.\\n' >/dev/tty\n  printf 'Review/install package changes before updating configs? [Y/n] ' >/dev/tty\n  IFS= read -r answer </dev/tty || answer=''\n  case "$answer" in\n    n|N|no|NO)\n      printf 'Skipping package reconciliation; continuing with the config update.\\n' >/dev/tty\n      return 0\n      ;;\n  esac\n\n  AWTARCHY_RUNTIME="$RUNTIME" bash "$PACKAGE_RECONCILER"\n}\n\nrun_failure_reports() {\n'''
assert old in text
text = text.replace(old, new, 1)

old = '''        protect_git_state_before_updater_refresh\n        ensure_latest_updater update\n        if config_release_ready_or_noop; then\n'''
new = '''        protect_git_state_before_updater_refresh\n        ensure_latest_updater update\n        offer_package_reconciliation_before_update || rc=$?\n        if [[ -z ${rc:-} ]] && config_release_ready_or_noop; then\n'''
assert old in text
text = text.replace(old, new, 1)

old = '''    update)\n      reject_stable_testing_overrides "$@"\n      protect_git_state_before_updater_refresh "$@"\n      ensure_latest_updater "$@"\n      shift\n      config_release_ready_or_noop "$@" || return 0\n'''
new = '''    update)\n      reject_stable_testing_overrides "$@"\n      protect_git_state_before_updater_refresh "$@"\n      ensure_latest_updater "$@"\n      shift\n      offer_package_reconciliation_before_update "$@"\n      config_release_ready_or_noop "$@" || return 0\n'''
assert old in text
text = text.replace(old, new, 1)
launcher.write_text(text)
