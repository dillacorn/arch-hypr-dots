#!/usr/bin/env bash
# Prepare and submit user-approved, sanitized Awtarchy failure reports.

set -uo pipefail
umask 077

REPORT_ENDPOINT="${AWTARCHY_REPORT_ENDPOINT:-https://awtarchy-reports.dillacorn.workers.dev/v1/report}"
STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
REPORT_DIR="${STATE_HOME}/awtarchy/reports"
COMMAND_VERSION_FILE="${STATE_HOME}/awtarchy/command-version"
CONFIG_VERSION_FILE="${STATE_HOME}/awtarchy/config-version"

log_error() {
    printf 'Awtarchy report: %s\n' "$*" >&2
}

state_value() {
    local key="$1" file="$2"
    [[ -r "$file" ]] || return 1
    sed -n "s/^${key}=//p" "$file" | head -n1
}

safe_value() {
    local value="$1" pattern="$2" fallback="${3:-unknown}"
    if [[ "$value" =~ $pattern ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$fallback"
    fi
}

config_version() {
    local value=""
    value="$(state_value tag "$CONFIG_VERSION_FILE" 2>/dev/null || true)"
    safe_value "${value:-unknown}" '^[A-Za-z0-9._+@/-]{1,128}$'
}

command_revision() {
    local value=""
    value="$(state_value revision "$COMMAND_VERSION_FILE" 2>/dev/null || true)"
    value="${value,,}"
    if [[ "$value" =~ ^[0-9a-f]{40}$ ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' unknown
    fi
}

extract_runtime_version() {
    local command="$1" output="" value=""
    shift
    command -v "$command" >/dev/null 2>&1 || { printf '%s\n' unknown; return 0; }
    output="$("$command" "$@" 2>/dev/null || true)"
    value="$(grep -Eo '[0-9]+\.[0-9]+\.[0-9]+([._+-][A-Za-z0-9._+-]+)?' <<<"$output" | head -n1)"
    safe_value "${value:-unknown}" '^[A-Za-z0-9._+-]{1,96}$'
}

kernel_version() {
    local value="unknown"
    if command -v uname >/dev/null 2>&1; then
        value="$(uname -r 2>/dev/null || true)"
    fi
    safe_value "${value:-unknown}" '^[A-Za-z0-9._+-]{1,96}$'
}

gpu_family() {
    local output=""
    command -v lspci >/dev/null 2>&1 || { printf '%s\n' Unknown; return 0; }
    output="$(lspci 2>/dev/null || true)"
    if grep -Eqi 'VGA|3D|Display' <<<"$output"; then
        if grep -Eqi 'NVIDIA' <<<"$output"; then
            printf '%s\n' NVIDIA
        elif grep -Eqi 'AMD|ATI' <<<"$output"; then
            printf '%s\n' AMD
        elif grep -Eqi 'Intel' <<<"$output"; then
            printf '%s\n' Intel
        else
            printf '%s\n' Other
        fi
    else
        printf '%s\n' Unknown
    fi
}

valid_failure() {
    case "$1|$2|$3" in
        quickshell\|start\|quickshell_not_ready|\
        quickshell\|restart\|quickshell_not_ready|\
        quickshell\|restart_after_update\|quickshell_not_ready|\
        resume_recovery\|start\|quickshell_start_failed|\
        resume_recovery\|restart\|quickshell_restart_failed|\
        resume_recovery\|final_validation\|expected_bars_missing)
            return 0
            ;;
        *) return 1 ;;
    esac
}

report_path() {
    printf '%s/%s--%s--%s.json\n' "$REPORT_DIR" "$1" "$2" "$3"
}

write_pending_report() {
    local component="$1" stage="$2" error_code="$3"
    local path tmp config revision hyprland quickshell kernel gpu
    local recovery_attempted="${AWTARCHY_REPORT_RECOVERY_ATTEMPTED:-}"
    local recovery_succeeded="${AWTARCHY_REPORT_RECOVERY_SUCCEEDED:-}"

    valid_failure "$component" "$stage" "$error_code" || return 2
    command -v jq >/dev/null 2>&1 || return 127

    mkdir -p -- "$REPORT_DIR" || return 1
    chmod 0700 -- "$REPORT_DIR" 2>/dev/null || true
    path="$(report_path "$component" "$stage" "$error_code")"
    tmp="${path}.tmp.$$"

    config="$(config_version)"
    revision="$(command_revision)"
    hyprland="$(extract_runtime_version hyprctl version)"
    quickshell="$(extract_runtime_version qs --version)"
    kernel="$(kernel_version)"
    gpu="$(gpu_family)"

    jq -n \
        --arg component "$component" \
        --arg stage "$stage" \
        --arg error_code "$error_code" \
        --arg config "$config" \
        --arg revision "$revision" \
        --arg hyprland "$hyprland" \
        --arg quickshell "$quickshell" \
        --arg kernel "$kernel" \
        --arg gpu "$gpu" \
        --arg recovery_attempted "$recovery_attempted" \
        --arg recovery_succeeded "$recovery_succeeded" '
        {
          schema_version: 1,
          report_type: "failure",
          component: $component,
          failure_stage: $stage,
          error_code: $error_code,
          awtarchy_config_version: $config,
          awtarchy_command_revision: $revision,
          hyprland_version: $hyprland,
          quickshell_version: $quickshell,
          kernel_version: $kernel,
          gpu_family: $gpu
        }
        | if ($recovery_attempted == "true" or $recovery_attempted == "false" or
              $recovery_succeeded == "true" or $recovery_succeeded == "false") then
            .context = {}
            | if ($recovery_attempted == "true" or $recovery_attempted == "false") then
                .context.recovery_attempted = ($recovery_attempted == "true")
              else . end
            | if ($recovery_succeeded == "true" or $recovery_succeeded == "false") then
                .context.recovery_succeeded = ($recovery_succeeded == "true")
              else . end
          else . end
    ' >"$tmp" || { rm -f -- "$tmp"; return 1; }

    chmod 0600 -- "$tmp" || { rm -f -- "$tmp"; return 1; }
    mv -f -- "$tmp" "$path" || { rm -f -- "$tmp"; return 1; }
    printf '%s\n' "$path"
}

submit_report() {
    local path="$1" response="" issue_url=""
    [[ -f "$path" && ! -L "$path" ]] || return 2
    command -v curl >/dev/null 2>&1 || return 127
    command -v jq >/dev/null 2>&1 || return 127

    response="$(curl -fsS \
        --connect-timeout 5 \
        --max-time 15 \
        -H 'Content-Type: application/json' \
        --data-binary "@${path}" \
        "$REPORT_ENDPOINT")" || return 1

    jq -e '.ok == true' <<<"$response" >/dev/null 2>&1 || return 1
    issue_url="$(jq -r '.issue_url // empty' <<<"$response" 2>/dev/null || true)"
    rm -f -- "$path"
    if [[ -n "$issue_url" ]]; then
        printf 'Awtarchy failure report sent: %s\n' "$issue_url"
    else
        printf 'Awtarchy failure report sent.\n'
    fi
}

review_report() {
    local path="$1"
    [[ -f "$path" && ! -L "$path" ]] || return 2
    command -v jq >/dev/null 2>&1 || return 127
    jq . "$path"
}

discard_report() {
    local path="$1"
    [[ -f "$path" && ! -L "$path" ]] || return 0
    rm -f -- "$path"
}

interactive_terminal() {
    [[ ${AWTARCHY_REPORT_NO_PROMPT:-0} != 1 ]] || return 1
    [[ -t 0 && -t 1 && -r /dev/tty && -w /dev/tty ]]
}

prompt_report() {
    local path="$1" choice=""
    interactive_terminal || return 0

    while true; do
        printf '\nAwtarchy detected a failure.\n' >/dev/tty
        printf 'A sanitized failure report can be sent to the Awtarchy project.\n' >/dev/tty
        printf 'It does not include your username, hostname, home path, raw logs, or a persistent machine ID.\n\n' >/dev/tty
        printf '  [S] Send report\n' >/dev/tty
        printf '  [R] Review report\n' >/dev/tty
        printf "  [N] Don't send\n" >/dev/tty
        printf 'Choose [N]: ' >/dev/tty
        IFS= read -r choice </dev/tty || return 0
        case "${choice,,}" in
            s|send)
                if submit_report "$path" >/dev/tty 2>&1; then
                    return 0
                fi
                printf 'Report submission failed. The sanitized report was kept locally for later.\n' >/dev/tty
                return 0
                ;;
            r|review)
                review_report "$path" >/dev/tty 2>&1 || true
                printf '\n' >/dev/tty
                ;;
            n|no|""|don\'t\ send|dont\ send)
                discard_report "$path"
                printf 'Failure report was not sent.\n' >/dev/tty
                return 0
                ;;
            *)
                printf 'Choose S, R, or N.\n' >/dev/tty
                ;;
        esac
    done
}

