#!/usr/bin/env bash
# Awtarchy Quickshell bar settings TUI.

set -euo pipefail

QUICKSHELL_SCRIPT="${HYPR_QUICKSHELL_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh}"
TITLE="Awtarchy Quick Settings"
SECTION_TITLE="Bar Settings"
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
KEY_SEQUENCE_TIMEOUT=0.15

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

ui_footer() {
    local message="$1" cols width
    cols="$(term_cols)"
    width=$((cols - 1))
    (( width < 1 )) && width=1
    ui_clear_line
    printf '%-*.*s' "$width" "$width" "$message"
}

read_key() {
    local key rest
    IFS= read -rsN1 key || return 1
    case "$key" in
        $'\r'|$'\n') printf '%s' '__ENTER__'; return 0 ;;
        $'\e') ;;
        *) printf '%s' "$key"; return 0 ;;
    esac

    if ! IFS= read -rsN1 -t "$KEY_SEQUENCE_TIMEOUT" rest; then
        printf '%s' "$key"
        return 0
    fi
    key+="$rest"
    if [[ $rest == '[' ]]; then
        while IFS= read -rsN1 -t "$KEY_SEQUENCE_TIMEOUT" rest; do
            key+="$rest"
            # SGR mouse packets end only at M/m. Ordinary CSI sequences end at
            # a final byte in the @-~ range. Waiting for the real terminator
            # prevents a click or wheel packet from being split and discarded.
            if [[ $key == $'\e[<'* ]]; then
                [[ $rest == M || $rest == m ]] && break
            elif [[ $rest =~ [@-~] ]]; then
                break
            fi
        done
    elif [[ $rest == O ]]; then
        if IFS= read -rsN1 -t "$KEY_SEQUENCE_TIMEOUT" rest; then
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
    return 0
}

focused_monitor() {
    local monitor
    monitor="$({
        hyprctl monitors -j 2>/dev/null |
            jq -r '.[] | select((.disabled // false) == false and .focused == true) | .name' |
            head -n1
    } 2>/dev/null || true)"
    if [[ -z $monitor ]]; then
        monitor="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.monitor // empty' 2>/dev/null || true)"
    fi
    if [[ -z $monitor ]]; then
        monitor="$(list_monitors | head -n1)"
    fi
    if [[ -n $monitor ]]; then
        printf '%s\n' "$monitor"
    fi
    return 0
}

list_monitors() {
    hyprctl monitors -j 2>/dev/null |
        jq -r '.[] | select((.disabled // false) == false) | .name' 2>/dev/null || true
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
    local command="$1" monitor value first="" seen=0 failed=0
    while IFS= read -r monitor; do
        [[ -n $monitor ]] || continue
        if ! value="$("$QUICKSHELL_SCRIPT" "$command" "$monitor" 2>/dev/null)"; then
            failed=1
            continue
        fi

        # Never allow manager diagnostics or usage text into a rendered row.
        # Every getter has a deliberately small, single-line output contract.
        [[ $value != *$'\n'* ]] || { failed=1; continue; }
        case "$command" in
            getpos) [[ $value == top || $value == bottom || $value == left || $value == right ]] || { failed=1; continue; } ;;
            getenabled) [[ $value == true || $value == false ]] || { failed=1; continue; } ;;
            getsize)
                [[ $value =~ ^[0-9]+$ ]] || { failed=1; continue; }
                (( value == 0 || (value >= MIN_BAR_SIZE && value <= MAX_BAR_SIZE) )) || { failed=1; continue; }
                ;;
            getscale)
                [[ $value =~ ^[0-9]+$ ]] || { failed=1; continue; }
                (( value >= MIN_ICON_SCALE && value <= MAX_ICON_SCALE )) || { failed=1; continue; }
                ;;
            *) failed=1; continue ;;
        esac

        if (( seen == 0 )); then
            first="$value"
            seen=1
        elif [[ $value != "$first" ]]; then
            printf 'mixed'
            return 0
        fi
    done < <(resolve_targets)
    if (( failed == 1 || seen == 0 )); then
        printf 'unavailable'
    else
        printf '%s' "$first"
    fi
}

