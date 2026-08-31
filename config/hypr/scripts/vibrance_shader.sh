#!/usr/bin/env bash
set -euo pipefail

# vibrance_shader.sh
# - Edits ~/.config/hypr/shaders/vibrance (#define VIBRANCE X)
# - Supports native Hyprland Lua: hl.config({ decoration = { screen_shader = "..." } })
# - Still supports old hyprland.conf screen_shader lines as fallback.

HYPR_LUA="${HYPRLAND_LUA:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua}"
HYPR_CONF="${HYPRLAND_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf}"
SHADER="${VIBRANCE_SHADER_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/shaders/vibrance}"

if [[ -f "$HYPR_LUA" ]]; then
  CONF="$HYPR_LUA"
  CONF_MODE="lua"
elif [[ -f "$HYPR_CONF" ]]; then
  CONF="$HYPR_CONF"
  CONF_MODE="conf"
else
  CONF="$HYPR_LUA"
  CONF_MODE="lua"
fi

LEVELS=(0.00 0.15 0.25 0.35 0.45 0.55 0.65 0.75 0.85 0.95)

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need_file() { [[ -f "$1" ]] || die "missing: $1"; }

notify() {
  local msg="$1"
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Hyprland -t 2200 "Vibrance" "$msg" >/dev/null 2>&1 || true
}

fmt2() { awk -v x="$1" 'BEGIN{printf "%.2f", x+0.0}'; }

read_vibrance() {
  local v
  v="$(awk '$1=="#define" && $2=="VIBRANCE" {print $3; exit}' "$SHADER" 2>/dev/null || true)"
  [[ -n "${v:-}" ]] || v="0.00"
  fmt2 "$v"
}

nearest_index() {
  local cur="$1"
  local best_i=0
  local best_d="999999"
  local d i
  for i in "${!LEVELS[@]}"; do
    d="$(awk -v a="$cur" -v b="${LEVELS[$i]}" 'BEGIN{d=a-b; if(d<0)d=-d; printf "%.6f", d}')"
    if awk -v d="$d" -v bd="$best_d" 'BEGIN{exit !(d < bd)}'; then
      best_d="$d"
      best_i="$i"
    fi
  done
  printf '%s' "$best_i"
}