notify_pending() {
    local count=0
    [[ -d "$REPORT_DIR" ]] || return 0
    shopt -s nullglob
    local reports=("$REPORT_DIR"/*.json)
    shopt -u nullglob
    count="${#reports[@]}"
    (( count > 0 )) || return 0
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send \
        'Awtarchy failure report pending' \
        "${count} sanitized failure report(s) are waiting. Run ~/.config/hypr/scripts/awtarchy_report_failure.sh pending to review." \
        >/dev/null 2>&1 || true
}

pending_reports() {
    [[ -d "$REPORT_DIR" ]] || return 0
    shopt -s nullglob
    local reports=("$REPORT_DIR"/*.json)
    shopt -u nullglob
    local path
    if (( ${#reports[@]} == 0 )); then
        printf 'No pending Awtarchy failure reports.\n'
        return 0
    fi
    for path in "${reports[@]}"; do
        prompt_report "$path"
    done
}

capture_failure() {
    local component="$1" stage="$2" error_code="$3" path=""
    path="$(write_pending_report "$component" "$stage" "$error_code")" || {
        log_error 'could not prepare the sanitized failure report; original failure is unchanged.'
        return 0
    }
    prompt_report "$path" || true
    return 0
}

main() {
    local command="${1:-}"
    case "$command" in
        capture)
            (( $# == 4 )) || { log_error 'capture requires component, stage, and error code.'; return 2; }
            capture_failure "$2" "$3" "$4"
            ;;
        send)
            (( $# == 2 )) || return 2
            submit_report "$2"
            ;;
        review)
            (( $# == 2 )) || return 2
            review_report "$2"
            ;;
        discard)
            (( $# == 2 )) || return 2
            discard_report "$2"
            ;;
        pending)
            (( $# == 1 )) || return 2
            pending_reports
            ;;
        notify-pending)
            (( $# == 1 )) || return 2
            notify_pending
            ;;
        *)
            log_error 'usage: awtarchy_report_failure.sh {capture COMPONENT STAGE ERROR|pending|send FILE|review FILE|discard FILE|notify-pending}'
            return 2
            ;;
    esac
}

main "$@"
