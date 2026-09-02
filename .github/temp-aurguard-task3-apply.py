from pathlib import Path

path = Path("bashrc")
text = path.read_text(encoding="utf-8")

if "_aur_guard_runtime_dispatch()" in text:
    raise SystemExit("AurGuard runtime dispatcher already exists")
if "# AWTARCHY_AURGUARD_RUNTIME_BEGIN v1" in text or "# AWTARCHY_AURGUARD_RUNTIME_END v1" in text:
    raise SystemExit("AurGuard runtime markers already exist")

anchor = "# --- AUR Guard ---\n"
if text.count(anchor) != 1:
    raise SystemExit(f"expected one AUR Guard anchor, found {text.count(anchor)}")

bootstrap = r'''# --- AUR Guard runtime bootstrap ---
# The shell-installed bootstrap is deliberately small. It refreshes the full
# AurGuard implementation from an exact Awtarchy commit, validates it, caches
# it for 24 hours, then executes public AurGuard commands in a child Bash.
_AUR_GUARD_RUNTIME_MAX_AGE=86400
_AUR_GUARD_RUNTIME_MAX_BYTES=$((4 * 1024 * 1024))
_AUR_GUARD_RUNTIME_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/awtarchy"
_AUR_GUARD_RUNTIME_FILE="$_AUR_GUARD_RUNTIME_DATA_DIR/aurguard-runtime.sh"
_AUR_GUARD_RUNTIME_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy"
_AUR_GUARD_RUNTIME_METADATA="$_AUR_GUARD_RUNTIME_STATE_DIR/aurguard-runtime"
_AUR_GUARD_RUNTIME_LOCK="$_AUR_GUARD_RUNTIME_STATE_DIR/aurguard-runtime.lock"
_AUR_GUARD_RUNTIME_GIT_TEST_STATE="$_AUR_GUARD_RUNTIME_STATE_DIR/git-testing"
_AUR_GUARD_RUNTIME_CONFIG_STATE="$_AUR_GUARD_RUNTIME_STATE_DIR/config-version"
_AUR_GUARD_RUNTIME_API='https://api.github.com/repos/dillacorn/awtarchy'
_AUR_GUARD_RUNTIME_RAW='https://raw.githubusercontent.com/dillacorn/awtarchy'

_aur_guard_runtime_state_value() {
  local key="$1"
  local file="$2"

  [[ -f "$file" && ! -L "$file" ]] || return 1
  awk -F= -v wanted="$key" '
    $1 == wanted {
      sub(/^[^=]*=/, "")
      print
      found = 1
      exit
    }
    END { exit found ? 0 : 1 }
  ' "$file"
}

_aur_guard_runtime_target() {
  local branch='' revision='' config_tag=''

  if [[ -f "$_AUR_GUARD_RUNTIME_GIT_TEST_STATE" \
      && ! -L "$_AUR_GUARD_RUNTIME_GIT_TEST_STATE" \
      && -f "$_AUR_GUARD_RUNTIME_CONFIG_STATE" \
      && ! -L "$_AUR_GUARD_RUNTIME_CONFIG_STATE" ]]; then
    branch=$(_aur_guard_runtime_state_value branch "$_AUR_GUARD_RUNTIME_GIT_TEST_STATE" 2>/dev/null || true)
    revision=$(_aur_guard_runtime_state_value revision "$_AUR_GUARD_RUNTIME_GIT_TEST_STATE" 2>/dev/null || true)
    config_tag=$(_aur_guard_runtime_state_value tag "$_AUR_GUARD_RUNTIME_CONFIG_STATE" 2>/dev/null || true)

    if [[ "$revision" =~ ^[0-9a-fA-F]{40}$ \
        && "$branch" =~ ^[A-Za-z0-9._/-]+$ \
        && "$branch" != -* \
        && "$config_tag" == "${branch}@${revision}" ]]; then
      printf 'git:%s\t%s\n' "$branch" "${revision,,}"
      return 0
    fi
  fi

  printf 'main\t\n'
}

_aur_guard_runtime_metadata_target() {
  _aur_guard_runtime_state_value target "$_AUR_GUARD_RUNTIME_METADATA"
}

_aur_guard_runtime_cache_valid() {
  local revision expected_hash actual_hash fetched_at version size

  [[ -f "$_AUR_GUARD_RUNTIME_FILE" && ! -L "$_AUR_GUARD_RUNTIME_FILE" ]] || return 1
  [[ -f "$_AUR_GUARD_RUNTIME_METADATA" && ! -L "$_AUR_GUARD_RUNTIME_METADATA" ]] || return 1

  version=$(_aur_guard_runtime_state_value version "$_AUR_GUARD_RUNTIME_METADATA" 2>/dev/null || true)
  revision=$(_aur_guard_runtime_state_value revision "$_AUR_GUARD_RUNTIME_METADATA" 2>/dev/null || true)
  expected_hash=$(_aur_guard_runtime_state_value sha256 "$_AUR_GUARD_RUNTIME_METADATA" 2>/dev/null || true)
  fetched_at=$(_aur_guard_runtime_state_value fetched_at "$_AUR_GUARD_RUNTIME_METADATA" 2>/dev/null || true)

  [[ "$version" == 1 ]] || return 1
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || return 1
  [[ "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
  [[ "$fetched_at" =~ ^[0-9]+$ ]] || return 1

  size=$(stat -c %s -- "$_AUR_GUARD_RUNTIME_FILE" 2>/dev/null) || return 1
  (( size > 0 && size <= _AUR_GUARD_RUNTIME_MAX_BYTES )) || return 1

  grep -Fxq '# AWTARCHY_AURGUARD_RUNTIME v1' "$_AUR_GUARD_RUNTIME_FILE" || return 1
  grep -Eq '^aurverify\(\)[[:space:]]*\{' "$_AUR_GUARD_RUNTIME_FILE" || return 1
  grep -Eq '^aurinstall\(\)[[:space:]]*\{' "$_AUR_GUARD_RUNTIME_FILE" || return 1
  grep -Eq '^aurguard\(\)[[:space:]]*\{' "$_AUR_GUARD_RUNTIME_FILE" || return 1
  grep -Eq '^_aur_guard_scan_checkout_with_aur_scan\(\)[[:space:]]*\{' "$_AUR_GUARD_RUNTIME_FILE" || return 1
  command bash -n "$_AUR_GUARD_RUNTIME_FILE" >/dev/null 2>&1 || return 1

  actual_hash=$(sha256sum -- "$_AUR_GUARD_RUNTIME_FILE" 2>/dev/null | awk '{print $1}') || return 1
  [[ "$actual_hash" == "$expected_hash" ]]
}

_aur_guard_runtime_cache_matches_target() {
  local target="$1"
  local revision="$2"
  local cached_target cached_revision

  _aur_guard_runtime_cache_valid || return 1
  cached_target=$(_aur_guard_runtime_metadata_target 2>/dev/null || true)
  cached_revision=$(_aur_guard_runtime_state_value revision "$_AUR_GUARD_RUNTIME_METADATA" 2>/dev/null || true)

  if [[ "$target" == main ]]; then
    [[ "$cached_target" == main ]]
  else
    [[ "$cached_target" == "$target" && "$cached_revision" == "$revision" ]]
  fi
}

_aur_guard_runtime_cache_fresh_for_target() {
  local target="$1"
  local revision="$2"
  local fetched_at now age

  _aur_guard_runtime_cache_matches_target "$target" "$revision" || return 1
  fetched_at=$(_aur_guard_runtime_state_value fetched_at "$_AUR_GUARD_RUNTIME_METADATA" 2>/dev/null || true)
  [[ "$fetched_at" =~ ^[0-9]+$ ]] || return 1
  now=$(date +%s) || return 1
  (( fetched_at <= now + 300 )) || return 1
  age=$((now - fetched_at))
  (( age >= 0 && age < _AUR_GUARD_RUNTIME_MAX_AGE ))
}

_aur_guard_runtime_resolve_main() {
  local payload revision

  type -P curl >/dev/null 2>&1 || return 127
  type -P python3 >/dev/null 2>&1 || return 127

  payload=$(command curl -fsSL \
    --connect-timeout 5 --max-time 15 --retry 1 \
    "$_AUR_GUARD_RUNTIME_API/commits/main") || return 1
  revision=$(python3 - "$payload" <<'PY_RUNTIME_SHA'
import json
import re
import sys

try:
    payload = json.loads(sys.argv[1])
    revision = str(payload.get("sha") or "").strip().lower()
except (IndexError, TypeError, json.JSONDecodeError):
    raise SystemExit(1)
if not re.fullmatch(r"[0-9a-f]{40}", revision):
    raise SystemExit(1)
print(revision)
PY_RUNTIME_SHA
  ) || return 1

  printf '%s\n' "$revision"
}

_aur_guard_runtime_fetch_exact_source() {
  local revision="$1"
  local output="$2"

  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || return 1
  type -P curl >/dev/null 2>&1 || return 127

  command curl -fsSL \
    --connect-timeout 5 --max-time 30 --retry 1 \
    -o "$output" \
    "$_AUR_GUARD_RUNTIME_RAW/$revision/bashrc"
}

_aur_guard_runtime_extract_candidate() {
  local source="$1"
  local candidate="$2"
  local source_size candidate_size

  type -P python3 >/dev/null 2>&1 || return 127

  source_size=$(stat -c %s -- "$source" 2>/dev/null) || return 1
  (( source_size > 0 && source_size <= _AUR_GUARD_RUNTIME_MAX_BYTES * 2 )) || return 1

  python3 - "$source" "$candidate" <<'PY_RUNTIME_EXTRACT'
import sys
from pathlib import Path

source = Path(sys.argv[1])
candidate = Path(sys.argv[2])
begin = "# AWTARCHY_AURGUARD_RUNTIME_BEGIN v1"
end = "# AWTARCHY_AURGUARD_RUNTIME_END v1"

try:
    text = source.read_text(encoding="utf-8")
except (OSError, UnicodeError):
    raise SystemExit(1)

if text.count(begin) != 1 or text.count(end) != 1:
    raise SystemExit(1)
start = text.index(begin) + len(begin)
finish = text.index(end, start)
body = text[start:finish].strip("\n")
if not body:
    raise SystemExit(1)

candidate.write_text(
    "# AWTARCHY_AURGUARD_RUNTIME v1\n"
    "# shellcheck shell=bash\n"
    + body
    + "\n",
    encoding="utf-8",
)
PY_RUNTIME_EXTRACT
  || return 1

  candidate_size=$(stat -c %s -- "$candidate" 2>/dev/null) || return 1
  (( candidate_size > 0 && candidate_size <= _AUR_GUARD_RUNTIME_MAX_BYTES )) || return 1
  grep -Fxq '# AWTARCHY_AURGUARD_RUNTIME v1' "$candidate" || return 1
  grep -Eq '^aurverify\(\)[[:space:]]*\{' "$candidate" || return 1
  grep -Eq '^aurinstall\(\)[[:space:]]*\{' "$candidate" || return 1
  grep -Eq '^aurguard\(\)[[:space:]]*\{' "$candidate" || return 1
  grep -Eq '^_aur_guard_scan_checkout_with_aur_scan\(\)[[:space:]]*\{' "$candidate" || return 1
  command bash -n "$candidate" >/dev/null 2>&1
}

_aur_guard_runtime_activate_candidate() {
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
    printf 'version=1\n'
    printf 'target=%s\n' "$target"
    printf 'revision=%s\n' "$revision"
    printf 'fetched_at=%s\n' "$now"
    printf 'sha256=%s\n' "$hash"
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

_aur_guard_runtime_refresh_target() {
  local target="$1"
  local pinned_revision="$2"
  local attempt resolved before after source candidate
  local work_dir

  install -d -m 0700 -- "$_AUR_GUARD_RUNTIME_DATA_DIR" "$_AUR_GUARD_RUNTIME_STATE_DIR" || return 1
  work_dir=$(mktemp -d "$_AUR_GUARD_RUNTIME_DATA_DIR/.aurguard-refresh.XXXXXX") || return 1

  if [[ "$target" != main ]]; then
    [[ "$pinned_revision" =~ ^[0-9a-f]{40}$ ]] || {
      rm -rf -- "$work_dir"
      return 1
    }
    source="$work_dir/bashrc"
    candidate="$work_dir/runtime"
    if ! _aur_guard_runtime_fetch_exact_source "$pinned_revision" "$source" \
        || ! _aur_guard_runtime_extract_candidate "$source" "$candidate" \
        || ! _aur_guard_runtime_activate_candidate "$candidate" "$target" "$pinned_revision"; then
      rm -rf -- "$work_dir"
      return 1
    fi
    rm -rf -- "$work_dir"
    return 0
  fi

  for attempt in 1 2; do
    before=$(_aur_guard_runtime_resolve_main) || {
      rm -rf -- "$work_dir"
      return 1
    }
    source="$work_dir/bashrc.$attempt"
    candidate="$work_dir/runtime.$attempt"
    _aur_guard_runtime_fetch_exact_source "$before" "$source" || {
      rm -rf -- "$work_dir"
      return 1
    }
    _aur_guard_runtime_extract_candidate "$source" "$candidate" || {
      rm -rf -- "$work_dir"
      return 1
    }
    after=$(_aur_guard_runtime_resolve_main) || {
      rm -rf -- "$work_dir"
      return 1
    }
    if [[ "$before" != "$after" ]]; then
      rm -f -- "$source" "$candidate"
      continue
    fi
    resolved="$before"
    if _aur_guard_runtime_activate_candidate "$candidate" main "$resolved"; then
      rm -rf -- "$work_dir"
      return 0
    fi
    rm -rf -- "$work_dir"
    return 1
  done

  rm -rf -- "$work_dir"
  return 1
}

_aur_guard_runtime_ensure() {
  local force="${1:-normal}"
  local target_spec target revision lock_fd

  IFS=$'\t' read -r target revision < <(_aur_guard_runtime_target) || return 1

  if [[ "$force" != force ]] \
      && _aur_guard_runtime_cache_fresh_for_target "$target" "$revision"; then
    return 0
  fi

  type -P flock >/dev/null 2>&1 || {
    if _aur_guard_runtime_cache_matches_target "$target" "$revision"; then
      printf 'AUR Guard: runtime refresh unavailable; using cached AurGuard runtime.\n' >&2
      return 0
    fi
    printf 'AUR Guard: flock is required to refresh the AurGuard runtime.\n' >&2
    return 127
  }

  install -d -m 0700 -- "$_AUR_GUARD_RUNTIME_STATE_DIR" || return 1
  exec {lock_fd}>"$_AUR_GUARD_RUNTIME_LOCK" || return 1
  flock "$lock_fd" || {
    exec {lock_fd}>&-
    return 1
  }

  IFS=$'\t' read -r target revision < <(_aur_guard_runtime_target) || {
    flock -u "$lock_fd" || true
    exec {lock_fd}>&-
    return 1
  }

  if [[ "$force" != force ]] \
      && _aur_guard_runtime_cache_fresh_for_target "$target" "$revision"; then
    flock -u "$lock_fd" || true
    exec {lock_fd}>&-
    return 0
  fi

  if _aur_guard_runtime_refresh_target "$target" "$revision"; then
    flock -u "$lock_fd" || true
    exec {lock_fd}>&-
    return 0
  fi

  if _aur_guard_runtime_cache_matches_target "$target" "$revision"; then
    printf 'AUR Guard: runtime refresh failed; using cached AurGuard runtime.\n' >&2
    flock -u "$lock_fd" || true
    exec {lock_fd}>&-
    return 0
  fi

  printf 'AUR Guard: could not obtain a validated AurGuard runtime for the current Awtarchy target.\n' >&2
  flock -u "$lock_fd" || true
  exec {lock_fd}>&-
  return 1
}

_aur_guard_runtime_dispatch() {
  local command_name="$1"
  local runtime="$_AUR_GUARD_RUNTIME_FILE"
  shift || true

  if [[ "$command_name" == aurguard && "${1:-}" == refresh ]]; then
    _aur_guard_runtime_ensure force || return $?
    printf 'AUR Guard: refreshed the validated exact-commit runtime cache.\n'
    return 0
  fi

  _aur_guard_runtime_ensure normal || return $?
  [[ -f "$runtime" && ! -L "$runtime" ]] || return 1

  AWTARCHY_AURGUARD_RUNTIME_ACTIVE=1 \
    command bash --noprofile --norc -c '
      set -e
      runtime=$1
      command_name=$2
      shift 2
      # shellcheck disable=SC1090
      source "$runtime"
      "$command_name" "$@"
    ' bash "$runtime" "$command_name" "$@"
}

# AWTARCHY_AURGUARD_RUNTIME_BEGIN v1
'''

