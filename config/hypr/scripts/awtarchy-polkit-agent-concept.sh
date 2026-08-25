#!/usr/bin/env bash
# Awtarchy PolicyKit terminal UI concept.
# Visual layout prototype only; the real authentication implementation is separate.

set -u
set -o pipefail
IFS=$'\n\t'
export LC_ALL=C.UTF-8

APP_ID="awtarchy-polkit-agent-concept"
SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" 2>/dev/null && pwd -P)"

WINDOW_WIDTH=900
WINDOW_HEIGHT=520
WINDOW_SIZE_TOLERANCE=4
GEOMETRY_WATCH_INTERVAL=0.75
HYPRCTL_BIN="${HYPRCTL_BIN:-hyprctl}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_ACCENT=$'\033[1;35m'
C_GREEN=$'\033[1;32m'
C_RED=$'\033[1;31m'
C_YELLOW=$'\033[1;33m'
C_REVERSE=$'\033[7m'

TTY_STATE=""
UI_ACTIVE=0
FOCUS=0
SHOW_DETAILS=0
PASSWORD_LENGTH=0
STATUS_MSG=""
GEOMETRY_WATCH_PID=""
WINDOW_RESIZED=0

PASSWORD_ROW=0
DETAILS_ROW=0
BUTTON_ROW=0
CANCEL_X1=0
CANCEL_X2=0
AUTH_X1=0
AUTH_X2=0
MOUSE_BUTTON=-1
MOUSE_X=0
MOUSE_Y=0
MOUSE_RELEASE=0

usage() {
    printf '%s\n' \
        'Usage: awtarchy-polkit-agent-concept.sh [--tui|--print]' \
        '' \
        'Without arguments, opens the concept in the preferred terminal.' \
        '--tui    Internal/current-terminal mode used by the spawned review window.' \
        '--print  Print a static noninteractive preview.' \
        '' \
        "Hyprland review geometry: ${WINDOW_WIDTH}x${WINDOW_HEIGHT}, floating and centered."
}

stop_geometry_watch() {
    if [[ ${GEOMETRY_WATCH_PID:-} =~ ^[1-9][0-9]*$ ]]; then
        kill -TERM -- "$GEOMETRY_WATCH_PID" 2>/dev/null || true
        wait "$GEOMETRY_WATCH_PID" 2>/dev/null || true
    fi
    GEOMETRY_WATCH_PID=""
}

cleanup_terminal() {
    stop_geometry_watch

    if (( UI_ACTIVE == 0 )); then
        return 0
    fi

    if [[ -n $TTY_STATE ]]; then
        stty "$TTY_STATE" <&3 2>/dev/null || true
    fi
    printf '\033[?1000l\033[?1006l\033[?25h\033[0m\033[?1049l' >&3 2>/dev/null || true
    UI_ACTIVE=0
}

open_tty() {
    exec 3<>/dev/tty || {
        printf '%s\n' 'awtarchy-polkit-agent-concept: /dev/tty is unavailable' >&2
        return 1
    }

    TTY_STATE="$(stty -g <&3 2>/dev/null || true)"
    [[ -n $TTY_STATE ]] || {
        printf '%s\n' 'awtarchy-polkit-agent-concept: could not read terminal state' >&2
        return 1
    }
}

ui_enter() {
    printf '\033[?1049h\033[2J\033[H\033[?1000h\033[?1006h\033[?25l' >&3
    stty -echo -icanon min 1 time 0 <&3
    UI_ACTIVE=1
}

hyprland_geometry_available() {
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 1
    command -v -- "$HYPRCTL_BIN" >/dev/null 2>&1 || return 1
    command -v -- "$PYTHON_BIN" >/dev/null 2>&1 || return 1
}

