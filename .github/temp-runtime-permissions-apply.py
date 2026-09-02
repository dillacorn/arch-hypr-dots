from pathlib import Path

path = Path('bashrc')
text = path.read_text(encoding='utf-8')
old = '''_aur_guard_runtime_cache_valid() {
  local revision expected_hash actual_hash fetched_at version size

  [[ -f "$_AUR_GUARD_RUNTIME_FILE" && ! -L "$_AUR_GUARD_RUNTIME_FILE" ]] || return 1
  [[ -f "$_AUR_GUARD_RUNTIME_METADATA" && ! -L "$_AUR_GUARD_RUNTIME_METADATA" ]] || return 1

  version=$(_aur_guard_runtime_state_value version "$_AUR_GUARD_RUNTIME_METADATA" 2>/dev/null || true)
'''
new = '''_aur_guard_runtime_cache_valid() {
  local revision expected_hash actual_hash fetched_at version size
  local runtime_uid metadata_uid runtime_mode metadata_mode

  [[ -f "$_AUR_GUARD_RUNTIME_FILE" && ! -L "$_AUR_GUARD_RUNTIME_FILE" ]] || return 1
  [[ -f "$_AUR_GUARD_RUNTIME_METADATA" && ! -L "$_AUR_GUARD_RUNTIME_METADATA" ]] || return 1

  runtime_uid=$(stat -c %u -- "$_AUR_GUARD_RUNTIME_FILE" 2>/dev/null) || return 1
  metadata_uid=$(stat -c %u -- "$_AUR_GUARD_RUNTIME_METADATA" 2>/dev/null) || return 1
  runtime_mode=$(stat -c %a -- "$_AUR_GUARD_RUNTIME_FILE" 2>/dev/null) || return 1
  metadata_mode=$(stat -c %a -- "$_AUR_GUARD_RUNTIME_METADATA" 2>/dev/null) || return 1
  (( runtime_uid == EUID && metadata_uid == EUID )) || return 1
  [[ "$runtime_mode" == 600 && "$metadata_mode" == 600 ]] || return 1

  version=$(_aur_guard_runtime_state_value version "$_AUR_GUARD_RUNTIME_METADATA" 2>/dev/null || true)
'''
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected one runtime cache validation boundary, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