format_visibility() {
    case "$(common_value getenabled)" in
        true) printf 'on' ;;
        false) printf 'off' ;;
        mixed) printf 'mixed' ;;
        *) printf 'unavailable' ;;
    esac
}

format_size() {
    local value
    value="$(common_value getsize)"
    case "$value" in
        0) printf 'default (28px horizontal / 36px vertical)' ;;
        mixed|unavailable) printf '%s' "$value" ;;
        *) printf '%spx' "$value" ;;
    esac
}

format_scale() {
    local value
    value="$(common_value getscale)"
    case "$value" in
        mixed|unavailable) printf '%s' "$value" ;;
        *) printf '%s%%' "$value" ;;
    esac
}

apply_each() {
    local command="$1"
    shift
    local monitor failed=0 seen=0
    while IFS= read -r monitor; do
        [[ -n $monitor ]] || continue
        seen=1
        "$QUICKSHELL_SCRIPT" "$command" "$monitor" "$@" >/dev/null 2>&1 || failed=1
    done < <(resolve_targets)
    refresh_bar_state
    (( seen == 1 )) || failed=1
    return "$failed"
}

option_menu() {
    local title="$1" current="$2" values_name="$3" labels_name="$4"
    local -n menu_values="$values_name"
    local -n menu_labels="$labels_name"
    local selected=0 key i count cols lines width row clicked
    count=${#menu_values[@]}
    OPTION_VALUE=""

    for i in "${!menu_values[@]}"; do
        if [[ ${menu_values[$i]} == "$current" ]]; then
            selected=$i
            break
        fi
    done

    while true; do
        cols="$(term_cols)"
        lines="$(term_lines)"
        width=$((cols - 5))
        (( width < 1 )) && width=1
        printf '\033[2J\033[H\033[?25l'
        printf '%s\n' "$TITLE"
        printf '%s / %s\n\n' "$SECTION_TITLE" "$title"
        row=4
        for i in "${!menu_values[@]}"; do
            ui_goto "$row" 3
            ui_clear_line
            if (( i == selected )); then
                printf '\033[7m> %-*.*s\033[0m' "$width" "$width" "${menu_labels[$i]}"
            else
                printf '  %s' "${menu_labels[$i]}"
            fi
            ((row++)) || true
        done
        ui_goto "$lines" 1
        ui_footer 'Up/Down or wheel: move | Enter/click: select | Esc/q: back'

        key="$(read_key)" || return 1
        case "$key" in
            q|Q|$'\e') return 1 ;;
            $'\e[A'|k) ((selected--)) || true; (( selected < 0 )) && selected=$((count - 1)) ;;
            $'\e[B'|j) ((selected++)) || true; (( selected >= count )) && selected=0 ;;
            __ENTER__|' ') OPTION_VALUE="${menu_values[$selected]}"; return 0 ;;
            $'\e[<'*)
                if parse_mouse_event "$key" && (( MOUSE_RELEASE == 0 )); then
                    if (( MOUSE_BUTTON & 64 )); then
                        if (( MOUSE_BUTTON & 1 )); then
                            ((selected++)) || true
                            (( selected >= count )) && selected=0
                        else
                            ((selected--)) || true
                            (( selected < 0 )) && selected=$((count - 1))
                        fi
                    elif (( (MOUSE_BUTTON & 3) == 0 && MOUSE_Y >= 4 && MOUSE_Y < 4 + count )); then
                        clicked=$((MOUSE_Y - 4))
                        OPTION_VALUE="${menu_values[$clicked]}"
                        return 0
                    fi
                fi
                ;;
        esac
    done
}

