#!/usr/bin/env bash
# ~/.config/hypr/scripts/hypridle_action.sh
# Authoritative guard for every Hypridle timeout action.

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

INHIBITOR_SH="${INHIBITOR_SH:-${CONF}/hypr/scripts/idle_inhibitor_global.sh}"
SCRIPTS_DIR="${CONF}/hypr/scripts"
QUICKSHELL_RESUME_SCRIPT="${QUICKSHELL_RESUME_SCRIPT:-${SCRIPTS_DIR}/quickshell_resume_recover.sh}"
LOG_FILE="${HYPRIDLE_ACTION_LOG:-${CACHE}/hypridle/actions.log}"

HYPRCTL_BIN="${HYPRCTL_BIN:-hyprctl}"
PLAYERCTL_BIN="${PLAYERCTL_BIN:-playerctl}"
BUSCTL_BIN="${BUSCTL_BIN:-busctl}"
PS_BIN="${PS_BIN:-ps}"
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-systemctl}"
SYSTEMD_RUN_BIN="${SYSTEMD_RUN_BIN:-systemd-run}"
LOGINCTL_BIN="${LOGINCTL_BIN:-loginctl}"
NOHUP_BIN="${NOHUP_BIN:-nohup}"
SYSTEMD_INHIBIT_BIN="${SYSTEMD_INHIBIT_BIN:-systemd-inhibit}"

OBS_LOG_FILE_OVERRIDE="${OBS_LOG_FILE_OVERRIDE:-}"
OBS_PROCESS_REQUIRED="${OBS_PROCESS_REQUIRED:-1}"


# Suspend-only productive-work protection.
# Known jobs, native sleep blockers, and sustained high CPU delay suspend.
# Waybar hiding, dimming, locking, and DPMS behavior remain unchanged.
SUSPEND_RUNTIME_DIR="${SUSPEND_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}}"
SUSPEND_WATCH_UNIT="${SUSPEND_WATCH_UNIT:-awtarchy-suspend-watch.service}"
SUSPEND_WATCH_PID_FILE="${SUSPEND_WATCH_PID_FILE:-${SUSPEND_RUNTIME_DIR}/awtarchy-suspend-watch.pid}"
SUSPEND_WATCH_LOG="${SUSPEND_WATCH_LOG:-${CACHE}/hypridle/suspend-watch.log}"
SUSPEND_WATCH_BACKEND="${SUSPEND_WATCH_BACKEND:-}"
SUSPEND_RECHECK_SECONDS="${SUSPEND_RECHECK_SECONDS:-60}"
SUSPEND_PRODUCTIVE_MIN_AGE="${SUSPEND_PRODUCTIVE_MIN_AGE:-30}"
SUSPEND_ACTIVITY_SAMPLE_SECONDS="${SUSPEND_ACTIVITY_SAMPLE_SECONDS:-5}"
SUSPEND_CPU_HIGH_PERCENT="${SUSPEND_CPU_HIGH_PERCENT:-85}"
SUSPEND_EXEC_OVERRIDE="${SUSPEND_EXEC_OVERRIDE:-}"

PROC_STAT_FILE="${PROC_STAT_FILE:-/proc/stat}"

# Match Linux process comm names, not full command lines. Bash performs this
# ERE match directly so backslashes are not reinterpreted by awk -v.
PRODUCTIVE_COMM_REGEX="${PRODUCTIVE_COMM_REGEX:-^(makepkg|pacman|paru|yay|pikaur|aura|trizen|make|gmake|ninja|cmake|meson|cargo|rustc|gcc|g\+\+|cc|c\+\+|clang|clang\+\+|cc1|cc1plus|lto1|ld|ld\.lld|mold|ar|ranlib|objcopy|strip|pahole|go|javac|gradle|mvn|ffmpeg|HandBrakeCLI|blender|rsync|rclone|restic|borg|tar|gzip|pigz|bzip2|pbzip2|xz|pixz|zstd|pzstd|7z|7zz|zip|unzip|cp|mv|dd|btrfs|zfs|fsck|mkfs\..*|wget|curl|aria2c)$}"

# Keep synchronized with the game classes in hyprland.lua.
GAME_CLASS_REGEX='^(steam_app_.*|lutris_game_class|minigalaxy|playnite_game_class|gamescope|chiaki|moonlight|com\.moonlight_stream\.Moonlight|.*\.exe)$'

# Teams for Linux may legitimately keep the PC awake during calls.
TEAMS_CLASS_REGEX='^(com\.github\.IsmaelMartinez\.teams_for_linux|teams[-_]?for[-_]?linux|microsoft[-_ ]?teams)$'

BROWSER_CLASS_REGEX='^(firefox|org\.mozilla\.firefox|firefoxdeveloperedition|librewolf|floorp|zen|zen-browser|chromium|chromium-browser|org\.chromium\.Chromium|google-chrome.*|brave-browser.*|com\.brave\.Browser|vivaldi.*|microsoft-edge.*)$'
BROWSER_MPRIS_REGEX='^(firefox|librewolf|floorp|zen|chromium|google-chrome|chrome|brave|vivaldi|microsoft-edge|edge)([._-]|$)'

VIDEO_PLAYER_CLASS_REGEX='^(mpv|vlc|org\.videolan\.VLC|celluloid|io\.github\.celluloid_player\.Celluloid|haruna|org\.kde\.haruna|smplayer|totem|org\.gnome\.Totem|clapper|com\.github\.rafostar\.Clapper|stremio|com\.stremio\.Stremio|jellyfin-media-player|com\.github\.iwalton3\.jellyfin-media-player|freetube|io\.freetubeapp\.FreeTube)$'
VIDEO_PLAYER_MPRIS_REGEX='(mpv|vlc|celluloid|haruna|smplayer|totem|clapper|stremio|jellyfin|freetube)'

