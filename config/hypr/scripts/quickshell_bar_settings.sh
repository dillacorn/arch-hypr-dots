#!/usr/bin/env bash
# Awtarchy Quickshell bar settings TUI.

set -euo pipefail

QUICKSHELL_SCRIPT="${HYPR_QUICKSHELL_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh}"
TITLE="Awtarchy Bar Settings"
EMBEDDED=0
TARGET="focused"
SEL=0
MSG=""
MOUSE_BUTTON=0
MOUSE_X=0
MOUSE_Y=0
MOUSE_RELEASE=0

MIN_BAR_SIZE=20
MAX_BAR_SIZE=80
MIN_ICON_SCALE=50
MAX_ICON_SCALE=200

[[ ${1:-} == --embedded ]] && EMBEDDED=1

[[ -x "$QUICKSHELL_SCRIPT" ]] || {
    printf 'bar settings: missing %s\n' "$QUICKSHELL_SCRIPT" >&2
    exit 1
}
command -v hyprctl >/dev/null 2>&1 || exit 127
command -v jq >/dev/null 2>&1 || exit 127

mouse_enable() { printf '\033[?1000h\033[?1006h'; }
mouse_disable() { printf '\033[?1000l\033[?1006l'; }

cleanup() {
    if (( EMBEDDED == 1 )); then
        mouse_enable
        printf '\033[?25l\033[0m'
    else
        mouse_disable
        printf '\033[?25h\033[0m\n'
    fi
}
trap cleanup EXIT INT TERM

term_cols() { tput cols 2>/dev/null || printf '80'; }
term_lines() { tput lines 2>/dev/null || printf '24'; }
ui_goto() { printf '\033[%s;%sH' "$1" "$2"; }
ui_clear_line() { printf '\033[2K'; }

read_key() {
    local key rest
    IFS= read -rsN1 key || return 1
    case "$key" in
        $'\r'|$'\n') printf '%s' '__ENTER__'; return 0 ;;
        $'\e') ;;
        *) printf '%s' "$key"; return 0 ;;
    esac

    if ! IFS= read -rsN1 -t 0.03 rest; then
        printf '%s' "$key"
        return 0
    fi
    key+="$rest"
    if [[ $rest == '[' ]]; then
        while IFS= read -rsN1 -t 0.03 rest; do
            key+="$rest"
            [[ $rest =~ [A-Za-z~] ]] && break
        done
    elif [[ $rest == O ]]; then
        if IFS= read -rsN1 -t 0.03 rest; then
            key+="$rest"
        fi
    fi
    printf '%s' "$key"
}

parse_mouse_event() {
    local seq="$1" payload final button x y
    [[ "$seq" == $'\e[<'* ]] || return 1
    final=${seq: -1}
    [[ $final == M || $final == m ]] || return 1
    payload=${seq#$'\e[<'}
    payload=${payload%M}
    payload=${payload%m}
    IFS=';' read -r button x y <<<"$payload"
    [[ $button =~ ^[0-9]+$ && $x =~ ^[0-9]+$ && $y =~ ^[0-9]+$ ]] || return 1
    MOUSE_BUTTON=$button
    MOUSE_X=$x
    MOUSE_Y=$y
    MOUSE_RELEASE=0
    [[ $final == m ]] && MOUSE_RELEASE=1
}

focused_monitor() {
    "$QUICKSHELL_SCRIPT" focused-monitor 2>/dev/null || true
}

list_monitors() {
    "$QUICKSHELL_SCRIPT" list-monitors 2>/dev/null || true
}

refresh_bar_state() {
    command -v qs >/dev/null 2>&1 || return 0
    qs -c awtarchy ipc call barstate refresh >/dev/null 2>&1 || true
}

target_label() {
    local focused
    case "$TARGET" in
        focused)
            focused="$(focused_monitor)"
            printf 'Focused display%s' "${focused:+ ($focused)}"
            ;;
        all) printf 'All displays' ;;
        *) printf '%s' "$TARGET" ;;
    esac
}

resolve_targets() {
    local focused
    case "$TARGET" in
        focused)
            focused="$(focused_monitor)"
            [[ -n $focused ]] && printf '%s\n' "$focused"
            ;;
        all) list_monitors ;;
        *) printf '%s\n' "$TARGET" ;;
    esac
}

common_value() {
    local command="$1" monitor value first="" seen=0
    while IFS= read -r monitor; do
        [[ -n $monitor ]] || continue
        value="$("$QUICKSHELL_SCRIPT" "$command" "$monitor" 2>/dev/null || true)"
        if (( seen == 0 )); then
            first="$value"
            seen=1
        elif [[ $value != "$first" ]]; then
            printf 'mixed'
            return 0
        fi
    done < <(resolve_targets)
    (( seen == 1 )) && printf '%s' "$first" || printf 'N/A'
}

format_visibility() {
    case "$(common_value getenabled)" in
        true) printf 'on' ;;
        false) printf 'off' ;;
        *) printf 'mixed' ;;
    esac
}

