#!/usr/bin/env bash
# ~/.config/hypr/scripts/hyprpm-auto-reload.sh
#
# Safe Hyprland plugin reconciliation:
# - Reconciles all enabled hyprpm plugins once per new Hyprland session.
# - Preflights hyprpm's cached Hyprland headers/commit/ABI before automatic
#   startup reloads so known stale-plugin states never reach hyprpm reload.
# - Never updates/builds plugins automatically at login.
# - Marks Awtarchy's optional hyprbars control as repair-required when needed.
# - Preserves the explicit HYPRPM_AUTO_LIVE_RELOAD=1 update-on-failure path.
#
# Log: ~/.cache/hyprpm-auto/hyprpm-auto-reload.log

set -u
set -o pipefail

HYPRPM="$(command -v hyprpm || true)"
HYPRCTL="$(command -v hyprctl || true)"
PYTHON="$(command -v python3 || true)"
PKGCONF="$(command -v pkgconf || true)"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy"
LOG_DIR="$CACHE_DIR/hyprpm-auto"
LOG_FILE="$LOG_DIR/hyprpm-auto-reload.log"
REPAIR_MARKER="$STATE_DIR/hyprbars-repair-required"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-${CACHE_DIR}/awtarchy-runtime}"
SESSION_DIR="$RUNTIME_DIR/awtarchy"
SESSION_MARKER="$SESSION_DIR/hyprpm-auto-reload.session"
SESSION_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-}"
HYPRPM_USER="${USER:-$(id -un 2>/dev/null || true)}"
HYPRPM_STATE_DIR="${HYPRPM_STATE_DIR:-/var/cache/hyprpm/${HYPRPM_USER}}"
HYPRPM_GLOBAL_STATE="$HYPRPM_STATE_DIR/state.toml"
HYPRPM_HEADERS_ROOT="$HYPRPM_STATE_DIR/headersRoot"
HYPRPM_PKGCONFIG_DIR="$HYPRPM_HEADERS_ROOT/share/pkgconfig"

LOCK_TTL_SECONDS="${HYPRPM_AUTO_LOCK_TTL_SECONDS:-600}"
LOCK_FILE="${HYPRPM_AUTO_LOCK_FILE:-/tmp/hyprpm-auto-reload.lock}"
RELOAD_TIMEOUT_SECONDS="${HYPRPM_RELOAD_TIMEOUT_SECONDS:-20}"
UPDATE_TIMEOUT_SECONDS="${HYPRPM_UPDATE_TIMEOUT_SECONDS:-600}"
LIVE_RELOAD="${HYPRPM_AUTO_LIVE_RELOAD:-0}"
UPDATE_ON_FAILURE="${HYPRPM_AUTO_UPDATE_ON_FAILURE:-1}"

mkdir -p "$LOG_DIR" "$STATE_DIR" 2>/dev/null || true

ts() { date +"%Y-%m-%d %H:%M:%S"; }

log_line() {
  printf '[%s] %s\n' "$(ts)" "$*" >>"$LOG_FILE"
}

notify() {
  local msg="$1"
  [[ -n "$HYPRCTL" ]] || return 0
  "$HYPRCTL" notify -1 9000 "rgb(ffcc00)" "$msg" >/dev/null 2>&1 || true
}

mark_repair() {
  local reason="$1"
  if printf '%s\n' "$reason" >"$REPAIR_MARKER" 2>/dev/null; then
    chmod 600 "$REPAIR_MARKER" 2>/dev/null || true
  fi
  log_line "Title Bars repair required: $reason"
}

clear_repair() {
  rm -f -- "$REPAIR_MARKER" 2>/dev/null || true
}

have_recent_lock() {
  [[ -f "$LOCK_FILE" ]] || return 1
  local now lock_ts age
  now="$(date +%s)"
  lock_ts="$(cat "$LOCK_FILE" 2>/dev/null || echo 0)"
  [[ "$lock_ts" =~ ^[0-9]+$ ]] || return 1
  age=$((now - lock_ts))
  ((age >= 0 && age < LOCK_TTL_SECONDS))
}

touch_lock() {
  date +%s >"$LOCK_FILE" 2>/dev/null || true
}

run_maybe_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout --preserve-status -k 5 "${secs}s" "$@"
  else
    "$@"
  fi
}

log_block() {
  local label="$1" rc="$2" out="$3"
  {
    printf '[%s] %s (rc=%s)\n' "$(ts)" "$label" "$rc"
    [[ -n "$out" ]] && printf '%s\n' "$out"
    printf '\n'
  } >>"$LOG_FILE"
}