# Music and audio-only playback must not block normal idling.
AUDIO_PLAYER_MPRIS_REGEX='^(spotify|ncspot|cider|amberol|rhythmbox|lollypop|audacious|strawberry|elisa|tauon|deadbeef|cmus|musikcube)([._-]|$)'
AUDIO_URL_REGEX='(music\.youtube\.com|open\.spotify\.com|soundcloud\.com|music\.apple\.com|tidal\.com|bandcamp\.com|deezer\.com|pandora\.com|music\.amazon\.)|\.(mp3|flac|ogg|oga|opus|m4a|aac|wav|wma)([?#]|$)'
AUDIO_TITLE_REGEX='(spotify|soundcloud|youtube music|apple music|bandcamp|tidal|deezer|pandora|amazon music)'

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    printf '%s %s\n' \
        "$(date '+%F %T')" \
        "$*" \
        >>"$LOG_FILE" 2>/dev/null || true
}

playerctl_available() {
    if [[ "$PLAYERCTL_BIN" == */* ]]; then
        [[ -x "$PLAYERCTL_BIN" ]]
    else
        command -v "$PLAYERCTL_BIN" >/dev/null 2>&1
    fi
}

get_clients() {
    timeout 2 "$HYPRCTL_BIN" clients -j 2>/dev/null || true
}


focused_workspace_id() {
    timeout 2 "$HYPRCTL_BIN" activeworkspace -j 2>/dev/null |
        jq -r '.id // empty' 2>/dev/null ||
        true
}

visible_workspaces_json() {
    local monitors

    monitors="$(
        timeout 2 "$HYPRCTL_BIN" monitors -j 2>/dev/null ||
            true
    )"

    if [[ -z "$monitors" ]]; then
        printf '%s\n' '[]'
        return 1
    fi

    jq -c '
        [
            .[]
            |
            (.activeWorkspace.id // empty),
            (
                .specialWorkspace.id
                // .activeSpecialWorkspace.id
                // empty
            )
        ]
        | map(
            select(
                type == "number"
                and . != 0
            )
        )
        | unique
    ' <<<"$monitors" 2>/dev/null || {
        printf '%s\n' '[]'
        return 1
    }
}

visible_workspace_ids() {
    visible_workspaces_json |
        jq -r '.[]' 2>/dev/null ||
        true
}

player_status() {
    local player="$1"

    timeout 1 "$PLAYERCTL_BIN" \
        --player="$player" \
        status \
        2>/dev/null ||
        true
}

player_metadata() {
    local player="$1"
    local separator=$'\x1f'
    local format

    format="{{xesam:title}}${separator}{{xesam:url}}${separator}{{xesam:album}}${separator}{{xesam:artist}}"

    timeout 1 "$PLAYERCTL_BIN" \
        --player="$player" \
        metadata \
        --format "$format" \
        2>/dev/null ||
        true
}

game_is_running() {
    local clients

    clients="$(get_clients)"
    [[ -n "$clients" ]] || return 1

    jq -e \
        --arg regex "$GAME_CLASS_REGEX" \
        '
        any(
            .[];
            (.mapped == true)
            and
            (
                ((.contentType // "") == "game")
                or
                ((.class // "") | test($regex; "i"))
                or
                ((.initialClass // "") | test($regex; "i"))
            )
        )
        ' \
        <<<"$clients" \
        >/dev/null 2>&1
}


teams_wayland_inhibitor_is_active() {
    local clients

    clients="$(get_clients)"
    [[ -n "$clients" ]] || return 1

    jq -e \
        --arg regex "$TEAMS_CLASS_REGEX" \
        '
        any(
            .[];
            (.mapped == true)
            and
            (
                ((.class // "") | test($regex; "i"))
                or
                ((.initialClass // "") | test($regex; "i"))
            )
            and
            ((.inhibitingIdle // false) == true)
        )
        ' \
        <<<"$clients" \
        >/dev/null 2>&1
}

teams_systemd_inhibitor_is_active() {
    command_is_available "$SYSTEMD_INHIBIT_BIN" || return 1

    timeout 2 "$SYSTEMD_INHIBIT_BIN" --list --no-pager 2>/dev/null |
        grep -Eqi \
            'teams[-_ ]?for[-_ ]?linux|com\.github\.IsmaelMartinez\.teams_for_linux|Microsoft Teams'
}

teams_inhibitor_is_active() {
    teams_wayland_inhibitor_is_active ||
        teams_systemd_inhibitor_is_active
}

obs_pids() {
    {
        pgrep -u "$(id -u)" -x obs 2>/dev/null || true
        pgrep -u "$(id -u)" -x obs-studio 2>/dev/null || true
    } |
        awk '/^[0-9]+$/ && !seen[$0]++'
}

obs_process_is_running() {
    obs_pids | grep -qE '^[0-9]+$'
}

obs_current_log() {
    local pid fd target
    local directory file modified
    local newest=""
    local newest_modified=-1

    if [[ -n "$OBS_LOG_FILE_OVERRIDE" ]]; then
        [[ -r "$OBS_LOG_FILE_OVERRIDE" ]] || return 1
        printf '%s\n' "$OBS_LOG_FILE_OVERRIDE"
        return 0
    fi

    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue

        for fd in "/proc/${pid}/fd/"*; do
            target="$(
                readlink -f -- "$fd" 2>/dev/null ||
                    true
            )"

            case "$target" in
                */obs-studio/logs/*.txt)
                    if [[ -r "$target" ]]; then
                        printf '%s\n' "$target"
                        return 0
                    fi
                    ;;
            esac
        done
    done < <(obs_pids)

    for directory in \
        "$HOME/.config/obs-studio/logs" \
        "$HOME/.var/app/com.obsproject.Studio/config/obs-studio/logs"
    do
        [[ -d "$directory" ]] || continue

        shopt -s nullglob

        for file in "$directory"/*.txt; do
            modified="$(
                stat -c '%Y' -- "$file" 2>/dev/null ||
                    printf '%s' -1
            )"

            [[ "$modified" =~ ^[0-9]+$ ]] || continue

            if (( modified > newest_modified )); then
                newest="$file"
                newest_modified="$modified"
            fi
        done
    done

    [[ -n "$newest" && -r "$newest" ]] || return 1
    printf '%s\n' "$newest"
}

obs_output_states() {
    local log_file

    if [[ "$OBS_PROCESS_REQUIRED" != "0" ]] &&
       ! obs_process_is_running
    then
        return 1
    fi

    log_file="$(obs_current_log)" || return 1

    awk '
        /==== Recording Start/ {
            recording = 1
        }

        /==== Recording Stop/ {
            recording = 0
        }

        /==== Streaming Start/ {
            streaming = 1
        }

        /==== Streaming Stop/ {
            streaming = 0
        }

        /User stopped the stream/ {
            streaming = 0
        }

        /streaming stop requested/ {
            streaming = 0
        }

        /Output '\''[^'\'']*stream[^'\'']*'\'': stopping/ {
            streaming = 0
        }

        /==== Replay Buffer Start/ {
            replay = 1
        }

        /==== Replay Buffer Stop/ {
            replay = 0
        }

        /Starting Virtual Camera output/ {
            virtual_camera = 1
        }

        /starting virtual-output/ {
            virtual_camera = 1
        }

        /Failed to start virtual camera/ {
            virtual_camera = 0
        }

        /Output '\''virtualcam_output'\'': stopping/ {
            virtual_camera = 0
        }

        /virtual-output stop/ {
            virtual_camera = 0
        }

        END {
            separator = ""

            if (recording) {
                printf "%srecording", separator
                separator = ","
            }

            if (streaming) {
                printf "%sstreaming", separator
                separator = ","
            }

            if (replay) {
                printf "%sreplay-buffer", separator
                separator = ","
            }

            if (virtual_camera) {
                printf "%svirtual-camera", separator
                separator = ","
            }

            if (separator != "") {
                printf "\n"
            }
        }
    ' "$log_file"
}

obs_output_is_active() {
    local states

    states="$(
        obs_output_states 2>/dev/null ||
            true
    )"

    [[ -n "$states" ]]
}

obs_diagnose() {
    local log_file states

    printf '%s\n' 'obs_processes:'

    if ! obs_pids |
        while IFS= read -r pid; do
            ps -o pid=,comm=,args= -p "$pid"
        done
    then
        true
    fi

    if ! obs_process_is_running; then
        printf '%s\n' '  none'
    fi

    log_file="$(
        obs_current_log 2>/dev/null ||
            true
    )"

    printf 'current_log=%s\n' "${log_file:-none}"

    states="$(
        obs_output_states 2>/dev/null ||
            true
    )"

    printf 'active_outputs=%s\n' "${states:-none}"

    if [[ -n "$states" ]]; then
        printf '%s\n' 'obs_output_active=yes'
    else
        printf '%s\n' 'obs_output_active=no'
    fi

    if [[ -n "$log_file" && -r "$log_file" ]]; then
        printf '\n%s\n' 'recent_output_events:'

        grep -E \
            '==== (Recording|Streaming|Replay Buffer) (Start|Stop)|User stopped the stream|streaming stop requested|Starting Virtual Camera output|starting virtual-output|Failed to start virtual camera|virtualcam_output.*stopping|virtual-output stop' \
            "$log_file" |
            tail -n 20 ||
            true
    fi
}


valid_positive_integer() {
    [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

valid_percent() {
    valid_positive_integer "${1:-}" &&
        (( 10#$1 >= 1 && 10#$1 <= 100 ))
}

command_is_available() {
    local command_name="${1:-}"

    [[ -n "$command_name" ]] || return 1

    if [[ "$command_name" == */* ]]; then
        [[ -x "$command_name" ]]
    else
        command -v "$command_name" >/dev/null 2>&1
    fi
}

