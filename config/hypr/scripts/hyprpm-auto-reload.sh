#!/usr/bin/env bash
# ~/.config/hypr/scripts/hyprpm-auto-reload.sh
#
# Quiet Awtarchy hyprbars session reconciliation.
# - Does nothing when hyprbars is not enabled or is already loaded.
# - Preflights hyprpm's cached Hyprland headers/commit/ABI before reload so known
#   stale-plugin states are contained before hyprpm can emit warning/error notices.
# - Never updates/builds plugins at login. Repair is handled explicitly through
#   the Awtarchy Hyprland Plugin control.
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
RELOAD_TIMEOUT_SECONDS="${HYPRPM_RELOAD_TIMEOUT_SECONDS:-20}"

mkdir -p "$LOG_DIR" "$STATE_DIR" 2>/dev/null || true

ts() { date +"%Y-%m-%d %H:%M:%S"; }

log_line() {
  printf '[%s] %s\n' "$(ts)" "$*" >>"$LOG_FILE"
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

run_maybe_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout --preserve-status -k 5 "${secs}s" "$@"
  else
    "$@"
  fi
}

hyprbars_enabled() {
  [[ -n "$PYTHON" && -d "$HYPRPM_STATE_DIR" ]] || return 1
  "$PYTHON" - "$HYPRPM_STATE_DIR" <<'PY_STATE'
import glob
import sys
import tomllib

root = sys.argv[1]
for path in glob.glob(root + "/*/state.toml"):
    try:
        with open(path, "rb") as handle:
            state = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError):
        continue
    plugin = state.get("hyprbars")
    if isinstance(plugin, dict) and plugin.get("enabled") is True:
        raise SystemExit(0)
raise SystemExit(1)
PY_STATE
}

hyprbars_loaded() {
  "$HYPRCTL" plugin list 2>/dev/null \
    | grep -qiE '(^|[^a-zA-Z0-9_])hyprbars([^a-zA-Z0-9_]|$)'
}

wait_hyprbars_loaded() {
  local attempt
  for ((attempt = 1; attempt <= 10; attempt++)); do
    hyprbars_loaded && return 0
    sleep 0.1
  done
  return 1
}

running_hyprland_identity_once() {
  [[ -n "$PYTHON" ]] || return 1
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
  for ((attempt = 1; attempt <= 10; attempt++)); do
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

[[ -n "$HYPRPM" && -n "$HYPRCTL" && -n "$SESSION_SIGNATURE" ]] || exit 0

mkdir -p "$SESSION_DIR" 2>/dev/null || exit 0
chmod 700 "$SESSION_DIR" 2>/dev/null || true
previous_session="$(cat "$SESSION_MARKER" 2>/dev/null || true)"
[[ "$previous_session" != "$SESSION_SIGNATURE" ]] || exit 0
printf '%s\n' "$SESSION_SIGNATURE" >"$SESSION_MARKER" 2>/dev/null || exit 0

if ! hyprbars_enabled; then
  clear_repair
  log_line "Title Bars are not enabled; no plugin reconciliation needed."
  exit 0
fi

if hyprbars_loaded; then
  clear_repair
  log_line "Title Bars are already loaded."
  exit 0
fi

reason=""
if ! reason="$(preflight_reason)"; then
  if [[ "$reason" == "version-unavailable" ]]; then
    log_line "Could not read the running Hyprland version after retries; leaving Title Bars unchanged."
    exit 0
  fi
  mark_repair "${reason:-preflight-failed}"
  exit 0
fi

log_line "Title Bars are enabled and compatible but not loaded. Running one quiet hyprpm reload."
reload_out="$(run_maybe_timeout "$RELOAD_TIMEOUT_SECONDS" "$HYPRPM" reload 2>&1)"
reload_rc=$?
{
  printf '[%s] hyprpm reload (rc=%d)\n' "$(ts)" "$reload_rc"
  [[ -n "$reload_out" ]] && printf '%s\n' "$reload_out"
  printf '\n'
} >>"$LOG_FILE"

if [[ "$reload_rc" -ne 0 ]]; then
  mark_repair "reload-failed"
  exit 0
fi

if ! wait_hyprbars_loaded; then
  mark_repair "reload-not-loaded"
  exit 0
fi

clear_repair
log_line "Title Bars plugin state reloaded successfully."
exit 0
