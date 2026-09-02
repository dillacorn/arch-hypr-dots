from pathlib import Path

path = Path('bashrc')
text = path.read_text(encoding='utf-8')
old = '''_aur_guard_runtime_activate_candidate() {
  local candidate="$1"
  local target="$2"
  local revision="$3"
  local metadata_tmp hash now

  install -d -m 0700 -- "$_AUR_GUARD_RUNTIME_DATA_DIR" "$_AUR_GUARD_RUNTIME_STATE_DIR" || return 1
  chmod 0600 -- "$candidate" || return 1
  hash=$(sha256sum -- "$candidate" | awk '{print $1}') || return 1
  [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || return 1
  now=$(date +%s) || return 1

  metadata_tmp=$(mktemp "$_AUR_GUARD_RUNTIME_STATE_DIR/.aurguard-runtime.XXXXXX") || return 1
  {
    printf 'version=1\\n'
    printf 'target=%s\\n' "$target"
    printf 'revision=%s\\n' "$revision"
    printf 'fetched_at=%s\\n' "$now"
    printf 'sha256=%s\\n' "$hash"
  } > "$metadata_tmp" || {
    rm -f -- "$metadata_tmp"
    return 1
  }
  chmod 0600 -- "$metadata_tmp" || {
    rm -f -- "$metadata_tmp"
    return 1
  }

  mv -f -- "$candidate" "$_AUR_GUARD_RUNTIME_FILE" || {
    rm -f -- "$metadata_tmp"
    return 1
  }
  mv -f -- "$metadata_tmp" "$_AUR_GUARD_RUNTIME_METADATA" || return 1
  _aur_guard_runtime_cache_matches_target "$target" "$revision"
}
'''
new = '''_aur_guard_runtime_activate_candidate() {
  local candidate="$1"
  local target="$2"
  local revision="$3"
  local metadata_tmp hash now
  local had_previous=0 runtime_backup='' metadata_backup=''

  install -d -m 0700 -- "$_AUR_GUARD_RUNTIME_DATA_DIR" "$_AUR_GUARD_RUNTIME_STATE_DIR" || return 1
  chmod 0600 -- "$candidate" || return 1
  hash=$(sha256sum -- "$candidate" | awk '{print $1}') || return 1
  [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || return 1
  now=$(date +%s) || return 1

  metadata_tmp=$(mktemp "$_AUR_GUARD_RUNTIME_STATE_DIR/.aurguard-runtime.XXXXXX") || return 1
  {
    printf 'version=1\\n'
    printf 'target=%s\\n' "$target"
    printf 'revision=%s\\n' "$revision"
    printf 'fetched_at=%s\\n' "$now"
    printf 'sha256=%s\\n' "$hash"
  } > "$metadata_tmp" || {
    rm -f -- "$metadata_tmp"
    return 1
  }
  chmod 0600 -- "$metadata_tmp" || {
    rm -f -- "$metadata_tmp"
    return 1
  }

  if _aur_guard_runtime_cache_valid; then
    runtime_backup=$(mktemp "$_AUR_GUARD_RUNTIME_DATA_DIR/.aurguard-runtime.previous.XXXXXX") || {
      rm -f -- "$metadata_tmp"
      return 1
    }
    metadata_backup=$(mktemp "$_AUR_GUARD_RUNTIME_STATE_DIR/.aurguard-runtime.previous.XXXXXX") || {
      rm -f -- "$metadata_tmp" "$runtime_backup"
      return 1
    }
    if ! cp -- "$_AUR_GUARD_RUNTIME_FILE" "$runtime_backup" \
        || ! cp -- "$_AUR_GUARD_RUNTIME_METADATA" "$metadata_backup" \
        || ! chmod 0600 -- "$runtime_backup" "$metadata_backup"; then
      rm -f -- "$metadata_tmp" "$runtime_backup" "$metadata_backup"
      return 1
    fi
    had_previous=1
  fi

  if ! mv -f -- "$candidate" "$_AUR_GUARD_RUNTIME_FILE"; then
    rm -f -- "$metadata_tmp" "$runtime_backup" "$metadata_backup"
    return 1
  fi

  if ! mv -f -- "$metadata_tmp" "$_AUR_GUARD_RUNTIME_METADATA"; then
    if (( had_previous )); then
      if ! mv -f -- "$runtime_backup" "$_AUR_GUARD_RUNTIME_FILE"; then
        rm -f -- "$metadata_tmp" "$runtime_backup" "$metadata_backup"
        return 1
      fi
      rm -f -- "$metadata_backup"
    else
      rm -f -- "$_AUR_GUARD_RUNTIME_FILE"
    fi
    rm -f -- "$metadata_tmp"
    return 1
  fi

  if _aur_guard_runtime_cache_matches_target "$target" "$revision"; then
    rm -f -- "$runtime_backup" "$metadata_backup"
    return 0
  fi

  if (( had_previous )); then
    local restore_failed=0
    mv -f -- "$runtime_backup" "$_AUR_GUARD_RUNTIME_FILE" || restore_failed=1
    mv -f -- "$metadata_backup" "$_AUR_GUARD_RUNTIME_METADATA" || restore_failed=1
    if (( restore_failed == 0 )); then
      _aur_guard_runtime_cache_valid || true
    fi
  else
    rm -f -- "$_AUR_GUARD_RUNTIME_FILE" "$_AUR_GUARD_RUNTIME_METADATA"
  fi
  return 1
}
'''
if text.count(old) != 1:
    raise SystemExit(f'expected one runtime activation function, found {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