format_size() {
    local value
    value="$(common_value getsize)"
    case "$value" in
        0) printf 'default (28px horizontal / 36px vertical)' ;;
        mixed|N/A) printf '%s' "$value" ;;
        *) printf '%spx' "$value" ;;
    esac
}

format_scale() {
    local value
    value="$(common_value getscale)"
    case "$value" in
        mixed|N/A) printf '%s' "$value" ;;
        *) printf '%s%%' "$value" ;;
    esac
}

apply_each() {
    local command="$1"
    shift
    local monitor failed=0
    while IFS= read -r monitor; do
        [[ -n $monitor ]] || continue
        "$QUICKSHELL_SCRIPT" "$command" "$monitor" "$@" >/dev/null 2>&1 || failed=1
    done < <(resolve_targets)
    refresh_bar_state
    return "$failed"
}

option_menu() {
    local title="$1" current="$2" values_name="$3" labels_name="$4"
    local -n values="$values_name"
    local -n labels="$labels_name"
    local selected=0 key i count cols lines row clicked
    count=${#values[@]}
    OPTION_VALUE=""

    for i in "${!values[@]}"; do
        if [[ ${values[$i]} == "$current" ]]; then
            selected=$i
            break
        fi
    done

    while true; do
        cols="$(term_cols)"
        lines="$(term_lines)"
        printf '\033[2J\033[H\033[?25l'
        printf '%s\n' "$TITLE"
        printf '%s\n\n' "$title"
        row=4
        for i in "${!values[@]}"; do
            ui_goto "$row" 3
            ui_clear_line
            if (( i == selected )); then
                printf '\033[7m> %-*.*s\033[0m' "$((cols - 5))" "$((cols - 5))" "${labels[$i]}"
            else
                printf '  %s' "${labels[$i]}"
            fi
            ((row++)) || true
        done
        ui_goto "$lines" 1
        ui_clear_line
        printf 'Up/Down or wheel: move   Enter/click: select   Esc/q: back'

        key="$(read_key)" || return 1
        case "$key" in
            q|Q|$'\e') return 1 ;;
            $'\e[A'|k) ((selected--)) || true; (( selected < 0 )) && selected=$((count - 1)) ;;
            $'\e[B'|j) ((selected++)) || true; (( selected >= count )) && selected=0 ;;
            __ENTER__|' ') OPTION_VALUE="${values[$selected]}"; return 0 ;;
            $'\e[<'*)
                if parse_mouse_event "$key" && (( MOUSE_RELEASE == 0 )); then
                    case "$MOUSE_BUTTON" in
                        64) ((selected--)) || true; (( selected < 0 )) && selected=$((count - 1)) ;;
                        65) ((selected++)) || true; (( selected >= count )) && selected=0 ;;
                        *)
                            if (( (MOUSE_BUTTON & 3) == 0 && MOUSE_Y >= 4 && MOUSE_Y < 4 + count )); then
                                clicked=$((MOUSE_Y - 4))
                                OPTION_VALUE="${values[$clicked]}"
                                return 0
                            fi
                            ;;
                    esac
                fi
                ;;
        esac
    done
}

prompt_number() {
    local title="$1" min="$2" max="$3" suffix="$4" input="" key
    mouse_disable
    printf '\033[2J\033[H\033[?25h'
    printf '%s\n\n' "$TITLE"
    printf '%s\n' "$title"
    printf 'Allowed: %s-%s%s   Enter blank to cancel   Esc: cancel\n> ' "$min" "$max" "$suffix"

    while true; do
        key="$(read_key)" || { mouse_enable; printf '\033[?25l'; return 1; }
        case "$key" in
            $'\e') mouse_enable; printf '\033[?25l'; return 1 ;;
            __ENTER__)
                mouse_enable
                printf '\033[?25l'
                [[ -n $input ]] || return 1
                if (( input < min || input > max )); then
                    MSG="value must be ${min}-${max}${suffix}"
                    return 1
                fi
                NUMBER_VALUE="$input"
                return 0
                ;;
            $'\177'|$'\b') input="${input%?}"; printf '\b \b' ;;
            [0-9]) input+="$key"; printf '%s' "$key" ;;
        esac
    done
}

confirm_reset() {
    local -a values=(yes no)
    local -a labels=("Yes - reset $(target_label)" 'No - keep current settings')
    if option_menu 'Reset bar defaults?' no values labels; then
        [[ $OPTION_VALUE == yes ]]
    else
        return 1
    fi
}

select_target() {
    local focused monitor
    local -a values=(focused all)
    local -a labels
    focused="$(focused_monitor)"
    labels=("Focused display${focused:+ ($focused)}" 'All displays')
    while IFS= read -r monitor; do
        [[ -n $monitor ]] || continue
        values+=("$monitor")
        labels+=("Display: $monitor")
    done < <(list_monitors)

    if option_menu 'Modification target' "$TARGET" values labels; then
        TARGET="$OPTION_VALUE"
        MSG="target: $(target_label)"
    fi
}