enabled_plugins() {
  [[ -n "$PYTHON" ]] || return 1
  "$PYTHON" - "$HYPRPM_STATE_DIR" <<'PY_STATE'
import glob
import sys
import tomllib

root = sys.argv[1]
parse_failed = False
for path in glob.glob(root + "/*/state.toml"):
    try:
        with open(path, "rb") as handle:
            state = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError):
        parse_failed = True
        continue

    for name, plugin in state.items():
        if name == "repository":
            continue
        if isinstance(plugin, dict) and plugin.get("enabled") is True:
            print(name)

if parse_failed:
    raise SystemExit(2)
PY_STATE
}

array_contains_exact() {
  local needle="$1" item
  shift || true
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

hyprbars_loaded() {
  [[ -n "$HYPRCTL" ]] || return 1
  "$HYPRCTL" plugin list 2>/dev/null \
    | grep -qiE '(^|[^a-zA-Z0-9_])hyprbars([^a-zA-Z0-9_]|$)'
}

wait_hyprbars_loaded() {
  local attempt
  for ((attempt = 1; attempt <= 20; attempt++)); do
    hyprbars_loaded && return 0
    sleep 0.1
  done
  return 1
}

running_hyprland_identity_once() {
  [[ -n "$PYTHON" && -n "$HYPRCTL" ]] || return 1
  "$HYPRCTL" -j version 2>/dev/null \
    | "$PYTHON" -c '
import json
import sys
try:
    data = json.load(sys.stdin)
    commit = str(data.get("commit") or "").strip()
    abi = str(data.get("abiHash") or "").strip()
except Exception:
    raise SystemExit(1)
if not commit or not abi:
    raise SystemExit(1)
print(commit)
print(abi)
'
}

running_hyprland_identity() {
  local attempt identity=""
  for ((attempt = 1; attempt <= 20; attempt++)); do
    if identity="$(running_hyprland_identity_once)"; then
      printf '%s\n' "$identity"
      return 0
    fi
    sleep 0.2
  done
  return 1
}

cached_abi_hash() {
  [[ -r "$HYPRPM_GLOBAL_STATE" ]] || return 1
  awk -F= '
    /^[[:space:]]*hash[[:space:]]*=/ {
      value = $2
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$HYPRPM_GLOBAL_STATE"
}

cached_header_commit() {
  local cflags="" token="" include_dir="" version_header=""
  [[ -n "$PKGCONF" && -r "$HYPRPM_PKGCONFIG_DIR/hyprland.pc" ]] || return 1

  cflags="$(
    PKG_CONFIG_PATH="${HYPRPM_PKGCONFIG_DIR}${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}" \
      "$PKGCONF" --cflags --keep-system-cflags hyprland 2>/dev/null
  )" || return 1

  for token in $cflags; do
    case "$token" in
      -I/*)
        include_dir="${token#-I}"
        [[ "$include_dir" == */protocols ]] && continue
        version_header="$include_dir/hyprland/src/version.h"
        break
        ;;
    esac
  done

  [[ -n "$version_header" && -r "$version_header" ]] || return 1
  sed -n 's/^[[:space:]]*#define[[:space:]][[:space:]]*GIT_COMMIT_HASH[[:space:]][[:space:]]*"\([^"]*\)".*/\1/p' \
    "$version_header" | head -n1
}

preflight_reason() {
  local identity="" running_commit="" running_abi="" cached_commit="" cached_abi=""
  local -a fields=()

  identity="$(running_hyprland_identity)" || {
    printf '%s\n' 'version-unavailable'
    return 1
  }
  mapfile -t fields <<<"$identity"
  running_commit="${fields[0]:-}"
  running_abi="${fields[1]:-}"

  cached_abi="$(cached_abi_hash)" || {
    printf '%s\n' 'headers-missing'
    return 1
  }
  cached_commit="$(cached_header_commit)" || {
    printf '%s\n' 'headers-missing'
    return 1
  }

  if [[ -z "$cached_abi" || "$cached_abi" != "$running_abi" ]]; then
    printf '%s\n' 'abi-mismatch'
    return 1
  fi
  if [[ -z "$cached_commit" || "$cached_commit" != "$running_commit" ]]; then
    printf '%s\n' 'headers-mismatch'
    return 1
  fi

  return 0
}

