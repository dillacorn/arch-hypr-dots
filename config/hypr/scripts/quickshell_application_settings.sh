#!/usr/bin/env bash
# Awtarchy Quickshell application view settings TUI.

set -euo pipefail

QUICKSHELL_SCRIPT="${HYPR_QUICKSHELL_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
TITLE="Awtarchy Application View"
EMBEDDED=0
TARGET="global"
SEL=0
MSG=""
MOUSE_BUTTON=0
MOUSE_X=0
MOUSE_Y=0
MOUSE_RELEASE=0

DEFAULT_WIDTH=520
DEFAULT_HEIGHT=604
DEFAULT_TEXT_SIZE=14
DEFAULT_ICON_SIZE=18
MIN_WIDTH=420
MAX_WIDTH=3840
MIN_HEIGHT=360
MAX_HEIGHT=2160
MIN_TEXT_SIZE=10
MAX_TEXT_SIZE=28
MIN_ICON_SIZE=12
MAX_ICON_SIZE=48

[[ ${1:-} == --embedded ]] && EMBEDDED=1

[[ -x "$QUICKSHELL_SCRIPT" ]] || {
    printf 'application view settings: missing %s\n' "$QUICKSHELL_SCRIPT" >&2
    exit 1
}
command -v hyprctl >/dev/null 2>&1 || exit 127
command -v jq >/dev/null 2>&1 || exit 127
command -v qs >/dev/null 2>&1 || exit 127

mouse_enable() { printf '\033[?1000h\033[?1006h'; }
mouse_disable() { printf '\033[?1000l\033[?1006l'; }
term_cols() { tput cols 2>/dev/null || printf '80'; }
term_lines() { tput lines 2>/dev/null || printf '24'; }
ui_goto() { printf '\033[%s;%sH' "$1" "$2"; }
ui_clear_line() { printf '\033[2K'; }

close_preview() {
    qs -c awtarchy ipc call launcher close >/dev/null 2>&1 || true
}

cleanup() {
    close_preview
    if (( EMBEDDED == 1 )); then
        mouse_enable
        printf '\033[?25l\033[0m'
    else
        mouse_disable
        printf '\033[?25h\033[0m\n'
    fi
}
trap cleanup EXIT INT TERM

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