normalize_suspend_settings() {
    valid_positive_integer "$SUSPEND_RECHECK_SECONDS" ||
        SUSPEND_RECHECK_SECONDS=60
    valid_positive_integer "$SUSPEND_PRODUCTIVE_MIN_AGE" ||
        SUSPEND_PRODUCTIVE_MIN_AGE=30
    valid_positive_integer "$SUSPEND_ACTIVITY_SAMPLE_SECONDS" ||
        SUSPEND_ACTIVITY_SAMPLE_SECONDS=5
    valid_percent "$SUSPEND_CPU_HIGH_PERCENT" ||
        SUSPEND_CPU_HIGH_PERCENT=85
}

manual_inhibitor_is_active() {
    [[ -x "$INHIBITOR_SH" ]] &&
        "$INHIBITOR_SH" is-active >/dev/null 2>&1
}

native_sleep_blocked() {
    local value

    command_is_available "$BUSCTL_BIN" || return 1

    value="$(
        "$BUSCTL_BIN" get-property \
            --value \
            org.freedesktop.login1 \
            /org/freedesktop/login1 \
            org.freedesktop.login1.Manager \
            BlockInhibited \
            2>/dev/null ||
        "$BUSCTL_BIN" get-property \
            org.freedesktop.login1 \
            /org/freedesktop/login1 \
            org.freedesktop.login1.Manager \
            BlockInhibited \
            2>/dev/null ||
        true
    )"

    value="${value#s }"
    value="${value#\"}"
    value="${value%\"}"
    value="${value//:/ }"

    [[ " $value " == *" sleep "* ]]
}