text = text.replace(anchor, bootstrap + anchor, 1)

public_functions = [
    "aurverify",
    "aurinstall",
    "aurup",
    "aur",
    "aurguard",
    "aurhelp",
    "aurinstalled",
    "aurremove",
    "auruninstall",
    "sysupdate",
    "aurcheck",
    "aurunsafe",
    "yay",
    "paru",
]

guard_template = '''  if [[ ${AWTARCHY_AURGUARD_RUNTIME_ACTIVE:-0} != 1 \\
      && ${AUR_GUARD_TEST_MODE:-0} != 1 ]]; then
    _aur_guard_runtime_dispatch {name} "$@"
    return $?
  fi

'''

for name in public_functions:
    signature = f"{name}() {{\n"
    if text.count(signature) != 1:
        raise SystemExit(f"expected one public function {name}, found {text.count(signature)}")
    text = text.replace(signature, signature + guard_template.format(name=name), 1)

selftest_signature = "aurguardtest() (\n"
if text.count(selftest_signature) != 1:
    raise SystemExit(f"expected one aurguardtest function, found {text.count(selftest_signature)}")
text = text.replace(
    selftest_signature,
    selftest_signature
    + guard_template.format(name="aurguardtest"),
    1,
)

if not text.endswith("\n"):
    text += "\n"
text += "# AWTARCHY_AURGUARD_RUNTIME_END v1\n"

if text.count("# AWTARCHY_AURGUARD_RUNTIME_BEGIN v1") != 1:
    raise SystemExit("runtime begin marker count is not one after transformation")
if text.count("# AWTARCHY_AURGUARD_RUNTIME_END v1") != 1:
    raise SystemExit("runtime end marker count is not one after transformation")

path.write_text(text, encoding="utf-8")