prompt_number() {
    local title="$1" min="$2" max="$3" suffix="$4" zero_label="${5:-}" input="" key
    mouse_disable
    printf '\033[2J\033[H\033[?25h'
    printf '%s\n' "$TITLE"
    printf '%s / %s\n\n' "$SECTION_TITLE" "$title"
    printf 'Target: %s\n' "$(target_label)"
    if [[ -n $zero_label ]]; then
        printf 'Enter %s-%s%s, or 0 for %s.\n' "$min" "$max" "$suffix" "$zero_label"
    else
        printf 'Enter %s-%s%s.\n' "$min" "$max" "$suffix"
    fi
    printf 'Enter blank or press Esc to cancel.\n\n> '

    while true; do
        key="$(read_key)" || { mouse_enable; printf '\033[?25l'; return 1; }
        case "$key" in
            $'\e') mouse_enable; printf '\033[?25l'; return 1 ;;
            __ENTER__)
                mouse_enable
                printf '\033[?25l'
                [[ -n $input ]] || return 1
                if [[ $input == 0 && -n $zero_label ]]; then
                    NUMBER_VALUE=0
                    return 0
                fi
                if (( input < min || input > max )); then
                    if [[ -n $zero_label ]]; then
                        MSG="value must be 0 or ${min}-${max}${suffix}"
                    else
                        MSG="value must be ${min}-${max}${suffix}"
                    fi
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
    local -a values=(true false)
    local -a labels=('On' 'Off')
    current="$(common_value getenabled)"
    if option_menu "Bar visibility - $(target_label)" "$current" values labels; then
        apply_each setenabled "$OPTION_VALUE" && MSG="visibility: $OPTION_VALUE" || MSG='visibility change failed'
    fi
}

set_bar_size() {
    if prompt_number 'Bar thickness' "$MIN_BAR_SIZE" "$MAX_BAR_SIZE" 'px' 'automatic 28px horizontal / 36px vertical'; then
        if [[ $NUMBER_VALUE == 0 ]]; then
            apply_each setsize 0 && MSG='bar thickness: automatic defaults' || MSG='bar thickness change failed'
        else
            apply_each setsize "$NUMBER_VALUE" && MSG="bar thickness: ${NUMBER_VALUE}px" || MSG='bar thickness change failed'
        fi
    fi
}

set_icon_scale() {
    if prompt_number 'Uniform icon size' "$MIN_ICON_SCALE" "$MAX_ICON_SCALE" '%'; then
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
    local cols lines width
    cols="$(term_cols)"
    lines="$(term_lines)"
    width=$((cols - 5))
    (( width < 1 )) && width=1
    local -a rows=(
        "Target         $(target_label)"
        "Position       $(common_value getpos)"
        "Visibility     $(format_visibility)"
        "Thickness      $(format_size)"
        "Icon size      $(format_scale)"
        "$([[ $TARGET == all ]] && printf 'Reset all displays' || printf 'Reset selected target')"
        "Back to Quick Settings"
    )
    local i row=4

    printf '\033[2J\033[H\033[?25l'
    printf '%s\n' "$TITLE"
    printf '%s\n\n' "$SECTION_TITLE"
    for i in "${!rows[@]}"; do
        ui_goto "$row" 3
        ui_clear_line
        if (( i == SEL )); then
            printf '\033[7m> %-*.*s\033[0m' "$width" "$width" "${rows[$i]}"
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
    ui_footer 'Up/Down or wheel: move | Enter/click: select | Esc/q: back'
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
                    if (( MOUSE_BUTTON & 64 )); then
                        if (( MOUSE_BUTTON & 1 )); then
                            ((SEL++)) || true
                            (( SEL >= count )) && SEL=0
                        else
                            ((SEL--)) || true
                            (( SEL < 0 )) && SEL=$((count - 1))
                        fi
                    elif (( (MOUSE_BUTTON & 3) == 0 && MOUSE_Y >= 4 && MOUSE_Y < 4 + count )); then
                        clicked=$((MOUSE_Y - 4))
                        SEL=$clicked
                        activate || return 0
                    fi
                fi
                ;;
        esac
    done
}

main_loop