productive_jobs() {
    local pid age state comm
    local restore_nocasematch=0
    local process_list

    command_is_available "$PS_BIN" || return 1

    process_list="$(
        LC_ALL=C "$PS_BIN" \
            -eo pid=,etimes=,stat=,comm= \
            2>/dev/null ||
        true
    )"

    [[ -n "$process_list" ]] || return 1

    shopt -q nocasematch || {
        shopt -s nocasematch
        restore_nocasematch=1
    }

    while read -r pid age state comm; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        [[ "$age" =~ ^[0-9]+$ ]] || continue
        (( age >= SUSPEND_PRODUCTIVE_MIN_AGE )) || continue

        case "$state" in
            Z*|T*|X*)
                continue
                ;;
        esac

        if [[ "$comm" =~ $PRODUCTIVE_COMM_REGEX ]]; then
            printf 'pid=%s age=%ss state=%s command=%s\n' \
                "$pid" "$age" "$state" "$comm"
        fi
    done <<<"$process_list"

    (( restore_nocasematch == 0 )) || shopt -u nocasematch
}

cpu_snapshot() {
    local label user nice system idle iowait irq softirq steal
    local total busy

    [[ -r "$PROC_STAT_FILE" ]] || return 1

    read -r \
        label user nice system idle iowait irq softirq steal _ \
        <"$PROC_STAT_FILE" ||
        return 1

    [[ "$label" == cpu ]] || return 1

    for value in \
        "$user" "$nice" "$system" "$idle" \
        "$iowait" "$irq" "$softirq" "$steal"
    do
        [[ "$value" =~ ^[0-9]+$ ]] || return 1
    done

    total=$((
        user + nice + system + idle + iowait + irq + softirq + steal
    ))
    busy=$((total - idle - iowait))

    printf '%s %s\n' "$busy" "$total"
}

activity_interval() {
    local seconds="$1"
    local busy_before total_before busy_after total_after
    local busy_delta total_delta
    local cpu_percent

    if ! read -r busy_before total_before < <(cpu_snapshot); then
        printf '%s\n' '0 unavailable'
        return 0
    fi

    sleep "$seconds"

    if ! read -r busy_after total_after < <(cpu_snapshot); then
        printf '%s\n' '0 unavailable'
        return 0
    fi

    busy_delta=$((busy_after - busy_before))
    total_delta=$((total_after - total_before))

    (( busy_delta < 0 )) && busy_delta=0
    (( total_delta < 1 )) && total_delta=1

    cpu_percent=$((busy_delta * 100 / total_delta))

    printf '%s available\n' "$cpu_percent"
}

measure_sustained_system_activity() {
    local available_one available_two

    read -r SUSPEND_CPU_ONE available_one \
        < <(activity_interval "$SUSPEND_ACTIVITY_SAMPLE_SECONDS")

    read -r SUSPEND_CPU_TWO available_two \
        < <(activity_interval "$SUSPEND_ACTIVITY_SAMPLE_SECONDS")

    SUSPEND_LAST_ACTIVITY="interval1_cpu=${SUSPEND_CPU_ONE}% interval2_cpu=${SUSPEND_CPU_TWO}%"

    [[ "$available_one" == available ]] || return 1
    [[ "$available_two" == available ]] || return 1

    ((
        SUSPEND_CPU_ONE >= SUSPEND_CPU_HIGH_PERCENT &&
        SUSPEND_CPU_TWO >= SUSPEND_CPU_HIGH_PERCENT
    ))
}
productive_sleep_guard_reason() {
    local jobs

    normalize_suspend_settings

    if native_sleep_blocked; then
        printf '%s\n' 'native sleep block inhibitor active'
        return 0
    fi

    jobs="$(productive_jobs)"
    if [[ -n "$jobs" ]]; then
        printf 'productive job active: %s\n' \
            "$(head -n 1 <<<"$jobs")"
        return 0
    fi

    if measure_sustained_system_activity; then
        printf 'sustained system activity: %s\n' \
            "$SUSPEND_LAST_ACTIVITY"
        return 0
    fi

    # Catch a job or inhibitor that appeared while activity was sampled.
    if native_sleep_blocked; then
        printf '%s\n' 'native sleep block inhibitor became active'
        return 0
    fi

    jobs="$(productive_jobs)"
    if [[ -n "$jobs" ]]; then
        printf 'productive job became active: %s\n' \
            "$(head -n 1 <<<"$jobs")"
        return 0
    fi

    return 1
}

