from pathlib import Path

path = Path('bashrc')
text = path.read_text(encoding='utf-8')
old = '''  if _aur_guard_runtime_refresh_target "$target" "$revision"; then
    flock -u "$lock_fd" || true
    exec {lock_fd}>&-
    return 0
  fi

  if _aur_guard_runtime_cache_matches_target "$target" "$revision"; then
    printf 'AUR Guard: runtime refresh failed; using cached AurGuard runtime.\\n' >&2
    flock -u "$lock_fd" || true
    exec {lock_fd}>&-
    return 0
  fi
'''
new = '''  if _aur_guard_runtime_refresh_target "$target" "$revision"; then
    flock -u "$lock_fd" || true
    exec {lock_fd}>&-
    return 0
  fi

  if [[ "$force" == force ]]; then
    printf 'AUR Guard: forced runtime refresh failed; existing validated cache was left unchanged.\\n' >&2
    flock -u "$lock_fd" || true
    exec {lock_fd}>&-
    return 1
  fi

  if _aur_guard_runtime_cache_matches_target "$target" "$revision"; then
    printf 'AUR Guard: runtime refresh failed; using cached AurGuard runtime.\\n' >&2
    flock -u "$lock_fd" || true
    exec {lock_fd}>&-
    return 0
  fi
'''
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected one forced-refresh fallback boundary, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
