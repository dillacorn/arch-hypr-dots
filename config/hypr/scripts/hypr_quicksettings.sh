#!/usr/bin/env bash
# Awtarchy Quick Settings entrypoint.
# The existing UI implementation is kept in hypr_quicksettings_core.sh while
# this entrypoint wires Quickshell-specific controls into it.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/hypr_quicksettings_core.sh"
BAR_SETTINGS_SCRIPT="${SCRIPT_DIR}/quickshell_bar_settings.sh"

[[ -r "$CORE_SCRIPT" ]] || {
  printf 'missing: %s\n' "$CORE_SCRIPT" >&2
  exit 1
}

# Load the established Quick Settings implementation without executing its
# final main call. Overrides below remain small and isolated.
# shellcheck disable=SC1090
source <(sed '/^main "\$@"$/d' "$CORE_SCRIPT")

MENU_ITEMS=(
  "Brightness"
  "Display"
  "Bar"
  "Night Light"
  "Vibrance"
  "Submap"
  "Wallpaper Picker"
  "sched-ext"
  "Stop sched-ext"
)

launch_terminal() {
  local self
  self="$(readlink -f "${BASH_SOURCE[0]}")"

  if close_existing_quicksettings; then
    return 0
  fi

  if [[ -t 1 ]]; then
    exec "$self" --ui
  fi

  if have_cmd kitty; then
    exec kitty --class "$TERM_CLASS" -e "$self" --ui
  fi
  if have_cmd foot; then
    exec foot --app-id="$TERM_CLASS" "$self" --ui
  fi
  if have_cmd alacritty; then
    exec alacritty --class "$TERM_CLASS" -e "$self" --ui
  fi
  if have_cmd wezterm; then
    exec wezterm start --class "$TERM_CLASS" -- "$self" --ui
  fi
  if have_cmd konsole; then
    exec konsole --appname "$TERM_CLASS" -e "$self" --ui
  fi
  if have_cmd gnome-terminal; then
    exec gnome-terminal --title="$TERM_CLASS" -- "$self" --ui
  fi

  exec xterm -T "$TERM_CLASS" -e "$self" --ui
}

select_bar() {
  if [[ ! -x "$BAR_SETTINGS_SCRIPT" ]]; then
    MSG="bar settings: missing $BAR_SETTINGS_SCRIPT"
    return 1
  fi

  if "$BAR_SETTINGS_SCRIPT" --embedded; then
    MSG='bar settings updated'
  else
    MSG='bar settings closed'
  fi
}

valid_scheduler() {
  local candidate="$1" scheduler
  for scheduler in "${SCHED_EXT_ITEMS[@]}"; do
    [[ "$candidate" == "$scheduler" ]] && return 0
  done
  return 1
}

valid_scheduler_profile() {
  local scheduler="$1" candidate="$2" profile
  while IFS= read -r profile; do
    [[ "$candidate" == "$profile" ]] && return 0
  done < <(sched_ext_profiles_for "$scheduler")
  return 1
}