suspend_watch_reason() {
    local states

    if manual_inhibitor_is_active; then
        printf '%s\n' 'Waybar inhibitor active'
        return 0
    fi

    if teams_inhibitor_is_active; then
        printf '%s\n' 'Teams inhibitor active'
        return 0
    fi

    if obs_output_is_active; then
        states="$(obs_output_states || printf unknown)"
        printf 'OBS output active: %s\n' "$states"
        return 0
    fi

    if game_is_running; then
        printf '%s\n' 'game active'
        return 0
    fi

    if video_is_playing; then
        printf '%s\n' 'visible video playback active'
        return 0
    fi

    productive_sleep_guard_reason
}

suspend_guard_diagnose() {
    local jobs reason activity_active=no

    normalize_suspend_settings

    printf 'manual_inhibitor=%s\n' \
        "$(manual_inhibitor_is_active && printf yes || printf no)"
    printf 'teams_inhibitor=%s\n' \
        "$(teams_inhibitor_is_active && printf yes || printf no)"
    printf 'obs_output=%s\n' \
        "$(obs_output_is_active && printf yes || printf no)"
    printf 'game=%s\n' \
        "$(game_is_running && printf yes || printf no)"
    printf 'visible_video=%s\n' \
        "$(video_is_playing && printf yes || printf no)"
    printf 'native_sleep_block=%s\n' \
        "$(native_sleep_blocked && printf yes || printf no)"

    printf '\n%s\n' 'productive_jobs:'
    jobs="$(productive_jobs)"
    if [[ -n "$jobs" ]]; then
        printf '%s\n' "$jobs"
    else
        printf '%s\n' 'none'
    fi

    printf '\n%s\n' 'activity_sampling:'
    printf 'sample_seconds=%s x 2\n' "$SUSPEND_ACTIVITY_SAMPLE_SECONDS"
    printf 'high_cpu_threshold=%s%%\n' "$SUSPEND_CPU_HIGH_PERCENT"

    if measure_sustained_system_activity; then
        activity_active=yes
    fi

    printf 'sustained_activity=%s\n' "$activity_active"
    printf '%s\n' "$SUSPEND_LAST_ACTIVITY"

    if manual_inhibitor_is_active; then
        reason='Waybar inhibitor active'
    elif teams_inhibitor_is_active; then
        reason='Teams inhibitor active'
    elif obs_output_is_active; then
        reason="OBS output active: $(obs_output_states || printf unknown)"
    elif game_is_running; then
        reason='game active'
    elif video_is_playing; then
        reason='visible video playback active'
    elif native_sleep_blocked; then
        reason='native sleep block inhibitor active'
    elif [[ -n "$jobs" ]]; then
        reason="productive job active: $(head -n 1 <<<"$jobs")"
    elif [[ "$activity_active" == yes ]]; then
        reason="sustained system activity: $SUSPEND_LAST_ACTIVITY"
    else
        reason='none'
    fi

    printf '\nsuspend_guard_active=%s\n' \
        "$([[ "$reason" != none ]] && printf yes || printf no)"
    printf 'reason=%s\n' "$reason"
}

suspend_guard_is_active() {
    suspend_watch_reason >/dev/null
}

resolve_self_path() {
    readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null ||
        printf '%s\n' "${BASH_SOURCE[0]}"
}

fallback_suspend_watch_pid() {
    local pid argument
    local self_path
    local found_self=0
    local found_action=0
    local -a arguments=()

    [[ -r "$SUSPEND_WATCH_PID_FILE" ]] || return 1

    pid="$(tr -d '[:space:]' <"$SUSPEND_WATCH_PID_FILE" 2>/dev/null || true)"
    [[ "$pid" =~ ^[0-9]+$ ]] || {
        rm -f "$SUSPEND_WATCH_PID_FILE" 2>/dev/null || true
        return 1
    }

    kill -0 "$pid" 2>/dev/null || {
        rm -f "$SUSPEND_WATCH_PID_FILE" 2>/dev/null || true
        return 1
    }

    [[ -r "/proc/${pid}/cmdline" ]] || return 1
    mapfile -d '' -t arguments <"/proc/${pid}/cmdline" || true

    self_path="$(resolve_self_path)"

    for argument in "${arguments[@]}"; do
        [[ "$argument" == "$self_path" ]] && found_self=1
        [[ "$argument" == suspend-watch ]] && found_action=1
    done

    if (( found_self == 1 && found_action == 1 )); then
        printf '%s\n' "$pid"
        return 0
    fi

    rm -f "$SUSPEND_WATCH_PID_FILE" 2>/dev/null || true
    return 1
}

systemd_suspend_watch_is_active() {
    local state

    command_is_available "$SYSTEMCTL_BIN" || return 1

    state="$(
        "$SYSTEMCTL_BIN" --user is-active \
            "$SUSPEND_WATCH_UNIT" 2>/dev/null ||
            true
    )"

    [[ "$state" == active || "$state" == activating ]]
}

suspend_watch_is_active() {
    systemd_suspend_watch_is_active && return 0
    fallback_suspend_watch_pid >/dev/null
}

cancel_suspend_watch() {
    local pid
    local cancelled=0

    if systemd_suspend_watch_is_active; then
        "$SYSTEMCTL_BIN" --user stop "$SUSPEND_WATCH_UNIT" \
            >/dev/null 2>&1 || true
        cancelled=1
    fi

    pid="$(fallback_suspend_watch_pid || true)"
    if [[ -n "$pid" ]]; then
        kill "$pid" >/dev/null 2>&1 || true

        for _ in {1..30}; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.05
        done

        kill -9 "$pid" >/dev/null 2>&1 || true
        rm -f "$SUSPEND_WATCH_PID_FILE" 2>/dev/null || true
        cancelled=1
    fi

    if (( cancelled == 1 )); then
        log 'suspend watch cancelled by user activity'
    fi
}

