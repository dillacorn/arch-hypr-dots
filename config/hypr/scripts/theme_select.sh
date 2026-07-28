#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# FILE: ~/.config/hypr/scripts/theme_select.sh
#
# Theme picker.
# - Uses fuzzel if available, otherwise wofi.
#
# Toggle behavior (fuzzel only):
# - Run once  -> opens picker
# - Run again -> closes THIS script's fuzzel instance (matched by its unique --config runtime path)
#
# Also: if another fuzzel is open (cliphist/launcher/etc), it will be closed first so this opens cleanly.

set -euo pipefail
exec </dev/null

DEBUG="${DEBUG:-0}"
log() { [[ "$DEBUG" == "1" ]] && printf '[select_theme] %s\n' "$*" >&2 || true; }

THEME_DIR="${THEME_DIR:-$HOME/.config/hypr/themes}"

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPTS_DIR="${CONF_DIR}/hypr/scripts"
WAYBAR_SH="${WAYBAR_SH:-$SCRIPTS_DIR/waybar.sh}"

FUZZEL_BIN="${FUZZEL_BIN:-fuzzel}"
USER_FUZZEL_CFG="${USER_FUZZEL_CFG:-$CONF_DIR/fuzzel/fuzzel.ini}"

RUNTIME_BASE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
RUNTIME_DIR="${RUNTIME_BASE}/awtarchy"
RUNTIME_CFG="${RUNTIME_DIR}/select_theme.fuzzel.ini"
SCRIPT_LOCK="${RUNTIME_BASE}/select_theme.fuzzel.lock"

# toggle  = if already open (script-launched), close and exit; else open
# reopen  = if already open, close then open again
# off     = never close; always attempt open
TOGGLE_MODE="${TOGGLE_MODE:-toggle}"

# Kill other fuzzel instances before opening (launcher, cliphist, etc)
KILL_OTHER_FUZZEL="${KILL_OTHER_FUZZEL:-1}"  # 1=yes, 0=no

FUZZEL_PROMPT="${FUZZEL_PROMPT:-Choose theme: }"
FUZZEL_LINES="${FUZZEL_LINES:-12}"
FUZZEL_WIDTH="${FUZZEL_WIDTH:-40}"

FROM_WAYBAR="0"
while (( $# )); do
  case "$1" in
    --from-waybar) FROM_WAYBAR="1"; shift ;;
    *) shift ;;
  esac
done

[[ -d "$THEME_DIR" ]] || { printf 'select_theme: missing theme dir: %s\n' "$THEME_DIR" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || { printf 'select_theme: missing: %s\n' "$1" >&2; exit 127; }; }

themes_list() {
  find "$THEME_DIR" -maxdepth 1 -type f -executable -printf '%f\n' 2>/dev/null | LC_ALL=C sort
}

user_anchor_opt_in() {
  local f="$USER_FUZZEL_CFG"
  [[ -f "$f" ]] || return 1
  awk '
    BEGIN{in_main=0}
    /^[[:space:]]*\[main\][[:space:]]*$/ {in_main=1; next}
    /^[[:space:]]*\[/ {in_main=0}
    in_main {
      if ($0 ~ /^[[:space:]]*[#;]/) next
      if ($0 ~ /^[[:space:]]*anchor[[:space:]]*=/) { found=1; exit }
    }
    END{ exit(found?0:1) }
  ' "$f"
}

waybar_visible_on_focused_monitor() {
  local mon safe cache cfg pid comm cmdline

  [[ -x "$WAYBAR_SH" ]] || return 1
  mon="$("$WAYBAR_SH" focused-monitor 2>/dev/null || true)"
  [[ -n "$mon" ]] || return 1

  cache="${XDG_CACHE_HOME:-$HOME/.cache}"
  safe="$(printf '%s' "$mon" | tr '/ \t' '___')"
  cfg="${cache}/waybar/per-output/${safe}.json"

  [[ -f "$cfg" ]] || return 1

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    [[ -r "/proc/$pid/comm" ]] || continue
    comm="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
    [[ "$comm" == "waybar" ]] || continue

    cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
    [[ "$cmdline" == *"$cfg"* ]] && return 0
  done < <(pgrep -x waybar 2>/dev/null || true)

  return 1
}

bar_pos_focused() {
  if [[ -x "$WAYBAR_SH" ]]; then
    "$WAYBAR_SH" getpos-focused 2>/dev/null || echo top
  else
    echo top
  fi
}

compute_anchor() {
  local pos="${1:-top}"
  if [[ "$FROM_WAYBAR" == "1" ]]; then
    case "$pos" in
      top) echo top-left ;;
      bottom) echo bottom-left ;;
      left) echo top-left ;;
      right) echo top-right ;;
      *) echo top-left ;;
    esac
  else
    case "$pos" in
      top|bottom|left|right) echo "$pos" ;;
      *) echo top ;;
    esac
  fi
}