machine_status() {
  local panel_monitor="${1:-}" brightness_monitor="${2:-}" monitors_json schedulers_json scheduler_authorized
  local scheduler profiles_json profile custom autopower summary sun_temp

  command -v jq >/dev/null 2>&1 || {
    printf 'hypr_quicksettings: jq is required\n' >&2
    return 127
  }

  if [[ -n "$brightness_monitor" && "$brightness_monitor" != "Focused display" ]]; then
    BRIGHTNESS_MONITOR="$brightness_monitor"
  else
    BRIGHTNESS_MONITOR=""
  fi

  sched_ext_state_load
  refresh_all

  scheduler_authorized=false
  if (( EUID == 0 )) || sudo_can_run_scxctl_noninteractive; then
    scheduler_authorized=true
  fi

  if [[ -n "$panel_monitor" && -x "$QUICKSHELL_SCRIPT" ]]; then
    BAR_MONITOR="$panel_monitor"
    BAR_POSITION="$(run_capture "$QUICKSHELL_SCRIPT" getpos "$panel_monitor" || true)"
    BAR_ENABLED="$(run_capture "$QUICKSHELL_SCRIPT" getenabled "$panel_monitor" || true)"
  fi

  monitors_json='[]'
  if have_cmd hyprctl; then
    monitors_json="$(hyprctl -j monitors 2>/dev/null | jq -c '
      [ .[]
        | select((.disabled // false) == false)
        | {
            name:(.name // ""),
            description:(.description // ""),
            focused:(.focused // false),
            width:(.width // 0),
            height:(.height // 0),
            refresh_rate:((.refreshRate // 0) | round)
          }
      ]
    ' 2>/dev/null || printf '[]')"
  fi

  schedulers_json='[]'
  for scheduler in "${SCHED_EXT_ITEMS[@]}"; do
    profiles_json="$(sched_ext_profiles_for "$scheduler" | jq -Rsc 'split("\n") | map(select(length > 0))')"
    profile="${SCHED_EXT_PROFILE_MAP[$scheduler]:-Default}"
    custom="$(sched_ext_normalize_args "${SCHED_EXT_CUSTOM_ARGS_MAP[$scheduler]:-}")"
    autopower="${SCHED_EXT_LAVD_AUTOPOWER_MAP[$scheduler]:-0}"
    summary="$(sched_ext_config_summary "$scheduler")"
    schedulers_json="$(jq -c \
      --arg scheduler "$scheduler" \
      --arg profile "$profile" \
      --arg custom "$custom" \
      --arg autopower "$autopower" \
      --arg summary "$summary" \
      --argjson profiles "$profiles_json" '
        . + [{
          name:$scheduler,
          profile:$profile,
          profiles:$profiles,
          custom_args:$custom,
          autopower:($autopower == "1"),
          summary:$summary
        }]
      ' <<<"$schedulers_json")"
  done

  sun_temp="${SUN_TEMP%K}"
  jq -cn \
    --arg brightness_target "${BRIGHTNESS_MONITOR:-Focused display}" \
    --arg brightness_connector "$BR_CONN" \
    --arg brightness_current "$BR_CUR" \
    --arg brightness_max "$BR_MAX" \
    --arg bar_monitor "$BAR_MONITOR" \
    --arg bar_position "$BAR_POSITION" \
    --arg bar_enabled "$BAR_ENABLED" \
    --arg sun_temperature "$sun_temp" \
    --arg sun_identity "$SUN_IDENTITY" \
    --arg sun_enabled "$SUN_ENABLED" \
    --arg vibrance_value "$VIB_VAL" \
    --arg vibrance_enabled "$VIB_ENABLED" \
    --arg submap "$SUBMAP_CURRENT" \
    --arg scheduler_running "$SCHED_EXT_RUNNING" \
    --arg scheduler_mode "$SCHED_EXT_MODE" \
    --arg scheduler_enabled "$SCHED_EXT_ENABLED" \
    --arg scheduler_available "$(have_cmd scxctl && printf true || printf false)" \
    --arg scheduler_authorized "$scheduler_authorized" \
    --argjson monitors "$monitors_json" \
    --argjson schedulers "$schedulers_json" '
      def number_or_null: try tonumber catch null;
      {
        monitors:$monitors,
        brightness:{
          target:$brightness_target,
          connector:$brightness_connector,
          current:($brightness_current | number_or_null),
          max:($brightness_max | number_or_null)
        },
        bar:{
          monitor:$bar_monitor,
          position:$bar_position,
          enabled:($bar_enabled == "true")
        },
        night_light:{
          temperature:($sun_temperature | number_or_null),
          identity:$sun_identity,
          enabled:(($sun_identity == "false") or ($sun_enabled == "1"))
        },
        vibrance:{
          value:($vibrance_value | number_or_null),
          enabled:($vibrance_enabled == "1")
        },
        submap:$submap,
        sched_ext:{
          running:$scheduler_running,
          mode:$scheduler_mode,
          enabled:($scheduler_enabled == "1"),
          available:($scheduler_available == "true"),
          authorized:($scheduler_authorized == "true"),
          schedulers:$schedulers
        }
      }
    '
}

machine_brightness_adjust() {
  local monitor="$1" delta="$2" target
  [[ "$delta" =~ ^-?[0-9]+$ ]] || return 2
  BRIGHTNESS_MONITOR="$monitor"
  refresh_brightness
  [[ "$BR_CUR" =~ ^[0-9]+$ && "$BR_MAX" =~ ^[1-9][0-9]*$ ]] || return 1
  target=$(( BR_CUR + delta ))
  (( target < 0 )) && target=0
  (( target > BR_MAX )) && target="$BR_MAX"
  brightness_quiet set "$target"
}

machine_brightness_percent() {
  local monitor="$1" percent="$2" target
  [[ "$percent" =~ ^[0-9]+$ ]] || return 2
  (( percent > 100 )) && percent=100
  BRIGHTNESS_MONITOR="$monitor"
  refresh_brightness
  [[ "$BR_MAX" =~ ^[1-9][0-9]*$ ]] || return 1
  target=$(( (BR_MAX * percent + 50) / 100 ))
  brightness_quiet set "$target"
}

machine_scheduler_authorize() {
  if (( EUID != 0 )) && [[ ! -t 0 ]]; then
    printf 'sched-ext authorization requires an interactive terminal\n' >&2
    return 4
  fi

  if ! ensure_scxctl_nopasswd_rule; then
    printf '%s\n' "${MSG:-sched-ext authorization failed}" >&2
    return 1
  fi

  printf '%s\n' "${MSG:-sched-ext authorization complete}"
  if have_cmd qs; then
    qs -c awtarchy ipc call quicksettings refresh >/dev/null 2>&1 || true
  fi
}

machine_scheduler_start() {
  local scheduler="$1"
  valid_scheduler "$scheduler" || return 2
  sched_ext_state_load
  refresh_sched_ext
  sched_ext_deps_ok || return 1
  if (( EUID != 0 )) && ! sudo_can_run_scxctl_noninteractive; then
    printf 'sched-ext authorization has not been configured\n' >&2
    return 3
  fi
  sched_ext_switch_or_start "$scheduler"
}

machine_scheduler_stop() {
  refresh_sched_ext
  if (( EUID != 0 )) && ! sudo_can_run_scxctl_noninteractive; then
    printf 'sched-ext authorization has not been configured\n' >&2
    return 3
  fi
  sched_ext_stop
}

machine_action() {
  local action="${1:-}" monitor value scheduler profile custom
  shift || true
  case "$action" in
    brightness-adjust)
      [[ -n ${1:-} && -n ${2:-} ]] || return 2
      machine_brightness_adjust "$1" "$2"
      ;;
    brightness-percent)
      [[ -n ${1:-} && -n ${2:-} ]] || return 2
      machine_brightness_percent "$1" "$2"
      ;;
    bar-enabled)
      monitor="${1:-}"; value="${2:-}"
      [[ -n "$monitor" && "$value" =~ ^(true|false)$ ]] || return 2
      "$QUICKSHELL_SCRIPT" setenabled "$monitor" "$value"
      ;;
    bar-position)
      monitor="${1:-}"; value="${2:-}"
      [[ -n "$monitor" && "$value" =~ ^(top|bottom|left|right)$ ]] || return 2
      "$QUICKSHELL_SCRIPT" setpos "$monitor" "$value"
      ;;
    night-light)
      value="${1:-}"
      [[ "$value" =~ ^(toggle|up|down|on|off)$ ]] || return 2
      "$SUNSET_SCRIPT" "$value"
      ;;
    vibrance)
      value="${1:-}"
      [[ "$value" =~ ^(toggle|up|down|off)$ ]] || return 2
      "$VIBRANCE_SCRIPT" "$value"
      ;;
    submap)
      value="${1:-}"
      [[ "$value" =~ ^(reset|noalt|mouse|vm)$ ]] || return 2
      set_submap "$value"
      ;;
    wallpaper)
      launch_awtwall
      ;;
    scheduler-start)
      machine_scheduler_start "${1:-}"
      ;;
    scheduler-stop)
      machine_scheduler_stop
      ;;
    scheduler-profile)
      scheduler="${1:-}"; profile="${2:-}"
      valid_scheduler "$scheduler" && valid_scheduler_profile "$scheduler" "$profile" || return 2
      sched_ext_state_load
      SCHED_EXT_PROFILE_MAP["$scheduler"]="$profile"
      sched_ext_state_save
      ;;
    scheduler-args)
      scheduler="${1:-}"; custom="${2:-}"
      valid_scheduler "$scheduler" || return 2
      sched_ext_state_load
      SCHED_EXT_CUSTOM_ARGS_MAP["$scheduler"]="$(sched_ext_normalize_args "$custom")"
      sched_ext_state_save
      ;;
    scheduler-autopower)
      scheduler="${1:-}"; value="${2:-}"
      [[ "$scheduler" == scx_lavd && "$value" =~ ^(true|false)$ ]] || return 2
      sched_ext_state_load
      SCHED_EXT_LAVD_AUTOPOWER_MAP["$scheduler"]=$([[ "$value" == true ]] && printf 1 || printf 0)
      sched_ext_state_save
      ;;
    scheduler-reset)
      scheduler="${1:-}"
      valid_scheduler "$scheduler" || return 2
      sched_ext_state_load
      sched_ext_reset_config "$scheduler"
      ;;
    *)
      printf 'unknown Quick Settings action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

case "${1:-}" in
  --status-json)
    shift
    machine_status "${1:-}" "${2:-}"
    ;;
  --authorize-scheduler)
    machine_scheduler_authorize
    ;;
  --action)
    shift
    machine_action "$@"
    ;;
  *)
    main "$@"
    ;;
esac