cleanup_fallback_watch_pid() {
    local recorded

    [[ "$SUSPEND_WATCH_BACKEND" == fallback ]] || return 0
    [[ -r "$SUSPEND_WATCH_PID_FILE" ]] || return 0

    recorded="$(tr -d '[:space:]' <"$SUSPEND_WATCH_PID_FILE" 2>/dev/null || true)"
    [[ "$recorded" == "$$" ]] || return 0

    rm -f "$SUSPEND_WATCH_PID_FILE" 2>/dev/null || true
}

start_fallback_suspend_watch() {
    local self_path="$1"
    local pid temporary_pid_file

    command_is_available "$NOHUP_BIN" || return 1

    mkdir -p \
        "$SUSPEND_RUNTIME_DIR" \
        "$(dirname "$SUSPEND_WATCH_LOG")" \
        2>/dev/null ||
        return 1

    rm -f "$SUSPEND_WATCH_PID_FILE" 2>/dev/null || true

    SUSPEND_WATCH_BACKEND=fallback \
        "$NOHUP_BIN" "$self_path" suspend-watch \
        >>"$SUSPEND_WATCH_LOG" 2>&1 </dev/null &
    pid=$!

    temporary_pid_file="${SUSPEND_WATCH_PID_FILE}.tmp.$$"
    printf '%s\n' "$pid" >"$temporary_pid_file"
    mv -f "$temporary_pid_file" "$SUSPEND_WATCH_PID_FILE"

    sleep 0.05

    if kill -0 "$pid" 2>/dev/null; then
        log "suspend watch started with fallback pid ${pid}"
        return 0
    fi

    rm -f "$SUSPEND_WATCH_PID_FILE" 2>/dev/null || true
    return 1
}

start_suspend_watch() {
    local self_path variable
    local -a environment_args=()

    if suspend_watch_is_active; then
        log 'suspend watch already active'
        return 0
    fi

    self_path="$(resolve_self_path)"

    for variable in \
        HOME \
        PATH \
        XDG_CONFIG_HOME \
        XDG_CACHE_HOME \
        XDG_RUNTIME_DIR \
        HYPRLAND_INSTANCE_SIGNATURE \
        WAYLAND_DISPLAY \
        DBUS_SESSION_BUS_ADDRESS \
        INHIBITOR_SH \
        HYPRCTL_BIN \
        PLAYERCTL_BIN \
        BUSCTL_BIN \
        PS_BIN \
        SYSTEMCTL_BIN \
        SYSTEMD_RUN_BIN \
        LOGINCTL_BIN \
        NOHUP_BIN \
        SYSTEMD_INHIBIT_BIN \
        OBS_LOG_FILE_OVERRIDE \
        OBS_PROCESS_REQUIRED \
        SUSPEND_RUNTIME_DIR \
        SUSPEND_WATCH_UNIT \
        SUSPEND_WATCH_PID_FILE \
        SUSPEND_WATCH_LOG \
        SUSPEND_RECHECK_SECONDS \
        SUSPEND_PRODUCTIVE_MIN_AGE \
        SUSPEND_ACTIVITY_SAMPLE_SECONDS \
        SUSPEND_CPU_HIGH_PERCENT \
        SUSPEND_EXEC_OVERRIDE \
        PROC_STAT_FILE \
        PRODUCTIVE_COMM_REGEX \
        TEAMS_CLASS_REGEX
    do
        if [[ -n "${!variable:-}" ]]; then
            environment_args+=("--setenv=${variable}=${!variable}")
        fi
    done

    if command_is_available "$SYSTEMD_RUN_BIN" &&
       command_is_available "$SYSTEMCTL_BIN" &&
       "$SYSTEMCTL_BIN" --user show-environment \
            >/dev/null 2>&1
    then
        "$SYSTEMCTL_BIN" --user reset-failed \
            "$SUSPEND_WATCH_UNIT" >/dev/null 2>&1 || true

        if "$SYSTEMD_RUN_BIN" \
            --user \
            --quiet \
            --collect \
            --unit="$SUSPEND_WATCH_UNIT" \
            --service-type=exec \
            --setenv=SUSPEND_WATCH_BACKEND=systemd \
            "${environment_args[@]}" \
            -- \
            "$self_path" suspend-watch
        then
            log 'suspend watch started with systemd user manager'
            return 0
        fi
    fi

    log 'suspend watch transient unit unavailable; using process fallback'

    if start_fallback_suspend_watch "$self_path"; then
        return 0
    fi

    log 'suspend watch could not be started; refusing unsafe suspend'
    return 1
}

perform_suspend() {
    if [[ -n "$SUSPEND_EXEC_OVERRIDE" ]]; then
        command_is_available "$SUSPEND_EXEC_OVERRIDE" || return 1
        "$SUSPEND_EXEC_OVERRIDE"
        return
    fi

    if command_is_available "$SYSTEMCTL_BIN" &&
       "$SYSTEMCTL_BIN" suspend
    then
        return 0
    fi

    command_is_available "$LOGINCTL_BIN" || return 1
    "$LOGINCTL_BIN" suspend
}