set_shader_define() {
  local new="$1"

  if grep -Eq '^[[:space:]]*#define[[:space:]]+VIBRANCE[[:space:]]+' "$SHADER"; then
    perl -i -pe "s/^[ \t]*#define[ \t]+VIBRANCE[ \t]+[-0-9.]+[ \t]*\$/#define VIBRANCE $new/" "$SHADER"
  else
    awk -v new="$new" '
      BEGIN{ins=0}
      {
        if (!ins && $0 ~ /^[ \t]*void[ \t]+main[ \t]*\(/) {
          print "#define VIBRANCE " new
          print ""
          ins=1
        }
        print
      }
      END{
        if(!ins){
          print ""
          print "#define VIBRANCE " new
        }
      }
    ' "$SHADER" >"${SHADER}.tmp" && mv -f "${SHADER}.tmp" "$SHADER"
  fi

  awk '
    BEGIN{prev_define=0}
    {
      if (prev_define && $0 ~ /^[ \t]*void[ \t]+main[ \t]*\(/) print ""
      print
      prev_define = ($0 ~ /^[ \t]*#define[ \t]+VIBRANCE[ \t]+[-0-9.]+[ \t]*$/) ? 1 : 0
    }
  ' "$SHADER" >"${SHADER}.tmp" && mv -f "${SHADER}.tmp" "$SHADER"
}

lua_vibrance_is_active() {
  python - "$CONF" <<'PY_LUA_ACTIVE'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
line_re = re.compile(r'^\s*hl\.config\(\{\s*decoration\s*=\s*\{\s*screen_shader\s*=\s*("(?:\\.|[^"\\])*")\s*\}\s*\}\s*\)\s*$', re.M)

for m in line_re.finditer(text):
    raw = m.group(1)
    try:
        value = bytes(raw[1:-1], "utf-8").decode("unicode_escape")
    except Exception:
        value = raw[1:-1]
    if value.rstrip().endswith("/shaders/vibrance"):
        raise SystemExit(0)

raise SystemExit(1)
PY_LUA_ACTIVE
}

set_lua_vibrance_state() {
  local enable="$1"
  python - "$CONF" "$enable" "$HOME/.config/hypr/shaders/vibrance" <<'PY_LUA_SET'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
enable = sys.argv[2] == "1"
default_path = sys.argv[3]

lines = path.read_text().splitlines(keepends=True)

shader_re = re.compile(
    r'^(?P<indent>\s*)(?P<comment>--\s*)?'
    r'hl\.config\(\{\s*decoration\s*=\s*\{\s*screen_shader\s*=\s*'
    r'(?P<quote>"(?:\\.|[^"\\])*")'
    r'\s*\}\s*\}\s*\)(?P<trail>\s*)$'
)

legacy_config_set_re = re.compile(
    r'^\s*(?:--\s*)?config_set\(\{\[\[decoration\]\]\},\s*\[\[screen_shader\]\],.*$'
)

def decode_lua_string(raw: str) -> str:
    try:
        return bytes(raw[1:-1], "utf-8").decode("unicode_escape")
    except Exception:
        return raw[1:-1]

def lua_string(value: str) -> str:
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'

out = []
vib_found = False
vib_done = False
first_shader_index = None
insert_before_index = None

for line in lines:
    body = line[:-1] if line.endswith("\n") else line
    newline = "\n" if line.endswith("\n") else ""

    # Delete obsolete helper-era shader lines. They are broken without hyprlang.lua/config_set().
    if legacy_config_set_re.match(body):
        continue

    m = shader_re.match(body)
    if m:
        if first_shader_index is None:
            first_shader_index = len(out)

        value = decode_lua_string(m.group("quote"))
        is_vibrance = value.rstrip().endswith("/shaders/vibrance")
        indent = m.group("indent")
        trail = m.group("trail")

        if is_vibrance:
            vib_found = True
            if enable and not vib_done:
                out.append(f'{indent}hl.config({{ decoration = {{ screen_shader = {lua_string(default_path)} }} }}){trail}{newline}')
                vib_done = True
            else:
                out.append(f'{indent}-- hl.config({{ decoration = {{ screen_shader = {lua_string(default_path)} }} }}){trail}{newline}')
            continue

        # When enabling vibrance, comment every other active shader line.
        if enable and not m.group("comment"):
            out.append(f'{indent}-- {body[len(indent):]}{newline}')
        else:
            out.append(line)
        continue

    if insert_before_index is None and "Shaders that require" in body:
        insert_before_index = len(out)

    out.append(line)

if enable and not vib_found:
    new_line = f'    hl.config({{ decoration = {{ screen_shader = {lua_string(default_path)} }} }})\n'
    if insert_before_index is not None:
        out.insert(insert_before_index, new_line)
    elif first_shader_index is not None:
        out.insert(first_shader_index, new_line)
    else:
        out.append("\n-- Shaders\n")
        out.append(new_line)

path.write_text("".join(out))
PY_LUA_SET
}

conf_vibrance_is_active() {
  awk '
    function strip_cr(s){ sub(/\r$/, "", s); return s }
    function ltrim(s){ sub(/^[ \t]+/, "", s); return s }
    {
      line=strip_cr($0)
      t=ltrim(line)
      if (t ~ /^#/) next
      if (t !~ /^screen_shader[ \t]*=/) next
      sub(/^screen_shader[ \t]*=/, "", t)
      sub(/#.*/, "", t)
      gsub(/[ \t]/, "", t)
      if (t ~ /\/shaders\/vibrance$/) { found=1; exit }
    }
    END{ exit !found }
  ' "$CONF"
}

set_conf_vibrance_state() {
  local enable="$1"
  local tmp default_path
  tmp="$(mktemp)"
  default_path="${HOME}/.config/hypr/shaders/vibrance"

  awk -v enable="$enable" -v default_path="$default_path" '
    function strip_cr(s){ sub(/\r$/, "", s); return s }
    function ltrim(s){ sub(/^[ \t]+/, "", s); return s }
    function indent_of(s){ match(s,/^[ \t]*/); return substr(s,RSTART,RLENGTH) }

    function is_shader_line(line, t){
      t=line; t=strip_cr(t); t=ltrim(t)
      return (t ~ /^#?[ \t]*screen_shader[ \t]*=/) ? 1 : 0
    }

    function shader_is_active(line, t){
      t=line; t=strip_cr(t); t=ltrim(t)
      return (t ~ /^screen_shader[ \t]*=/) ? 1 : 0
    }

    function shader_path_norm(line, t){
      t=line; t=strip_cr(t); t=ltrim(t)
      sub(/^#[ \t]*/, "", t)
      if (t !~ /^screen_shader[ \t]*=/) return ""
      sub(/^screen_shader[ \t]*=/, "", t)
      sub(/#.*/, "", t)
      gsub(/[ \t]/, "", t)
      return t
    }

    function is_vibrance(line, p){
      p=shader_path_norm(line)
      return (p ~ /\/shaders\/vibrance$/) ? 1 : 0
    }

    BEGIN{ vib_found=0; first_vib_done=0; indent_guess="" }

    {
      line=strip_cr($0)
      if (indent_guess=="" && line ~ /^[ \t]*#?[ \t]*screen_shader[ \t]*=/) indent_guess=indent_of(line)

      if (is_shader_line(line)) {
        if (is_vibrance(line)) {
          vib_found=1
          ind=indent_of(line)
          rest=substr(line, length(ind)+1)
          if (enable=="1") {
            if (!first_vib_done) {
              sub(/^#[ \t]*/, "", rest)
              print ind rest
              first_vib_done=1
            } else {
              if (rest !~ /^#/) rest="#" rest
              sub(/^##+/, "#", rest)
              print ind rest
            }
            next
          } else {
            if (rest !~ /^#/) rest="#" rest
            sub(/^##+/, "#", rest)
            print ind rest
            next
          }
        } else if (enable=="1" && shader_is_active(line)) {
          ind=indent_of(line)
          rest=substr(line, length(ind)+1)
          if (rest !~ /^#/) rest="#" rest
          sub(/^##+/, "#", rest)
          print ind rest
          next
        }
      }

      print line
    }

    END{
      if (enable=="1" && vib_found==0) {
        ind = (indent_guess!="") ? indent_guess : "    "
        print ind "screen_shader = " default_path
      }
    }
  ' "$CONF" >"$tmp"

  mv -f "$tmp" "$CONF"
}

vibrance_is_active() {
  if [[ "$CONF_MODE" == "lua" ]]; then
    lua_vibrance_is_active
  else
    conf_vibrance_is_active
  fi
}

set_vibrance_state() {
  if [[ "$CONF_MODE" == "lua" ]]; then
    set_lua_vibrance_state "$1"
  else
    set_conf_vibrance_state "$1"
  fi
}

reload_hypr() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  hyprctl reload >/dev/null 2>&1 || true
}

apply_live_vibrance_state() {
  local enable="$1"
  command -v hyprctl >/dev/null 2>&1 || return 0

  if [[ "$enable" == "1" ]]; then
    hyprctl keyword decoration:screen_shader "$SHADER" >/dev/null 2>&1
  else
    hyprctl keyword decoration:screen_shader "" >/dev/null 2>&1
  fi
}

snap_level_value() {
  local raw="$1"
  local idx
  idx="$(nearest_index "$(fmt2 "$raw")")"
  printf '%s' "${LEVELS[$idx]}"
}

notify_enabled_or_off() {
  local want_enable="$1"
  local val="$2"
  if [[ "$want_enable" == "1" ]]; then
    notify "$val"
  else
    notify "off"
  fi
}

main() {
  local action="${1:-}"
  [[ -n "$action" ]] || die "usage: $0 up|down|toggle|off|set <val>|key <1..9|0>"

  need_file "$CONF"
  need_file "$SHADER"

  local cur idx new_idx new want_enable

  cur="$(read_vibrance)"
  idx="$(nearest_index "$cur")"

  case "$action" in
    up)
      new_idx="$(( idx + 1 ))"
      (( new_idx > ${#LEVELS[@]} - 1 )) && new_idx="$(( ${#LEVELS[@]} - 1 ))"
      new="${LEVELS[$new_idx]}"
      set_shader_define "$new"
      want_enable=1
      [[ "$new" == "0.00" ]] && want_enable=0
      set_vibrance_state "$want_enable"
      reload_hypr
      apply_live_vibrance_state "$want_enable"
      notify_enabled_or_off "$want_enable" "$new"
      ;;
    down)
      new_idx="$(( idx - 1 ))"
      (( new_idx < 0 )) && new_idx=0
      new="${LEVELS[$new_idx]}"
      set_shader_define "$new"
      want_enable=1
      [[ "$new" == "0.00" ]] && want_enable=0
      set_vibrance_state "$want_enable"
      reload_hypr
      apply_live_vibrance_state "$want_enable"
      notify_enabled_or_off "$want_enable" "$new"
      ;;
    toggle)
      if vibrance_is_active; then
        set_vibrance_state 0
        reload_hypr
        apply_live_vibrance_state 0
        notify "off"
      else
        set_vibrance_state 1
        reload_hypr
        apply_live_vibrance_state 1
        notify "$(read_vibrance)"
      fi
      ;;
    off)
      set_vibrance_state 0
      reload_hypr
      apply_live_vibrance_state 0
      notify "off"
      ;;
    set)
      [[ -n "${2:-}" ]] || die "usage: $0 set 0.35"
      new="$(snap_level_value "$2")"
      set_shader_define "$new"
      want_enable=1
      [[ "$new" == "0.00" ]] && want_enable=0
      set_vibrance_state "$want_enable"
      reload_hypr
      apply_live_vibrance_state "$want_enable"
      notify_enabled_or_off "$want_enable" "$new"
      ;;
    key)
      [[ -n "${2:-}" ]] || die "usage: $0 key 1..9|0"
      case "$2" in
        1) new="0.00" ;;
        2) new="0.15" ;;
        3) new="0.25" ;;
        4) new="0.35" ;;
        5) new="0.45" ;;
        6) new="0.55" ;;
        7) new="0.65" ;;
        8) new="0.75" ;;
        9) new="0.85" ;;
        0) new="0.95" ;;
        *) die "key must be 1..9 or 0" ;;
      esac
      set_shader_define "$new"
      want_enable=1
      [[ "$new" == "0.00" ]] && want_enable=0
      set_vibrance_state "$want_enable"
      reload_hypr
      apply_live_vibrance_state "$want_enable"
      notify_enabled_or_off "$want_enable" "$new"
      ;;
    *)
      die "usage: $0 up|down|toggle|off|set <val>|key <1..9|0>"
      ;;
  esac
}

main "$@"