query_concept_window_state() {
    local clients_json

    hyprland_geometry_available || return 1
    clients_json="$("$HYPRCTL_BIN" -j clients 2>/dev/null)" || return 1
    [[ -n $clients_json ]] || return 1

    "$PYTHON_BIN" - "$APP_ID" "$clients_json" <<'PY'
import json
import sys

app_id = sys.argv[1]
try:
    clients = json.loads(sys.argv[2])
except (IndexError, json.JSONDecodeError):
    raise SystemExit(1)

if not isinstance(clients, list):
    raise SystemExit(1)

matches = []
for client in clients:
    if not isinstance(client, dict) or not client.get("mapped", True):
        continue

    identity_fields = (
        client.get("class"),
        client.get("initialClass"),
        client.get("title"),
        client.get("initialTitle"),
    )
    if app_id not in identity_fields:
        continue

    address = str(client.get("address") or "")
    size = client.get("size")
    at = client.get("at")
    if not address.startswith("0x") or not isinstance(size, list) or len(size) != 2:
        continue
    if not all(isinstance(value, (int, float)) for value in size):
        continue
    if not isinstance(at, list) or len(at) != 2 or not all(isinstance(value, (int, float)) for value in at):
        at = [0, 0]

    matches.append((
        int(client.get("focusHistoryID", 999999)),
        address,
        bool(client.get("floating", False)),
        int(size[0]),
        int(size[1]),
        int(at[0]),
        int(at[1]),
        bool(client.get("visible", True)),
    ))

if not matches:
    raise SystemExit(1)

matches.sort(key=lambda item: item[0])
_, address, floating, width, height, x, y, visible = matches[0]
print(f"{address}\t{str(floating).lower()}\t{width}\t{height}\t{x}\t{y}\t{str(visible).lower()}")
PY
}

window_size_is_correct() {
    local width="$1" height="$2" dw dh
    [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]] || return 1

    dw=$((width - WINDOW_WIDTH))
    dh=$((height - WINDOW_HEIGHT))
    (( dw < 0 )) && dw=$((-dw))
    (( dh < 0 )) && dh=$((-dh))

    (( dw <= WINDOW_SIZE_TOLERANCE && dh <= WINDOW_SIZE_TOLERANCE ))
}

enforce_window_geometry() {
    local address="$1" lua
    [[ $address =~ ^0x[0-9A-Fa-f]+$ ]] || return 1

    printf -v lua \
        'local w="address:%s"; hl.dispatch(hl.dsp.window.float({ action = "set", window = w })); hl.dispatch(hl.dsp.window.resize({ x = %d, y = %d, relative = false, window = w })); hl.dispatch(hl.dsp.window.center({ window = w }))' \
        "$address" "$WINDOW_WIDTH" "$WINDOW_HEIGHT"

    "$HYPRCTL_BIN" eval "$lua" >/dev/null 2>&1
}

correct_window_geometry_if_needed() {
    local state address floating width height x y visible

    state="$(query_concept_window_state)" || return 1
    IFS=$'\t' read -r address floating width height x y visible <<<"$state"

    if [[ $floating != true ]] || ! window_size_is_correct "$width" "$height"; then
        enforce_window_geometry "$address" || return 1
        return 0
    fi

    return 2
}

prepare_review_geometry() {
    local attempt state address floating width height x y visible

    hyprland_geometry_available || return 0

    for attempt in {1..60}; do
        if state="$(query_concept_window_state 2>/dev/null)"; then
            IFS=$'\t' read -r address floating width height x y visible <<<"$state"
            if enforce_window_geometry "$address"; then
                sleep 0.08
                return 0
            fi
        fi
        sleep 0.05
    done

    return 1
}

geometry_watch_loop() {
    local appeared=0 misses=0 rc=0

    hyprland_geometry_available || return 0

    while true; do
        correct_window_geometry_if_needed
        rc=$?
        case "$rc" in
            0|2)
                appeared=1
                misses=0
                ;;
            *)
                if (( appeared == 1 )); then
                    ((misses++))
                    (( misses >= 4 )) && return 0
                fi
                ;;
        esac
        sleep "$GEOMETRY_WATCH_INTERVAL"
    done
}

start_geometry_watch() {
    hyprland_geometry_available || return 0
    geometry_watch_loop &
    GEOMETRY_WATCH_PID=$!
}

term_cols() {
    local cols
    cols="$(tput cols 2>/dev/null || printf '80')"
    [[ $cols =~ ^[0-9]+$ ]] || cols=80
    printf '%s\n' "$cols"
}

term_lines() {
    local lines
    lines="$(tput lines 2>/dev/null || printf '24')"
    [[ $lines =~ ^[0-9]+$ ]] || lines=24
    printf '%s\n' "$lines"
}

goto_xy() {
    printf '\033[%d;%dH' "$1" "$2" >&3
}

print_at() {
    local row="$1" col="$2"
    shift 2
    goto_xy "$row" "$col"
    printf '%s' "$*" >&3
}

repeat_char() {
    local char="$1" count="$2" out=""
    (( count < 0 )) && count=0
    printf -v out '%*s' "$count" ''
    printf '%s' "${out// /$char}"
}

focus_wrap() {
    local selected="$1" text="$2" color="${3:-}"
    if (( FOCUS == selected )); then
        printf '%s%s%s%s' "$C_REVERSE" "$color" "$text" "$C_RESET"
    else
        printf '%s%s%s' "$color" "$text" "$C_RESET"
    fi
}

