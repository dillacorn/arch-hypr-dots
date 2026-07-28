#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/workspace_mix.sh
#
# PURPOSE:
#   - Mix windows from selected Hyprland workspaces into a temporary workspace named by MIX_NAME
#   - Toggle adds/removes live
#   - Restore dwindle workspaces by rebuilding their recorded split direction, ratio, and window placement
#   - Restore floating windows to their recorded position and size
#   - Fall back to stable insertion order if exact reconstruction is unsafe or unavailable
#
# Hyprland 0.55+ Lua-compatible hyprctl dispatch version.
# DEPS: bash, hyprctl, jq, python

set -euo pipefail

# ---------- Config ----------
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/workspace-mix"
STATE_FILE="$CACHE_ROOT/state.json"
MIX_NAME=" "   # leading space + Nerd Font glyph
mkdir -p "$CACHE_ROOT"

# Runtime options temporarily changed during exact dwindle reconstruction.
DWIN_USE_ACTIVE_OLD=""
DWIN_PRESERVE_SPLIT_OLD=""

# ---------- Helpers ----------
err() { printf 'workspace-mix: %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

require_deps() {
  local missing=()
  have hyprctl || missing+=("hyprctl")
  have jq      || missing+=("jq")
  have python  || missing+=("python")
  if ((${#missing[@]})); then
    err "missing deps: ${missing[*]}"
    exit 1
  fi
}

lua_quote() {
  local s="${1:-}"
  s=${s//\\/\\\\}
  s=${s//\'/\\\'}
  printf "'%s'" "$s"
}

is_numeric() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
now_epoch()  { date +%s; }

lua_ws_expr() {
  local ws="${1:-}"
  if [[ "$ws" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s' "$ws"
  else
    lua_quote "$ws"
  fi
}

hypr_dispatch() {
  hyprctl dispatch "$1"
}

monitors_json()    { hyprctl -j monitors; }
workspaces_json()  { hyprctl -j workspaces; }
clients_json()     { hyprctl -j clients; }
activewindow_json(){ hyprctl -j activewindow; }

focused_monitor() {
  monitors_json | jq -r '(map(select(.focused==true))[0].name) // (.[0].name) // empty'
}

focused_ws_label() {
  monitors_json | jq -r '(map(select(.focused==true))[0].activeWorkspace.name) // (.[0].activeWorkspace.name) // empty'
}

focused_window_addr() {
  activewindow_json | jq -r '.address // empty'
}

# Normalize to a workspace label (string). If numeric id, resolve to name if possible.
ws_label_from_arg() {
  local arg="$1"
  if is_numeric "$arg"; then
    local name
    name="$(workspaces_json | jq -r --argjson id "$arg" '([.[]|select(.id==$id).name][0]) // empty')"
    printf '%s' "${name:-$arg}"
  else
    printf '%s' "$arg"
  fi
}

# Workspace expression accepted by Lua dispatchers.
ws_token_for_client_move() {
  local label="$1"
  if is_numeric "$label"; then printf '%s' "$label"; else printf 'name:%s' "$label"; fi
}

focus_ws() {
  local label="$1"
  hypr_dispatch "hl.dsp.focus({ workspace = $(lua_ws_expr "$(ws_token_for_client_move "$label")") })" >/dev/null
}

focus_addr() {
  local addr="$1"
  [[ -n "$addr" ]] || return 1
  hypr_dispatch "hl.dsp.focus({ window = $(lua_quote "address:$addr") })" >/dev/null
}

move_addr_to_ws() {
  local addr="$1" label="$2"
  [[ -n "$addr" && -n "$label" ]] || return 1
  hypr_dispatch "hl.dsp.window.move({ workspace = $(lua_ws_expr "$(ws_token_for_client_move "$label")"), follow = false, window = $(lua_quote "address:$addr") })" >/dev/null
}

move_workspace_to_monitor() {
  local label="$1" monitor="$2"
  [[ -n "$label" && -n "$monitor" ]] || return 1
  hypr_dispatch "hl.dsp.workspace.move({ workspace = $(lua_ws_expr "$(ws_token_for_client_move "$label")"), monitor = $(lua_quote "$monitor") })" >/dev/null
}

layout_msg() {
  local message="$1"
  hypr_dispatch "hl.dsp.layout($(lua_quote "$message"))" >/dev/null
}

set_window_floating() {
  local addr="$1" enabled="$2" action
  [[ -n "$addr" ]] || return 1
  if [[ "$enabled" == "true" || "$enabled" == "1" ]]; then
    action="set"
  else
    action="unset"
  fi
  hypr_dispatch "hl.dsp.window.float({ action = $(lua_quote "$action"), window = $(lua_quote "address:$addr") })" >/dev/null
}

set_window_pseudo() {
  local addr="$1" enabled="$2" action
  [[ -n "$addr" ]] || return 1
  if [[ "$enabled" == "true" || "$enabled" == "1" ]]; then
    action="set"
  else
    action="unset"
  fi
  hypr_dispatch "hl.dsp.window.pseudo({ action = $(lua_quote "$action"), window = $(lua_quote "address:$addr") })" >/dev/null
}

move_window_exact() {
  local addr="$1" x="$2" y="$3"
  hypr_dispatch "hl.dsp.window.move({ x = $x, y = $y, relative = false, window = $(lua_quote "address:$addr") })" >/dev/null
}

resize_window_exact() {
  local addr="$1" w="$2" h="$3"
  hypr_dispatch "hl.dsp.window.resize({ x = $w, y = $h, relative = false, window = $(lua_quote "address:$addr") })" >/dev/null
}

get_option_int() {
  local option="$1"
  hyprctl -j getoption "$option" 2>/dev/null | jq -r '
    if has("int") then .int
    elif has("value") then .value
    else empty
    end
  '
}

set_option_int() {
  local option="$1" value="$2"
  hyprctl keyword "$option" "$value" >/dev/null
}

prepare_dwindle_restore() {
  if [[ -z "$DWIN_USE_ACTIVE_OLD" ]]; then
    DWIN_USE_ACTIVE_OLD="$(get_option_int "dwindle.use_active_for_splits" || true)"
  fi
  if [[ -z "$DWIN_PRESERVE_SPLIT_OLD" ]]; then
    DWIN_PRESERVE_SPLIT_OLD="$(get_option_int "dwindle.preserve_split" || true)"
  fi

  [[ "$DWIN_USE_ACTIVE_OLD" =~ ^[01]$ && "$DWIN_PRESERVE_SPLIT_OLD" =~ ^[01]$ ]] || return 1

  set_option_int "dwindle.use_active_for_splits" 1
  set_option_int "dwindle.preserve_split" 1
}

restore_runtime_options() {
  if [[ "$DWIN_USE_ACTIVE_OLD" =~ ^[01]$ ]]; then
    set_option_int "dwindle.use_active_for_splits" "$DWIN_USE_ACTIVE_OLD" >/dev/null 2>&1 || true
  fi
  if [[ "$DWIN_PRESERVE_SPLIT_OLD" =~ ^[01]$ ]]; then
    set_option_int "dwindle.preserve_split" "$DWIN_PRESERVE_SPLIT_OLD" >/dev/null 2>&1 || true
  fi
}
trap restore_runtime_options EXIT

# ---------- State ----------
empty_state_json() {
  cat <<'JSON'
{
  "selection": [],
  "windows": [],
  "workspaces": {},
  "mix_ws": "",
  "monitor": "",
  "prev_ws": "",
  "prev_window": "",
  "created": 0
}
JSON
}

load_state() {
  if [[ -s "$STATE_FILE" ]] && jq -e . "$STATE_FILE" >/dev/null 2>&1; then
    jq -c '
      .selection = (.selection // [])
      | .windows = (.windows // [])
      | .workspaces = (.workspaces // {})
      | .mix_ws = (.mix_ws // "")
      | .monitor = (.monitor // "")
      | .prev_ws = (.prev_ws // "")
      | .prev_window = (.prev_window // "")
      | .created = (.created // 0)
    ' "$STATE_FILE"
  else
    empty_state_json
  fi
}

save_state() {
  local tmp="${STATE_FILE}.tmp.$$"
  cat > "$tmp"
  mv -f "$tmp" "$STATE_FILE"
}

workspace_meta() {
  local label="$1"
  workspaces_json | jq -c --arg l "$label" '
    ([.[] | select(.name == $l)][0] // {})
    | {
        monitor: (.monitor // ""),
        layout: (.tiledLayout // "unknown"),
        last_window: (.lastwindow // "")
      }
  '
}

# Clients on a given LABEL with enough state to restore layout and floating geometry.
clients_from_label_as_moves() {
  local label="$1"
  clients_json | jq -c --arg l "$label" '
    map(select(.workspace.name == $l and .mapped == true))
    | map({
        address,
        orig_ws: .workspace.name,
        floating: (.floating // false),
        pseudo: (.pseudo // false),
        pinned: (.pinned // false),
        focus_history: (.focusHistoryID // 999999),
        x: (.at[0] // 0),
        y: (.at[1] // 0),
        w: (.size[0] // 0),
        h: (.size[1] // 0)
      })
  '
}

live_addr_set() {
  clients_json | jq -r '.[].address' | sort -u
}

# ---------- Dwindle layout reconstruction ----------
# Infer a guillotine split tree from saved tiled rectangles, then emit the order
# needed to recreate that tree with preselect + exact splitratio operations.
dwindle_plan_json() {
  local windows_json="$1"
  python - 3<<<"$windows_json" <<'PY'
import json
import os
import sys

items = json.load(os.fdopen(3))

for item in items:
    item["x0"] = float(item.get("x", 0))
    item["y0"] = float(item.get("y", 0))
    item["x1"] = item["x0"] + max(float(item.get("w", 0)), 1.0)
    item["y1"] = item["y0"] + max(float(item.get("h", 0)), 1.0)

TOL = 3.0


def bounds(group):
    return {
        "x0": min(w["x0"] for w in group),
        "y0": min(w["y0"] for w in group),
        "x1": max(w["x1"] for w in group),
        "y1": max(w["y1"] for w in group),
    }


def split_candidates(group):
    box = bounds(group)
    candidates = []

    by_x = sorted(group, key=lambda w: (w["x0"], w["x1"], w["y0"], w["address"]))
    for index in range(1, len(by_x)):
        first = by_x[:index]
        second = by_x[index:]
        first_edge = max(w["x1"] for w in first)
        second_edge = min(w["x0"] for w in second)
        if first_edge <= second_edge + TOL:
            a = bounds(first)
            b = bounds(second)
            span = max(box["y1"] - box["y0"], 1.0)
            coverage = (
                abs(a["y0"] - box["y0"]) + abs(a["y1"] - box["y1"])
                + abs(b["y0"] - box["y0"]) + abs(b["y1"] - box["y1"])
            ) / span
            cut = (first_edge + second_edge) / 2.0
            ratio = 2.0 * (cut - box["x0"]) / max(box["x1"] - box["x0"], 1.0)
            gap = max(second_edge - first_edge, 0.0)
            balance = abs(len(first) - len(second)) / len(group)
            candidates.append((coverage, balance, -gap, "vertical", first, second, ratio))

    by_y = sorted(group, key=lambda w: (w["y0"], w["y1"], w["x0"], w["address"]))
    for index in range(1, len(by_y)):
        first = by_y[:index]
        second = by_y[index:]
        first_edge = max(w["y1"] for w in first)
        second_edge = min(w["y0"] for w in second)
        if first_edge <= second_edge + TOL:
            a = bounds(first)
            b = bounds(second)
            span = max(box["x1"] - box["x0"], 1.0)
            coverage = (
                abs(a["x0"] - box["x0"]) + abs(a["x1"] - box["x1"])
                + abs(b["x0"] - box["x0"]) + abs(b["x1"] - box["x1"])
            ) / span
            cut = (first_edge + second_edge) / 2.0
            ratio = 2.0 * (cut - box["y0"]) / max(box["y1"] - box["y0"], 1.0)
            gap = max(second_edge - first_edge, 0.0)
            balance = abs(len(first) - len(second)) / len(group)
            candidates.append((coverage, balance, -gap, "horizontal", first, second, ratio))

    return candidates


def fallback_split(group):
    box = bounds(group)
    horizontal_span = box["x1"] - box["x0"]
    vertical_span = box["y1"] - box["y0"]
    if horizontal_span >= vertical_span:
        ordered = sorted(group, key=lambda w: ((w["x0"] + w["x1"]) / 2.0, w["address"]))
        orientation = "vertical"
    else:
        ordered = sorted(group, key=lambda w: ((w["y0"] + w["y1"]) / 2.0, w["address"]))
        orientation = "horizontal"
    index = max(1, len(ordered) // 2)
    return orientation, ordered[:index], ordered[index:]


def build(group):
    if len(group) == 1:
        return {"leaf": group[0]["address"], "exact": True}

    candidates = split_candidates(group)
    exact = bool(candidates)
    if candidates:
        _, _, _, orientation, first, second, ratio = min(candidates, key=lambda c: (c[0], c[1], c[2], c[3]))
    else:
        orientation, first, second = fallback_split(group)
        box = bounds(group)
        a = bounds(first)
        b = bounds(second)
        if orientation == "vertical":
            cut = (a["x1"] + b["x0"]) / 2.0
            ratio = 2.0 * (cut - box["x0"]) / max(box["x1"] - box["x0"], 1.0)
        else:
            cut = (a["y1"] + b["y0"]) / 2.0
            ratio = 2.0 * (cut - box["y0"]) / max(box["y1"] - box["y0"], 1.0)

    ratio = max(0.1, min(1.9, ratio))
    left = build(first)
    right = build(second)
    return {
        "orientation": orientation,
        "ratio": ratio,
        "first": left,
        "second": right,
        "exact": exact and left.get("exact", False) and right.get("exact", False),
    }


def representative(node):
    if "leaf" in node:
        return node["leaf"]
    return representative(node["first"])


def emit(node, operations):
    if "leaf" in node:
        return
    anchor = representative(node["first"])
    new_window = representative(node["second"])
    operations.append({
        "anchor": anchor,
        "new": new_window,
        "direction": "r" if node["orientation"] == "vertical" else "d",
        "ratio": round(float(node["ratio"]), 6),
    })
    emit(node["first"], operations)
    emit(node["second"], operations)


if not items:
    print(json.dumps({"initial": "", "operations": [], "exact": True}))
    sys.exit(0)

root = build(items)
operations = []
emit(root, operations)
print(json.dumps({
    "initial": representative(root),
    "operations": operations,
    "exact": bool(root.get("exact", True)),
}, separators=(",", ":")))
PY
}

workspace_has_existing_tiled_windows() {
  local ws="$1"
  clients_json | jq -e --arg ws "$ws" 'any(.[]; .workspace.name == $ws and .mapped == true and (.floating // false) == false)' >/dev/null
}

monitor_exists() {
  local monitor="$1"
  monitors_json | jq -e --arg m "$monitor" 'any(.[]; .name == $m)' >/dev/null
}

prepare_target_workspace() {
  local ws="$1" state_json="$2" monitor current_monitor
  monitor="$(jq -r --arg ws "$ws" '.workspaces[$ws].monitor // ""' <<<"$state_json")"

  focus_ws "$ws" >/dev/null 2>&1 || return 1

  if [[ -n "$monitor" ]] && monitor_exists "$monitor"; then
    current_monitor="$(workspaces_json | jq -r --arg ws "$ws" '([.[] | select(.name == $ws)][0].monitor) // ""')"
    if [[ "$current_monitor" != "$monitor" ]]; then
      move_workspace_to_monitor "$ws" "$monitor" >/dev/null 2>&1 || true
      focus_ws "$ws" >/dev/null 2>&1 || return 1
    fi
  fi
}

restore_floating_windows() {
  local ws="$1" windows_json="$2" live="$3"
  local row addr x y w h

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    addr="$(jq -r '.address' <<<"$row")"
    grep -qx "$addr" <<<"$live" || continue
    x="$(jq -r '.x' <<<"$row")"
    y="$(jq -r '.y' <<<"$row")"
    w="$(jq -r '.w' <<<"$row")"
    h="$(jq -r '.h' <<<"$row")"

    set_window_floating "$addr" true >/dev/null 2>&1 || true
    move_addr_to_ws "$addr" "$ws" >/dev/null 2>&1 || true
    move_window_exact "$addr" "$x" "$y" >/dev/null 2>&1 || true
    resize_window_exact "$addr" "$w" "$h" >/dev/null 2>&1 || true
  done < <(jq -c 'map(select(.floating == true)) | sort_by(.focus_history) | .[]' <<<"$windows_json")
}

restore_saved_window_modes() {
  local windows_json="$1" live="$2" row addr pseudo
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    addr="$(jq -r '.address' <<<"$row")"
    grep -qx "$addr" <<<"$live" || continue
    pseudo="$(jq -r '.pseudo // false' <<<"$row")"
    set_window_pseudo "$addr" "$pseudo" >/dev/null 2>&1 || true
  done < <(jq -c '.[] | select(.floating == false)' <<<"$windows_json")
}

restore_workspace_fallback() {
  local ws="$1" state_json="$2" windows_json live row addr
  windows_json="$(jq -c --arg ws "$ws" '.windows | map(select(.orig_ws == $ws))' <<<"$state_json")"
  live="$(live_addr_set || true)"

  prepare_target_workspace "$ws" "$state_json" || true

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    addr="$(jq -r '.address' <<<"$row")"
    grep -qx "$addr" <<<"$live" || continue
    set_window_floating "$addr" false >/dev/null 2>&1 || true
    move_addr_to_ws "$addr" "$ws" >/dev/null 2>&1 || true
    focus_addr "$addr" >/dev/null 2>&1 || true
  done < <(jq -c 'map(select(.floating == false)) | sort_by(.x, .y) | .[]' <<<"$windows_json")

  restore_saved_window_modes "$windows_json" "$live"
  restore_floating_windows "$ws" "$windows_json" "$live"
}

restore_workspace_dwindle() {
  local ws="$1" state_json="$2"
  local windows_json tiled_json live plan initial exact row anchor new_window direction ratio addr

  windows_json="$(jq -c --arg ws "$ws" '.windows | map(select(.orig_ws == $ws))' <<<"$state_json")"
  live="$(live_addr_set || true)"
  tiled_json="$(jq -c --arg live "$live" '
    map(select(.floating == false))
    | map(select(.address as $a | ($live | split("\n") | index($a)) != null))
  ' <<<"$windows_json")"

  # Exact reconstruction requires an empty original tiled workspace. New windows
  # opened there while mixing are preserved by falling back instead.
  if workspace_has_existing_tiled_windows "$ws"; then
    return 1
  fi

  prepare_dwindle_restore || return 1
  prepare_target_workspace "$ws" "$state_json" || return 1

  plan="$(dwindle_plan_json "$tiled_json")" || return 1
  initial="$(jq -r '.initial // ""' <<<"$plan")"
  exact="$(jq -r '.exact // false' <<<"$plan")"

  # Normalize originally tiled windows before rebuilding the tree.
  jq -r '.[].address' <<<"$tiled_json" | while IFS= read -r addr; do
    [[ -n "$addr" ]] || continue
    set_window_floating "$addr" false >/dev/null 2>&1 || true
  done

  if [[ -n "$initial" ]]; then
    move_addr_to_ws "$initial" "$ws" || return 1
    focus_addr "$initial" >/dev/null 2>&1 || true
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    anchor="$(jq -r '.anchor' <<<"$row")"
    new_window="$(jq -r '.new' <<<"$row")"
    direction="$(jq -r '.direction' <<<"$row")"
    ratio="$(jq -r '.ratio' <<<"$row")"

    focus_addr "$anchor" || return 1
    layout_msg "preselect $direction" || return 1
    move_addr_to_ws "$new_window" "$ws" || return 1
    layout_msg "preselect reset" >/dev/null 2>&1 || true
    focus_addr "$anchor" || return 1
    layout_msg "splitratio $ratio exact" || return 1
  done < <(jq -c '.operations[]' <<<"$plan")

  layout_msg "preselect reset" >/dev/null 2>&1 || true
  restore_saved_window_modes "$windows_json" "$live"
  restore_floating_windows "$ws" "$windows_json" "$live"

  [[ "$exact" == "true" ]] || err "workspace $ws: used geometric fallback for part of the dwindle tree"
}

restore_workspace() {
  local ws="$1" state_json="$2" layout
  layout="$(jq -r --arg ws "$ws" '.workspaces[$ws].layout // "unknown"' <<<"$state_json")"

  if [[ "$layout" == "dwindle" ]] && restore_workspace_dwindle "$ws" "$state_json"; then
    return 0
  fi

  restore_workspace_fallback "$ws" "$state_json"
}

restore_previous_focus() {
  local state_json="$1" prev_ws prev_window live
  prev_ws="$(jq -r '.prev_ws // ""' <<<"$state_json")"
  prev_window="$(jq -r '.prev_window // ""' <<<"$state_json")"
  live="$(live_addr_set || true)"

  if [[ -n "$prev_window" ]] && grep -qx "$prev_window" <<<"$live"; then
    focus_addr "$prev_window" >/dev/null 2>&1 || true
  elif [[ -n "$prev_ws" ]]; then
    focus_ws "$prev_ws" >/dev/null 2>&1 || true
  fi
}

# ---------- Toggle ----------
apply_toggle_immediate() {
  local label="$1"
  local state mix_ws first_add prev_ws prev_window moves_to_add meta remaining addr row

  state="$(load_state)"
  if [[ "$(jq -r '.mix_ws' <<<"$state")" == "" ]]; then
    local mon
    mon="$(focused_monitor)"
    state="$(empty_state_json | jq --arg m "$mon" --arg mw "$MIX_NAME" --argjson ts "$(now_epoch)" '
      .monitor = $m | .mix_ws = $mw | .created = $ts
    ')"
  fi
  mix_ws="$(jq -r '.mix_ws' <<<"$state")"

  if jq -e --arg l "$label" '.selection | index($l)' <<<"$state" >/dev/null; then
    restore_workspace "$label" "$state"

    state="$(jq -c --arg l "$label" '
      .selection -= [$l]
      | .windows = (.windows | map(select(.orig_ws != $l)))
      | del(.workspaces[$l])
    ' <<<"$state")"
    remaining="$(jq -r '.selection | length' <<<"$state")"

    if (( remaining > 0 )); then
      save_state <<<"$state"
      focus_ws "$mix_ws" >/dev/null 2>&1 || true
    else
      restore_previous_focus "$state"
      save_state <<<"$(empty_state_json)"
    fi
    return
  fi

  first_add="$(jq -r '((.selection | length) == 0)' <<<"$state")"
  if [[ "$first_add" == "true" ]]; then
    prev_ws="$(focused_ws_label)"
    prev_window="$(focused_window_addr)"
    state="$(jq -c --arg p "${prev_ws:-}" --arg w "${prev_window:-}" '
      .prev_ws = $p | .prev_window = $w
    ' <<<"$state")"
  fi

  moves_to_add="$(clients_from_label_as_moves "$label")"
  meta="$(workspace_meta "$label")"

  state="$(jq -c --arg l "$label" --argjson add "$moves_to_add" --argjson meta "$meta" '
    .selection += [$l]
    | .windows = (.windows + $add | unique_by(.address))
    | .workspaces[$l] = $meta
  ' <<<"$state")"
  save_state <<<"$state"

  focus_ws "$mix_ws" >/dev/null 2>&1 || true
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    addr="$(jq -r '.address' <<<"$row")"
    move_addr_to_ws "$addr" "$mix_ws" >/dev/null 2>&1 || true
    if [[ "$(jq -r '.floating' <<<"$row")" == "false" ]]; then
      focus_addr "$addr" >/dev/null 2>&1 || true
    fi
  done < <(jq -c 'sort_by(.floating, .x, .y) | .[]' <<<"$moves_to_add")
  focus_ws "$mix_ws" >/dev/null 2>&1 || true
}

# ---------- Main ----------
require_deps
cmd="${1:-status}"

case "$cmd" in
  toggle)
    ws_arg="${2:-}"
    [[ -n "$ws_arg" ]] || { err "toggle needs a workspace id/name"; exit 1; }
    label="$(ws_label_from_arg "$ws_arg")"
    apply_toggle_immediate "$label"
    ;;

  restore)
    state="$(load_state)"

    while IFS= read -r ws; do
      [[ -n "$ws" ]] || continue
      restore_workspace "$ws" "$state"
    done < <(jq -r '.selection[]' <<<"$state")

    restore_previous_focus "$state"
    save_state <<<"$(empty_state_json)"
    ;;

  focus)
    state="$(load_state)"
    mix_ws="$(jq -r '.mix_ws' <<<"$state")"
    if [[ -z "$mix_ws" ]] || [[ "$mix_ws" == "null" ]]; then
      mon="$(focused_monitor)"
      state="$(empty_state_json | jq --arg m "$mon" --arg mw "$MIX_NAME" --argjson ts "$(now_epoch)" '
        .monitor = $m | .mix_ws = $mw | .created = $ts
      ')"
      save_state <<<"$state"
      mix_ws="$MIX_NAME"
    fi
    focus_ws "$mix_ws" >/dev/null
    ;;

  build) # backward-compat: just focus mixed view
    "$0" focus
    ;;

  status)
    state="$(load_state)"
    printf 'state_file: %s\n' "$STATE_FILE"
    mix="$(jq -r '.mix_ws // ""' <<<"$state")"
    mon="$(jq -r '.monitor // ""' <<<"$state")"
    prev="$(jq -r '.prev_ws // ""' <<<"$state")"
    prev_window="$(jq -r '.prev_window // ""' <<<"$state")"
    sel="$(jq -r '.selection | join(",")' <<<"$state")"
    win_count="$(jq -r '.windows | length' <<<"$state")"
    printf 'mix_ws: %s\nmonitor: %s\nprev_ws: %s\nprev_window: %s\nselection: %s\nwindows: %s\n' \
      "$mix" "$mon" "$prev" "$prev_window" "$sel" "$win_count"
    ;;

  doctor)
    printf '== PATH ==\n%s\n\n' "$PATH"
    printf '== which hyprctl ==\n'; command -v hyprctl || true; printf '\n'
    printf '== which jq ==\n'; command -v jq || true; printf '\n'
    printf '== which python ==\n'; command -v python || true; printf '\n'
    printf '== hyprctl monitors ==\n'
    monitors_json | jq '. | map({name, focused, "active": .activeWorkspace.name})' || true
    printf '\n== hyprctl clients (first 5) ==\n'
    clients_json | jq '.[0:5] | map({address, class, title, ws: .workspace, floating, at, size})' || true
    printf '\n== current state ==\n'
    "$0" status || true
    ;;

  *)
    err "unknown cmd: $cmd {toggle <ws>|restore|focus|build|status|doctor}"
    exit 2
    ;;
esac