suspend_watch_loop() {
    local reason

    normalize_suspend_settings

    if [[ "$SUSPEND_WATCH_BACKEND" == fallback ]]; then
        trap cleanup_fallback_watch_pid EXIT INT TERM
    fi

    while true; do
        reason="$(suspend_watch_reason || true)"

        if [[ -z "$reason" ]]; then
            log 'suspend watch: guard clear; suspending'

            if perform_suspend; then
                return 0
            fi

            log "suspend watch: suspend command failed; rechecking in ${SUSPEND_RECHECK_SECONDS}s"
        else
            log "suspend watch: blocked; ${reason}; rechecking in ${SUSPEND_RECHECK_SECONDS}s"
        fi

        sleep "$SUSPEND_RECHECK_SECONDS"
    done
}

media_is_audio_only() {
    local player="${1,,}"
    local title="${2,,}"
    local url="${3,,}"
    local album="$4"

    [[ "$player" =~ $AUDIO_PLAYER_MPRIS_REGEX ]] &&
        return 0

    [[ "$url" =~ $AUDIO_URL_REGEX ]] &&
        return 0

    [[ "$title" =~ $AUDIO_TITLE_REGEX ]] &&
        return 0

    # Album metadata is treated as a strong music signal.
    [[ -n "${album//[[:space:]]/}" ]] &&
        return 0

    return 1
}