password_field_text() {
    local cols="$1" stars="" field_width=40 visible_count pad content
    (( cols < 72 )) && field_width=28
    (( cols > 100 )) && field_width=46

    visible_count=$PASSWORD_LENGTH
    (( visible_count > field_width )) && visible_count=$field_width
    (( visible_count > 0 )) && stars="$(repeat_char '•' "$visible_count")"
    pad=$((field_width - visible_count))
    content="${stars}$(repeat_char ' ' "$pad")"

    if (( FOCUS == 0 )); then
        printf '%s[%s]%s' "$C_REVERSE" "$content" "$C_RESET"
    else
        printf '[%s]' "$content"
    fi
}

render_password_field_only() {
    local cols field left=3
    (( PASSWORD_ROW > 0 )) || return 0
    cols="$(term_cols)"
    field="$(password_field_text "$cols")"
    print_at "$PASSWORD_ROW" "$left" "Password:  ${field}"
}

render() {
    local cols lines left=3 row=2 field button_gap=6 total button_start
    local cancel='[ Cancel ]' auth='[ Authenticate ]'

    cols="$(term_cols)"
    lines="$(term_lines)"
    printf '\033[H\033[2J' >&3

    if (( cols < 64 || lines < 20 )); then
        print_at 2 2 "${C_YELLOW}${C_BOLD}Review window is below the minimum terminal cell size.${C_RESET}"
        print_at 4 2 "The geometry watcher will restore ${WINDOW_WIDTH}x${WINDOW_HEIGHT}."
        print_at 6 2 'Reduce terminal font size if the fixed review window cannot fit the layout.'
        print_at 8 2 'Esc closes the prototype.'
        return 0
    fi

    print_at "$row" "$left" "${C_ACCENT}${C_BOLD}Authentication Required${C_RESET}"
    ((row += 2))
    print_at "$row" "$left" 'An application is attempting to perform an action that requires privileges.'
    ((row++))
    print_at "$row" "$left" "Authentication is needed to run '/usr/bin/true' as the super user."
    ((row += 2))

    PASSWORD_ROW=$row
    field="$(password_field_text "$cols")"
    print_at "$row" "$left" "Password:  ${field}"
    ((row += 2))

    DETAILS_ROW=$row
    if (( SHOW_DETAILS == 1 )); then
        print_at "$row" "$left" "$(focus_wrap 1 '▼ Details:' "$C_ACCENT")"
        ((row++))
        print_at "$row" "$((left + 2))" "${C_DIM}Action:${C_RESET}      org.freedesktop.policykit.exec"
        ((row++))
        print_at "$row" "$((left + 2))" "${C_DIM}Vendor:${C_RESET}      The polkit project"
        ((row++))
        print_at "$row" "$((left + 2))" "${C_DIM}Description:${C_RESET} Run programs as another user"
        ((row++))
        print_at "$row" "$((left + 2))" "${C_DIM}Identity:${C_RESET}    unix-user:${USER:-user}"
        ((row += 2))
    else
        print_at "$row" "$left" "$(focus_wrap 1 '▶ Details:' "$C_ACCENT")"
        ((row += 2))
    fi

    total=$(( ${#cancel} + button_gap + ${#auth} ))
    button_start=$(( (cols - total) / 2 + 1 ))
    (( button_start < left )) && button_start=$left
    BUTTON_ROW=$row
    CANCEL_X1=$button_start
    CANCEL_X2=$((CANCEL_X1 + ${#cancel} - 1))
    AUTH_X1=$((CANCEL_X2 + button_gap + 1))
    AUTH_X2=$((AUTH_X1 + ${#auth} - 1))

    print_at "$row" "$CANCEL_X1" "$(focus_wrap 2 "$cancel" "$C_RED")"
    print_at "$row" "$AUTH_X1" "$(focus_wrap 3 "$auth" "$C_GREEN")"
    ((row += 2))

    if [[ -n $STATUS_MSG ]]; then
        print_at "$row" "$left" "${C_YELLOW}${STATUS_MSG}${C_RESET}"
    fi
    ((row += 2))
    print_at "$row" "$left" "${C_DIM}Tab/Shift+Tab: move   Enter: activate   Mouse: click   Esc: cancel${C_RESET}"
}

# Keep this reader identical to awtarchy-tips-tui.sh. It is already exercised
# by Awtarchy's mouse-capable terminal UI and preserves standard SGR events.
read_key() {
    local key="" next=""

    IFS= read -rsn1 key <&3 || return 1
    if [[ "$key" != $'\033' ]]; then
        printf '%s' "$key"
        return 0
    fi

    if ! IFS= read -rsn1 -t 0.04 next <&3; then
        printf '%s' "$key"
        return 0
    fi
    key+="$next"

    if [[ "$next" == "[" ]]; then
        if IFS= read -rsn1 -t 0.04 next <&3; then
            key+="$next"
            if [[ "$next" == "<" ]]; then
                while IFS= read -rsn1 -t 0.04 next <&3; do
                    key+="$next"
                    [[ "$next" == "M" || "$next" == "m" ]] && break
                done
            elif [[ "$next" =~ [0-9] ]]; then
                while IFS= read -rsn1 -t 0.04 next <&3; do
                    key+="$next"
                    [[ "$next" == "~" || "$next" =~ [A-Za-z] ]] && break
                done
            fi
        fi
    fi

    printf '%s' "$key"
}

parse_mouse_event() {
    local event="$1" body suffix
    MOUSE_BUTTON=-1
    MOUSE_X=0
    MOUSE_Y=0
    MOUSE_RELEASE=0

    [[ "$event" == $'\033[<'* ]] || return 1
    suffix="${event: -1}"
    [[ "$suffix" == "M" || "$suffix" == "m" ]] || return 1
    body="${event#$'\033[<'}"
    body="${body%?}"
    IFS=';' read -r MOUSE_BUTTON MOUSE_X MOUSE_Y <<<"$body"
    [[ "$MOUSE_BUTTON" =~ ^[0-9]+$ && "$MOUSE_X" =~ ^[0-9]+$ && "$MOUSE_Y" =~ ^[0-9]+$ ]] || return 1
    [[ "$suffix" == "m" ]] && MOUSE_RELEASE=1
    return 0
}

simulate_authentication() {
    if (( PASSWORD_LENGTH == 0 )); then
        STATUS_MSG='Password not entered.'
        FOCUS=0
        render
        return 0
    fi

    STATUS_MSG='Authenticating…'
    render
    sleep 0.35
    PASSWORD_LENGTH=0
    STATUS_MSG='Incorrect password.'
    FOCUS=0
    render
}

handle_parsed_mouse_event() {
    local button

    (( MOUSE_RELEASE == 1 )) && return 0

    button=$(( MOUSE_BUTTON & 3 ))
    (( button == 0 )) || return 0

    if (( MOUSE_Y == PASSWORD_ROW )); then
        FOCUS=0
        render
        return 0
    fi

    if (( MOUSE_Y == DETAILS_ROW )); then
        FOCUS=1
        SHOW_DETAILS=$((1 - SHOW_DETAILS))
        render
        return 0
    fi

    if (( MOUSE_Y == BUTTON_ROW && MOUSE_X >= CANCEL_X1 && MOUSE_X <= CANCEL_X2 )); then
        FOCUS=2
        return 2
    fi

    if (( MOUSE_Y == BUTTON_ROW && MOUSE_X >= AUTH_X1 && MOUSE_X <= AUTH_X2 )); then
        FOCUS=3
        simulate_authentication
        return 0
    fi

    return 0
}

run_tui() {
    local key="" mouse_status=0

    open_tty || return 1
    prepare_review_geometry || true
    ui_enter
    start_geometry_watch
    trap cleanup_terminal EXIT
    trap 'WINDOW_RESIZED=1' WINCH

    render

    while true; do
        WINDOW_RESIZED=0
        key="$(read_key || true)"

        if parse_mouse_event "$key"; then
            if handle_parsed_mouse_event; then
                continue
            else
                mouse_status=$?
                (( mouse_status == 2 )) && break
                continue
            fi
        fi

        case "$key" in
            $'\033')
                break
                ;;
            $'\t')
                FOCUS=$(( (FOCUS + 1) % 4 ))
                render
                ;;
            $'\033[Z'|$'\033[D')
                FOCUS=$(( (FOCUS + 3) % 4 ))
                render
                ;;
            $'\033[C')
                FOCUS=$(( (FOCUS + 1) % 4 ))
                render
                ;;
            $'\177'|$'\b')
                if (( FOCUS == 0 && PASSWORD_LENGTH > 0 )); then
                    ((PASSWORD_LENGTH--))
                    STATUS_MSG=""
                    render_password_field_only
                fi
                ;;
            ""|$'\r'|$'\n')
                case "$FOCUS" in
                    0)
                        simulate_authentication
                        ;;
                    1)
                        SHOW_DETAILS=$((1 - SHOW_DETAILS))
                        render
                        ;;
                    2)
                        break
                        ;;
                    3)
                        simulate_authentication
                        ;;
                esac
                ;;
            *)
                if (( FOCUS == 0 )) && [[ ${#key} -eq 1 ]]; then
                    ((PASSWORD_LENGTH++))
                    STATUS_MSG=""
                    render_password_field_only
                fi
                ;;
        esac

        if (( WINDOW_RESIZED == 1 )); then
            render
        fi
    done

    trap - WINCH
    cleanup_terminal
    trap - EXIT
}

print_static() {
    printf '%sAuthentication Required%s\n\n' "$C_ACCENT" "$C_RESET"
    printf '%s\n' \
        'An application is attempting to perform an action that requires privileges.' \
        "Authentication is needed to run '/usr/bin/true' as the super user." \
        '' \
        'Password:  [                                      ]' \
        ''
    printf '%s▶ Details:%s\n\n' "$C_ACCENT" "$C_RESET"
    printf '              %s[ Cancel ]%s      %s[ Authenticate ]%s\n\n' "$C_RED" "$C_RESET" "$C_GREEN" "$C_RESET"
    printf '%s\n' 'Tab/Shift+Tab: move   Enter: activate   Mouse: click   Esc: cancel'
}

launch_with_terminal() {
    local helper="${SCRIPT_DIR}/default_terminal.sh" terminal_name=""
    local -a terminal_args=()

    if [[ -x $helper ]]; then
        "$helper" --class "$APP_ID" -- "$SCRIPT_PATH" --tui >/dev/null 2>&1 &
        return 0
    fi

    if [[ -n ${TERMINAL:-} ]]; then
        read -r -a terminal_args <<<"$TERMINAL"
        if (( ${#terminal_args[@]} == 0 )) || ! command -v "${terminal_args[0]}" >/dev/null 2>&1; then
            terminal_args=()
        fi
    fi

    if (( ${#terminal_args[@]} == 0 )); then
        local candidate
        for candidate in footclient foot kitty alacritty wezterm konsole gnome-terminal xfce4-terminal xterm; do
            if command -v "$candidate" >/dev/null 2>&1; then
                terminal_args=("$candidate")
                break
            fi
        done
    fi

    (( ${#terminal_args[@]} > 0 )) || {
        printf '%s\n' 'awtarchy-polkit-agent-concept: no supported terminal emulator was found' >&2
        return 127
    }

    terminal_name="${terminal_args[0]##*/}"
    case "$terminal_name" in
        foot|footclient)
            "${terminal_args[@]}" --app-id="$APP_ID" "$SCRIPT_PATH" --tui >/dev/null 2>&1 &
            ;;
        kitty)
            "${terminal_args[@]}" --class "$APP_ID" "$SCRIPT_PATH" --tui >/dev/null 2>&1 &
            ;;
        alacritty)
            "${terminal_args[@]}" --class "$APP_ID,$APP_ID" --title "$APP_ID" -e "$SCRIPT_PATH" --tui >/dev/null 2>&1 &
            ;;
        wezterm)
            "${terminal_args[@]}" start --class "$APP_ID" -- "$SCRIPT_PATH" --tui >/dev/null 2>&1 &
            ;;
        konsole)
            "${terminal_args[@]}" --appname "$APP_ID" -e "$SCRIPT_PATH" --tui >/dev/null 2>&1 &
            ;;
        gnome-terminal)
            "${terminal_args[@]}" --title="$APP_ID" -- "$SCRIPT_PATH" --tui >/dev/null 2>&1 &
            ;;
        xfce4-terminal)
            "${terminal_args[@]}" --title="$APP_ID" --execute "$SCRIPT_PATH" --tui >/dev/null 2>&1 &
            ;;
        xterm)
            "${terminal_args[@]}" -class "$APP_ID" -T "$APP_ID" -e "$SCRIPT_PATH" --tui >/dev/null 2>&1 &
            ;;
        *)
            "${terminal_args[@]}" -e "$SCRIPT_PATH" --tui >/dev/null 2>&1 &
            ;;
    esac
}

main() {
    case "${1:-}" in
        '')
            launch_with_terminal
            ;;
        --tui)
            run_tui
            ;;
        --print)
            print_static
            ;;
        -h|--help)
            usage
            ;;
        *)
            usage >&2
            printf 'Unknown option: %s\n' "$1" >&2
            return 2
            ;;
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