build_runtime_cfg() {
  local anchor_override="${1:-}"

  mkdir -p "$RUNTIME_DIR" 2>/dev/null || true

  {
    if [[ -f "$USER_FUZZEL_CFG" ]]; then
      cat "$USER_FUZZEL_CFG"
      echo
    else
      echo "[main]"
    fi

    echo "[main]"
    echo "lines=$FUZZEL_LINES"
    echo "width=$FUZZEL_WIDTH"
    [[ -n "$anchor_override" ]] && echo "anchor=$anchor_override"
    echo

    echo "[dmenu]"
    echo "prompt=$FUZZEL_PROMPT"
  } > "$RUNTIME_CFG"

  log "runtime cfg: $RUNTIME_CFG"
  log "anchor_override=${anchor_override:-<none>}"
}

kill_pids() {
  local pids="${1:-}"
  [[ -n "$pids" ]] || return 0

  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true

  for _ in {1..12}; do
    local alive=0 pid
    for pid in $pids; do
      kill -0 "$pid" 2>/dev/null && alive=1 || true
    done
    [[ "$alive" == "0" ]] && break
    sleep 0.05
  done

  local still=0 pid
  for pid in $pids; do
    kill -0 "$pid" 2>/dev/null && still=1 || true
  done
  if [[ "$still" == "1" ]]; then
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
    sleep 0.05
  fi

  if ! pgrep -u "$UID" -x fuzzel >/dev/null 2>&1; then
    rm -f -- "$RUNTIME_BASE"/fuzzel-*.lock 2>/dev/null || true
  fi
}

ours_pids() {
  (pgrep -u "$UID" -x "$FUZZEL_BIN" -a 2>/dev/null || true) \
    | awk -v m="$RUNTIME_CFG" 'index($0,m){print $1}'
}

other_pids() {
  (pgrep -u "$UID" -x "$FUZZEL_BIN" -a 2>/dev/null || true) \
    | awk -v m="$RUNTIME_CFG" '!index($0,m){print $1}'
}

close_ours_and_maybe_exit() {
  local pids
  pids="$(ours_pids || true)"
  [[ -n "${pids:-}" ]] || return 1

  kill_pids "$pids"

  if [[ "$TOGGLE_MODE" == "toggle" ]]; then
    exit 0
  fi
  return 0
}

pick_with_fuzzel() {
  need pgrep
  need awk
  need flock

  exec 8>"$SCRIPT_LOCK"
  if ! flock -n 8; then
    if [[ "$TOGGLE_MODE" == "toggle" ]]; then
      close_ours_and_maybe_exit || exit 0
      exit 0
    fi

    if [[ "$TOGGLE_MODE" == "reopen" ]]; then
      close_ours_and_maybe_exit || true
      for _ in {1..80}; do
        flock -n 8 && break
        sleep 0.025
      done
      flock -n 8 || exit 0
    else
      exit 0
    fi
  fi

  close_ours_and_maybe_exit || true

  if [[ "$KILL_OTHER_FUZZEL" == "1" ]]; then
    opids="$(other_pids || true)"
    [[ -n "${opids:-}" ]] && kill_pids "$opids"
  fi

  local anchor_override=""
  if [[ "$FROM_WAYBAR" == "1" ]]; then
    if waybar_visible_on_focused_monitor; then
      anchor_override="$(compute_anchor "$(bar_pos_focused)")"
    fi
  else
    if waybar_visible_on_focused_monitor && user_anchor_opt_in; then
      anchor_override="$(compute_anchor "$(bar_pos_focused)")"
    fi
  fi

  build_runtime_cfg "$anchor_override"
  themes_list | "$FUZZEL_BIN" --dmenu --config "$RUNTIME_CFG"
}

pick_with_wofi() {
  themes_list | wofi --dmenu -i -p "Choose theme"
}

THEME=""

if command -v "$FUZZEL_BIN" >/dev/null 2>&1; then
  THEME="$(pick_with_fuzzel || true)"
elif command -v wofi >/dev/null 2>&1; then
  THEME="$(pick_with_wofi || true)"
else
  printf 'select_theme: need fuzzel or wofi\n' >&2
  exit 127
fi

if [[ -n "${THEME:-}" ]]; then
  if "${THEME_DIR}/${THEME}"; then
    STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy"
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$THEME" >"${STATE_DIR}/active-theme"
    exit 0
  else
    status=$?
    exit "$status"
  fi
fi