select_position() {
    local current
    local -a values=(top bottom left right)
    local -a labels=(Top Bottom Left Right)
    current="$(common_value getpos)"
    if option_menu "Bar position - $(target_label)" "$current" values labels; then
        if apply_each setpos "$OPTION_VALUE" && apply_each setenabled true; then
            MSG="position: $OPTION_VALUE"
        else
            MSG='bar position change failed'
        fi
    fi
}

select_visibility() {
    local current
    local -a values=(true false toggle)
    local -a labels=('On' 'Off' 'Toggle current state')
    current="$(common_value getenabled)"
    if option_menu "Bar visibility - $(target_label)" "$current" values labels; then
        case "$OPTION_VALUE" in
            true|false)
                apply_each setenabled "$OPTION_VALUE" && MSG="visibility: $OPTION_VALUE" || MSG='visibility change failed'
                ;;
            toggle)
                apply_each toggle-mon && MSG='visibility toggled' || MSG='visibility toggle failed'
                ;;
        esac
    fi
}

set_bar_size() {
    if prompt_number "Bar size / thickness for $(target_label)" "$MIN_BAR_SIZE" "$MAX_BAR_SIZE" 'px'; then
        apply_each setsize "$NUMBER_VALUE" && MSG="bar size: ${NUMBER_VALUE}px" || MSG='bar size change failed'
    fi
}

set_icon_scale() {
    if prompt_number "Uniform icon size for $(target_label)" "$MIN_ICON_SCALE" "$MAX_ICON_SCALE" '%'; then
        apply_each setscale "$NUMBER_VALUE" && MSG="icon size: ${NUMBER_VALUE}%" || MSG='icon size change failed'
    fi
}

reset_defaults() {
    confirm_reset || { MSG='reset cancelled'; return 0; }
    if [[ $TARGET == all ]]; then
        if "$QUICKSHELL_SCRIPT" reset-all >/dev/null 2>&1; then
            refresh_bar_state
            MSG='all display bar settings reset'
        else
            MSG='reset failed'
        fi
    else
        apply_each reset-mon && MSG="reset: $(target_label)" || MSG='reset failed'
    fi
}

draw_main() {
    local cols lines
    cols="$(term_cols)"
    lines="$(term_lines)"
    local -a rows=(
        "Target            $(target_label)"
        "Position          $(common_value getpos)"
        "Visibility        $(format_visibility)"
        "Bar size          $(format_size)"
        "Icon size         $(format_scale)"
        "Reset defaults"
        "Back"
    )
    local i row=4

    printf '\033[2J\033[H\033[?25l'
    printf '%s\n' "$TITLE"
    printf '%s\n\n' 'Settings apply only to the selected target. Position changes also show the bar.'
    for i in "${!rows[@]}"; do
        ui_goto "$row" 3
        ui_clear_line
        if (( i == SEL )); then
            printf '\033[7m> %-*.*s\033[0m' "$((cols - 5))" "$((cols - 5))" "${rows[$i]}"
        else
            printf '  %s' "${rows[$i]}"
        fi
        ((row++)) || true
    done

    if [[ -n $MSG ]]; then
        ui_goto "$((lines - 1))" 1
        ui_clear_line
        printf '%.*s' "$cols" "$MSG"
    fi
    ui_goto "$lines" 1
    ui_clear_line
    printf 'Up/Down or wheel: move   Enter/click: select   Esc/q: back'
}

activate() {
    case "$SEL" in
        0) select_target ;;
        1) select_position ;;
        2) select_visibility ;;
        3) set_bar_size ;;
        4) set_icon_scale ;;
        5) reset_defaults ;;
        6) return 1 ;;
    esac
    return 0
}

main_loop() {
    local key clicked count=7
    mouse_enable
    while true; do
        draw_main
        key="$(read_key)" || break
        MSG=""
        case "$key" in
            q|Q|$'\e') break ;;
            $'\e[A'|k) ((SEL--)) || true; (( SEL < 0 )) && SEL=$((count - 1)) ;;
            $'\e[B'|j) ((SEL++)) || true; (( SEL >= count )) && SEL=0 ;;
            __ENTER__|' ') activate || break ;;
            $'\e[<'*)
                if parse_mouse_event "$key" && (( MOUSE_RELEASE == 0 )); then
                    case "$MOUSE_BUTTON" in
                        64) ((SEL--)) || true; (( SEL < 0 )) && SEL=$((count - 1)) ;;
                        65) ((SEL++)) || true; (( SEL >= count )) && SEL=0 ;;
                        *)
                            if (( (MOUSE_BUTTON & 3) == 0 && MOUSE_Y >= 4 && MOUSE_Y < 4 + count )); then
                                clicked=$((MOUSE_Y - 4))
                                SEL=$clicked
                                activate || return 0
                            fi
                            ;;
                    esac
                fi
                ;;
        esac
    done
}

main_loop