ensure_state() {
    local tmp
    "$QUICKSHELL_SCRIPT" dump-state >/dev/null 2>&1
    mkdir -p "$(dirname "$STATE_FILE")"
    tmp="${STATE_FILE}.tmp.$$"
    jq '
        .monitors = (.monitors // {})
        | .application_view = ({width:520,height:604,text_size:14,icon_size:18} * (.application_view // {}))
    ' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

focused_monitor() {
    "$QUICKSHELL_SCRIPT" focused-monitor 2>/dev/null || true
}

list_monitors() {
    "$QUICKSHELL_SCRIPT" list-monitors 2>/dev/null || true
}

monitor_modified() {
    local monitor="$1"
    ensure_state
    jq -e --arg monitor "$monitor" '((.monitors[$monitor].application_view // {}) | length) > 0' "$STATE_FILE" >/dev/null 2>&1
}

target_label() {
    if [[ $TARGET == global ]]; then
        printf 'All displays (global default)'
    elif monitor_modified "$TARGET"; then
        printf '%s *' "$TARGET"
    else
        printf '%s' "$TARGET"
    fi
}

effective_field() {
    local field="$1"
    ensure_state
    if [[ $TARGET == global ]]; then
        jq -r --arg field "$field" '.application_view[$field]' "$STATE_FILE"
    else
        jq -r --arg monitor "$TARGET" --arg field "$field" \
            '.monitors[$monitor].application_view[$field] // .application_view[$field]' "$STATE_FILE"
    fi
}

write_global_field() {
    local field="$1" value="$2" tmp
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    jq --arg field "$field" --argjson value "$value" \
        '.application_view[$field] = $value' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

write_monitor_field() {
    local monitor="$1" field="$2" value="$3" tmp
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    jq --arg monitor "$monitor" --arg field "$field" --argjson value "$value" '
        .monitors[$monitor] = (.monitors[$monitor] // {})
        | if $value == .application_view[$field] then
            .monitors[$monitor].application_view = ((.monitors[$monitor].application_view // {}) | del(.[$field]))
          else
            .monitors[$monitor].application_view = ((.monitors[$monitor].application_view // {}) + {($field): $value})
          end
        | if ((.monitors[$monitor].application_view // {}) | length) == 0 then
            del(.monitors[$monitor].application_view)
          else . end
    ' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

write_field() {
    local field="$1" value="$2"
    if [[ $TARGET == global ]]; then
        write_global_field "$field" "$value"
    else
        write_monitor_field "$TARGET" "$field" "$value"
    fi
}

reset_target() {
    local tmp
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    if [[ $TARGET == global ]]; then
        jq '
            .application_view = {width:520,height:604,text_size:14,icon_size:18}
            | .monitors |= with_entries(.value |= del(.application_view))
        ' "$STATE_FILE" >"$tmp"
    else
        jq --arg monitor "$TARGET" 'del(.monitors[$monitor].application_view)' "$STATE_FILE" >"$tmp"
    fi
    mv -f "$tmp" "$STATE_FILE"
}

preview_target() {
    local monitor global_only=false
    "$QUICKSHELL_SCRIPT" start >/dev/null 2>&1 || return 1
    if [[ $TARGET == global ]]; then
        monitor="$(focused_monitor)"
        global_only=true
    else
        monitor="$TARGET"
    fi
    [[ -n $monitor ]] || return 1
    qs -c awtarchy ipc call launcher previewMonitor "$monitor" "$global_only" >/dev/null 2>&1
}

apply_preview_size() {
    qs -c awtarchy ipc call launcher applyConfiguredSize >/dev/null 2>&1 || true
}

current_preview_size() {
    local width height
    width="$(qs -c awtarchy ipc call launcher currentWidth 2>/dev/null || true)"
    height="$(qs -c awtarchy ipc call launcher currentHeight 2>/dev/null || true)"
    [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]] || return 1
    printf '%s %s\n' "$width" "$height"
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
    local title="$1" min="$2" max="$3" suffix="$4" current="$5" input="" key
    mouse_disable
    printf '\033[2J\033[H\033[?25h'
    printf '%s\n\n' "$TITLE"
    printf '%s\n' "$title"
    printf 'Current: %s%s   Allowed: %s-%s%s   Enter blank to cancel   Esc: cancel\n> ' \
        "$current" "$suffix" "$min" "$max" "$suffix"

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

select_target() {
    local monitor label
    local -a values=(global)
    local -a labels=('All displays (global default)')
    while IFS= read -r monitor; do
        [[ -n $monitor ]] || continue
        label="Display: $monitor"
        monitor_modified "$monitor" && label+=' * modified'
        values+=("$monitor")
        labels+=("$label")
    done < <(list_monitors)

    if option_menu 'Application View modification target' "$TARGET" values labels; then
        TARGET="$OPTION_VALUE"
        preview_target || true
        MSG="target: $(target_label)"
    fi
}

set_numeric_field() {
    local field="$1" title="$2" min="$3" max="$4" suffix="$5" current
    current="$(effective_field "$field")"
    if prompt_number "$title for $(target_label)" "$min" "$max" "$suffix" "$current"; then
        write_field "$field" "$NUMBER_VALUE"
        case "$field" in width|height) apply_preview_size ;; esac
        MSG="$title: ${NUMBER_VALUE}${suffix}"
    fi
}

save_current_size() {
    local width height
    if read -r width height < <(current_preview_size); then
        (( width < MIN_WIDTH )) && width=$MIN_WIDTH
        (( width > MAX_WIDTH )) && width=$MAX_WIDTH
        (( height < MIN_HEIGHT )) && height=$MIN_HEIGHT
        (( height > MAX_HEIGHT )) && height=$MAX_HEIGHT
        write_field width "$width"
        write_field height "$height"
        MSG="saved launcher size: ${width}x${height}"
    else
        MSG='could not read launcher preview size'
    fi
}

confirm_reset() {
    local -a values=(yes no)
    local -a labels=("Yes - reset $(target_label)" 'No - keep current settings')
    if option_menu 'Reset Application View defaults?' no values labels; then
        [[ $OPTION_VALUE == yes ]]
    else
        return 1
    fi
}

reset_defaults() {
    confirm_reset || { MSG='reset cancelled'; return 0; }
    reset_target
    preview_target || true
    apply_preview_size
    if [[ $TARGET == global ]]; then
        MSG='Application View reset globally; display overrides cleared'
    else
        MSG="Application View override cleared: $TARGET"
    fi
}

draw_main() {
    local cols lines width height text_size icon_size target
    cols="$(term_cols)"
    lines="$(term_lines)"
    width="$(effective_field width)"
    height="$(effective_field height)"
    text_size="$(effective_field text_size)"
    icon_size="$(effective_field icon_size)"
    target="$(target_label)"
    local -a rows=(
        "Target                 $target"
        "Window width           ${width}px"
        "Window height          ${height}px"
        "Application text       ${text_size}px"
        "Application icons      ${icon_size}px"
        "Save current window size"
        "Reset defaults"
        "Back"
    )
    local i row=5

    printf '\033[2J\033[H\033[?25l'
    printf '%s\n' "$TITLE"
    printf '%s\n' 'Launcher preview is open. ALT + right-drag the launcher to resize it.'
    printf '%s\n\n' 'Text/icon edits save immediately. Use Save current window size after dragging.'
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
    printf 'Up/Down or wheel: move   Enter/click: select   Esc/q: back   * modified display'
}

activate() {
    case "$SEL" in
        0) select_target ;;
        1) set_numeric_field width 'Window width' "$MIN_WIDTH" "$MAX_WIDTH" 'px' ;;
        2) set_numeric_field height 'Window height' "$MIN_HEIGHT" "$MAX_HEIGHT" 'px' ;;
        3) set_numeric_field text_size 'Application text' "$MIN_TEXT_SIZE" "$MAX_TEXT_SIZE" 'px' ;;
        4) set_numeric_field icon_size 'Application icons' "$MIN_ICON_SIZE" "$MAX_ICON_SIZE" 'px' ;;
        5) save_current_size ;;
        6) reset_defaults ;;
        7) return 1 ;;
    esac
    return 0
}

main_loop() {
    local key clicked count=8
    ensure_state
    "$QUICKSHELL_SCRIPT" start >/dev/null 2>&1 || true
    preview_target || true
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
                            if (( (MOUSE_BUTTON & 3) == 0 && MOUSE_Y >= 5 && MOUSE_Y < 5 + count )); then
                                clicked=$((MOUSE_Y - 5))
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