run_explicit_live_reconcile() {
  local reload_out="" reload_rc=0 update_out="" update_rc=0 reload2_out="" reload2_rc=0

  if have_recent_lock; then
    return 0
  fi

  log_line "HYPRPM_AUTO_LIVE_RELOAD=1 set. Running live hyprpm reload."
  reload_out="$(run_maybe_timeout "$RELOAD_TIMEOUT_SECONDS" "$HYPRPM" reload 2>&1)"
  reload_rc=$?
  log_block "hyprpm reload" "$reload_rc" "$reload_out"

  if [[ "$reload_rc" -eq 0 ]]; then
    return 0
  fi

  if [[ "$UPDATE_ON_FAILURE" != "1" ]]; then
    notify "hyprpm reload failed. Auto update disabled. See log: $LOG_FILE"
    return 0
  fi

  touch_lock
  notify "hyprpm reload failed. Running hyprpm update, then reload."

  update_out="$(run_maybe_timeout "$UPDATE_TIMEOUT_SECONDS" "$HYPRPM" update 2>&1)"
  update_rc=$?
  log_block "hyprpm update" "$update_rc" "$update_out"

  if [[ "$update_rc" -ne 0 ]]; then
    notify "hyprpm update failed. See log: $LOG_FILE"
    return 0
  fi

  reload2_out="$(run_maybe_timeout "$RELOAD_TIMEOUT_SECONDS" "$HYPRPM" reload 2>&1)"
  reload2_rc=$?
  log_block "hyprpm reload after update" "$reload2_rc" "$reload2_out"

  if [[ "$reload2_rc" -ne 0 ]]; then
    notify "hyprpm reload still failing after update. See log: $LOG_FILE"
    return 0
  fi

  notify "hyprpm updated and reloaded."
  return 0
}

[[ -n "$HYPRPM" ]] || exit 0

session_start_reconcile=0
if [[ -n "$SESSION_SIGNATURE" ]]; then
  mkdir -p "$SESSION_DIR" 2>/dev/null || true
  chmod 700 "$SESSION_DIR" 2>/dev/null || true
  previous_session="$(cat "$SESSION_MARKER" 2>/dev/null || true)"
  if [[ "$previous_session" != "$SESSION_SIGNATURE" ]]; then
    if printf '%s\n' "$SESSION_SIGNATURE" >"$SESSION_MARKER" 2>/dev/null; then
      session_start_reconcile=1
    else
      log_line "Could not record Hyprland session marker; skipping automatic plugin reconciliation."
    fi
  fi
fi

if [[ "$session_start_reconcile" -ne 1 ]]; then
  if [[ "$LIVE_RELOAD" != "1" ]]; then
    log_line "Skipped hyprpm reload. Set HYPRPM_AUTO_LIVE_RELOAD=1 to allow live plugin reload."
    exit 0
  fi
  run_explicit_live_reconcile
  exit 0
fi

enabled_output=""
if ! enabled_output="$(enabled_plugins)"; then
  log_line "Could not inspect persisted hyprpm plugin state; skipping automatic reconciliation."
  exit 0
fi

mapfile -t enabled <<<"$enabled_output"
if [[ ${#enabled[@]} -eq 1 && -z ${enabled[0]} ]]; then
  enabled=()
fi

if [[ ${#enabled[@]} -eq 0 ]]; then
  clear_repair
  log_line "No enabled hyprpm plugins; no session reconciliation needed."
  exit 0
fi

hyprbars_wanted=0
array_contains_exact hyprbars "${enabled[@]}" && hyprbars_wanted=1

reason=""
if ! reason="$(preflight_reason)"; then
  if [[ "$reason" == "version-unavailable" ]]; then
    log_line "Could not read the running Hyprland version after retries; leaving plugin state unchanged."
    exit 0
  fi

  if ((hyprbars_wanted == 1)); then
    mark_repair "${reason:-preflight-failed}"
  else
    clear_repair
    log_line "Hyprland plugin reload skipped: ${reason:-preflight-failed}. Run hyprpm update manually before reloading plugins."
  fi
  exit 0
fi

log_line "Enabled hyprpm plugins are compatible. Running one quiet hyprpm reload for the new session."
reload_out="$(run_maybe_timeout "$RELOAD_TIMEOUT_SECONDS" "$HYPRPM" reload 2>&1)"
reload_rc=$?
log_block "hyprpm reload" "$reload_rc" "$reload_out"

if [[ "$reload_rc" -ne 0 ]]; then
  if ((hyprbars_wanted == 1)); then
    mark_repair "reload-failed"
  else
    clear_repair
    log_line "hyprpm reload failed for non-Awtarchy plugins; no automatic update was attempted."
  fi
  exit 0
fi

if ((hyprbars_wanted == 1)); then
  if ! wait_hyprbars_loaded; then
    mark_repair "reload-not-loaded"
    exit 0
  fi
fi

clear_repair
log_line "Enabled hyprpm plugin state reloaded successfully."
exit 0