browser_video_on_visible_workspace() {
    local media_title="$1"
    local visible clients

    [[ ${#media_title} -ge 4 ]] || return 1

    visible="$(visible_workspaces_json)"
    clients="$(get_clients)"

    [[ "$visible" != "[]" ]] || return 1
    [[ -n "$clients" ]] || return 1

    jq -e \
        --argjson visible "$visible" \
        --arg regex "$BROWSER_CLASS_REGEX" \
        --arg media_title "$media_title" \
        '
        ($media_title | ascii_downcase) as $needle
        |
        any(
            .[];
            (.mapped == true)
            and
            (
                (.workspace.id // -999999) as $workspace_id
                |
                ($visible | index($workspace_id)) != null
            )
            and
            (
                ((.class // "") | test($regex; "i"))
                or
                ((.initialClass // "") | test($regex; "i"))
            )
            and
            (
                (.title // "")
                | ascii_downcase
                | contains($needle)
            )
        )
        ' \
        <<<"$clients" \
        >/dev/null 2>&1
}


dedicated_video_on_visible_workspace() {
    local visible clients

    visible="$(visible_workspaces_json)"
    clients="$(get_clients)"

    [[ "$visible" != "[]" ]] || return 1
    [[ -n "$clients" ]] || return 1

    jq -e \
        --argjson visible "$visible" \
        --arg regex "$VIDEO_PLAYER_CLASS_REGEX" \
        '
        any(
            .[];
            (.mapped == true)
            and
            (
                (.workspace.id // -999999) as $workspace_id
                |
                ($visible | index($workspace_id)) != null
            )
            and
            (
                ((.class // "") | test($regex; "i"))
                or
                ((.initialClass // "") | test($regex; "i"))
            )
        )
        ' \
        <<<"$clients" \
        >/dev/null 2>&1
}

# Native Wayland video players such as mpv can inhibit idle without exposing
# an MPRIS player to playerctl. Hypridle intentionally ignores those inhibitors
# globally, so honor them selectively for visible dedicated video windows.
dedicated_video_native_inhibit_on_visible_workspace() {
    local visible clients

    visible="$(visible_workspaces_json)"
    clients="$(get_clients)"

    [[ "$visible" != "[]" ]] || return 1
    [[ -n "$clients" ]] || return 1

    jq -e \
        --argjson visible "$visible" \
        --arg regex "$VIDEO_PLAYER_CLASS_REGEX" \
        '
        any(
            .[];
            (.mapped == true)
            and
            ((.inhibitingIdle // false) == true)
            and
            (
                (.workspace.id // -999999) as $workspace_id
                |
                ($visible | index($workspace_id)) != null
            )
            and
            (
                ((.class // "") | test($regex; "i"))
                or
                ((.initialClass // "") | test($regex; "i"))
            )
        )
        ' \
        <<<"$clients" \
        >/dev/null 2>&1
}

video_is_playing() {
    local player status metadata
    local title url album artist
    local separator=$'\x1f'
    local player_lower

    if dedicated_video_native_inhibit_on_visible_workspace; then
        return 0
    fi

    playerctl_available || return 1

    while IFS= read -r player; do
        [[ -n "$player" ]] || continue

        status="$(player_status "$player")"
        [[ "$status" == "Playing" ]] || continue

        metadata="$(player_metadata "$player")"

        title=""
        url=""
        album=""
        artist=""

        IFS="$separator" read -r title url album artist <<<"$metadata"

        if media_is_audio_only \
            "$player" \
            "$title" \
            "$url" \
            "$album"
        then
            continue
        fi

        player_lower="${player,,}"

        if [[ "$player_lower" =~ $VIDEO_PLAYER_MPRIS_REGEX ]] &&
           dedicated_video_on_visible_workspace
        then
            return 0
        fi

        if [[ "$player_lower" =~ $BROWSER_MPRIS_REGEX ]] &&
           browser_video_on_visible_workspace "$title"
        then
            return 0
        fi
    done < <(
        timeout 2 "$PLAYERCTL_BIN" --list-all 2>/dev/null ||
            true
    )

    return 1
}

video_diagnose() {
    local player status metadata
    local title url album artist
    local separator=$'\x1f'
    local classification

    printf 'focused_workspace=%s\n' \
        "$(focused_workspace_id || printf unknown)"

    printf 'visible_workspaces=%s\n' \
        "$(visible_workspaces_json |
            jq -r '
                if length == 0 then
                    "none"
                else
                    map(tostring) | join(",")
                end
            ' 2>/dev/null || printf unknown)"

    printf '\n%s\n' 'relevant_windows:'

    get_clients |
        jq -r \
            --arg browser "$BROWSER_CLASS_REGEX" \
            --arg video "$VIDEO_PLAYER_CLASS_REGEX" \
            '
            .[]
            | select(
                ((.class // "") | test($browser; "i"))
                or
                ((.initialClass // "") | test($browser; "i"))
                or
                ((.class // "") | test($video; "i"))
                or
                ((.initialClass // "") | test($video; "i"))
            )
            |
            "class=\(.class) workspace=\(.workspace.id) mapped=\(.mapped) fullscreen=\(.fullscreen // "missing") inhibiting_idle=\(.inhibitingIdle // "missing") title=\(.title)"
            ' \
            2>/dev/null ||
        true

    printf '\nnative_visible_video_inhibitor=%s\n' \
        "$(dedicated_video_native_inhibit_on_visible_workspace && printf yes || printf no)"

    printf '\n%s\n' 'mpris_players:'

    while IFS= read -r player; do
        [[ -n "$player" ]] || continue

        status="$(player_status "$player")"
        metadata="$(player_metadata "$player")"

        title=""
        url=""
        album=""
        artist=""

        IFS="$separator" read -r title url album artist <<<"$metadata"

        if media_is_audio_only \
            "$player" \
            "$title" \
            "$url" \
            "$album"
        then
            classification="audio-only"
        else
            classification="possible-video"
        fi

        printf 'player=%s\n' "$player"
        printf '  status=%s\n' "${status:-unknown}"
        printf '  classification=%s\n' "$classification"
        printf '  title=%s\n' "${title:-none}"
        printf '  url=%s\n' "${url:-none}"
        printf '  album=%s\n' "${album:-none}"
        printf '  artist=%s\n' "${artist:-none}"
    done < <(
        timeout 2 "$PLAYERCTL_BIN" --list-all 2>/dev/null ||
            true
    )

    printf '\nvideo_active=%s\n' \
        "$(video_is_playing && printf yes || printf no)"
}

action="${1:-}"
shift || true

case "$action" in
    prepare-sleep)
        "$INHIBITOR_SH" off >/dev/null 2>&1 || true
        log "sleep transition: inhibitor reset before sleep"
        exec loginctl lock-session
        ;;

    resume-sleep)
        cancel_suspend_watch
        "$INHIBITOR_SH" off >/dev/null 2>&1 || true
        log "sleep transition: inhibitor reset after sleep"
        if ! "$HYPRCTL_BIN" dispatch 'hl.dsp.dpms({ action = "enable" })'; then
            log "sleep transition: failed to enable displays after sleep"
        fi
        if "$QUICKSHELL_RESUME_SCRIPT"; then
            log "sleep transition: Quickshell resume recovery completed"
        else
            log "sleep transition: Quickshell resume recovery failed"
        fi
        ;;

    teams-inhibit-active)
        teams_inhibitor_is_active
        exit
        ;;

    game-active)
        game_is_running
        exit
        ;;

    video-active)
        video_is_playing
        exit
        ;;

    video-diagnose)
        video_diagnose
        exit
        ;;

    obs-active)
        obs_output_is_active
        exit
        ;;

    obs-diagnose)
        obs_diagnose
        exit
        ;;


    suspend-guard-active)
        suspend_guard_is_active
        exit
        ;;

    suspend-guard-diagnose)
        suspend_guard_diagnose
        exit
        ;;

    suspend-watch-status)
        suspend_watch_is_active
        exit
        ;;

    cancel-suspend-watch)
        cancel_suspend_watch
        exit
        ;;

    suspend-watch)
        suspend_watch_loop
        exit
        ;;
esac

if [[ "$action" == "suspend" ]]; then
    start_suspend_watch
    exit
fi

if [[ -x "$INHIBITOR_SH" ]] &&
   "$INHIBITOR_SH" is-active >/dev/null 2>&1; then
    log "blocked timeout action: ${action:-missing}; Waybar inhibitor active"
    exit 0
fi

if teams_inhibitor_is_active; then
    log "blocked timeout action: ${action:-missing}; Teams inhibitor active"
    exit 0
fi

if obs_output_is_active; then
    log "blocked timeout action: ${action:-missing}; OBS output active: $(obs_output_states || printf unknown)"
    exit 0
fi

if game_is_running; then
    log "blocked timeout action: ${action:-missing}; game active"
    exit 0
fi

if video_is_playing; then
    log "blocked timeout action: ${action:-missing}; visible video playback active"
    exit 0
fi

log "allowed timeout action: ${action:-missing}"

case "$action" in
    waybar-hide)
        exec "${SCRIPTS_DIR}/quickshell_bar_idle_hide.sh"
        ;;

    dim)
        exec "${SCRIPTS_DIR}/dim_display.sh"
        ;;

    lock)
        exec loginctl lock-session
        ;;

    dpms-off)
        exec "$HYPRCTL_BIN" dispatch 'hl.dsp.dpms({ action = "disable" })'
        ;;

    test-touch)
        marker="${1:-}"

        [[ -n "$marker" ]] || {
            printf '%s\n' 'test-touch requires a marker path' >&2
            exit 2
        }

        printf 'fired\n' >"$marker"
        ;;

    *)
        printf 'Unknown Hypridle action: %s\n' \
            "${action:-missing}" >&2
        exit 2
        ;;
esac
