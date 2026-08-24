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
    local value="${AWTARCHY_REPORT_CONFIG_VERSION_OVERRIDE:-}"
    if [[ -z "$value" ]]; then
        value="$(state_value tag "$CONFIG_VERSION_FILE" 2>/dev/null || true)"
    fi
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

report_basename_allowed() {
    case "$1" in
        quickshell--start--quickshell_not_ready.json|\
        quickshell--restart--quickshell_not_ready.json|\
        quickshell--restart_after_update--quickshell_not_ready.json|\
        resume_recovery--start--quickshell_start_failed.json|\
        resume_recovery--restart--quickshell_restart_failed.json|\
        resume_recovery--final_validation--expected_bars_missing.json)
            return 0
            ;;
        *) return 1 ;;
    esac
}

ensure_report_dir() {
    if [[ -e "$REPORT_DIR" || -L "$REPORT_DIR" ]]; then
        [[ -d "$REPORT_DIR" && ! -L "$REPORT_DIR" && -O "$REPORT_DIR" ]] || return 1
    else
        mkdir -p -- "$REPORT_DIR" || return 1
    fi
    chmod 0700 -- "$REPORT_DIR" || return 1
}

managed_report_path() {
    local path="$1" base=""
    base="${path##*/}"

    [[ -d "$REPORT_DIR" && ! -L "$REPORT_DIR" && -O "$REPORT_DIR" ]] || return 2
    report_basename_allowed "$base" || return 2
    [[ "$path" == "$REPORT_DIR/$base" ]] || return 2
    [[ -f "$path" && ! -L "$path" && -O "$path" ]] || return 2
}

validate_pending_payload() {
    local path="$1" size=0 component="" stage="" error_code="" expected=""
    managed_report_path "$path" || return 2
    command -v jq >/dev/null 2>&1 || return 127

    size="$(wc -c <"$path" 2>/dev/null || printf '0')"
    [[ "$size" =~ ^[0-9]+$ ]] || return 2
    (( size > 0 && size <= 32768 )) || return 2

    jq -e '
        def allowed: [
          "schema_version", "report_type", "component", "failure_stage", "error_code",
          "awtarchy_config_version", "awtarchy_command_revision", "hyprland_version",
          "quickshell_version", "kernel_version", "gpu_family", "context"
        ];
        def required: [
          "schema_version", "report_type", "component", "failure_stage", "error_code",
          "awtarchy_config_version", "awtarchy_command_revision", "hyprland_version",
          "quickshell_version", "kernel_version", "gpu_family"
        ];
        type == "object"
        and ((keys - allowed) | length == 0)
        and ((required - keys) | length == 0)
        and .schema_version == 1
        and .report_type == "failure"
        and (.component | type == "string")
        and (.component | test("^[a-z][a-z0-9_]{0,31}$"))
        and (.failure_stage | type == "string")
        and (.failure_stage | test("^[a-z][a-z0-9_]{0,47}$"))
        and (.error_code | type == "string")
        and (.error_code | test("^[a-z][a-z0-9_]{0,63}$"))
        and (.awtarchy_config_version | type == "string")
        and (.awtarchy_config_version | test("^[A-Za-z0-9._+@/-]{1,128}$"))
        and (.awtarchy_command_revision | type == "string")
        and (.awtarchy_command_revision | test("^(unknown|[0-9a-f]{40})$"))
        and (.hyprland_version | type == "string")
        and (.hyprland_version | test("^[A-Za-z0-9._+-]{1,96}$"))
        and (.quickshell_version | type == "string")
        and (.quickshell_version | test("^[A-Za-z0-9._+-]{1,96}$"))
        and (.kernel_version | type == "string")
        and (.kernel_version | test("^[A-Za-z0-9._+-]{1,96}$"))
        and (.gpu_family == "AMD" or .gpu_family == "Intel" or .gpu_family == "NVIDIA"
             or .gpu_family == "Other" or .gpu_family == "Unknown")
        and (
          (has("context") | not)
          or (
            (.context | type == "object")
            and (((.context | keys) - ["recovery_attempted", "recovery_succeeded"]) | length == 0)
            and ((.context | has("recovery_attempted") | not) or (.context.recovery_attempted | type == "boolean"))
            and ((.context | has("recovery_succeeded") | not) or (.context.recovery_succeeded | type == "boolean"))
          )
        )
    ' "$path" >/dev/null 2>&1 || return 2

    IFS=$'\t' read -r component stage error_code < <(
        jq -r '[.component, .failure_stage, .error_code] | @tsv' "$path"
    ) || return 2
    valid_failure "$component" "$stage" "$error_code" || return 2
    expected="$(report_path "$component" "$stage" "$error_code")"
    [[ "$path" == "$expected" ]] || return 2
}

write_pending_report() {
    local component="$1" stage="$2" error_code="$3"
    local path tmp config revision hyprland quickshell kernel gpu
    local recovery_attempted="${AWTARCHY_REPORT_RECOVERY_ATTEMPTED:-}"
    local recovery_succeeded="${AWTARCHY_REPORT_RECOVERY_SUCCEEDED:-}"

    valid_failure "$component" "$stage" "$error_code" || return 2
    command -v jq >/dev/null 2>&1 || return 127

    ensure_report_dir || return 1
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
    validate_pending_payload "$path" || return $?
    command -v curl >/dev/null 2>&1 || return 127

    response="$(curl -fsS \
        --connect-timeout 5 \
        --max-time 15 \
        -H 'Content-Type: application/json' \
        --data-binary "@${path}" \
        "$REPORT_ENDPOINT")" || return 1

    jq -e '.ok == true' <<<"$response" >/dev/null 2>&1 || return 1
    if jq -e '.pending == true' <<<"$response" >/dev/null 2>&1; then
        printf 'Awtarchy failure report is still processing. The sanitized report was kept locally for retry.\n'
        return 75
    fi
    jq -e '
        .ok == true
        and (.pending != true)
        and (.created == true or .deduplicated == true)
        and (.issue_number | type == "number")
        and (.issue_url | type == "string" and length > 0)
    ' <<<"$response" >/dev/null 2>&1 || return 1

    issue_url="$(jq -r '.issue_url' <<<"$response" 2>/dev/null || true)"
    rm -f -- "$path"
    printf 'Awtarchy failure report sent: %s\n' "$issue_url"
}

review_report() {
    local path="$1"
    managed_report_path "$path" || return 2
    command -v jq >/dev/null 2>&1 || return 127
    jq . "$path"
}

discard_report() {
    local path="$1" base=""
    base="${path##*/}"
    report_basename_allowed "$base" || return 2
    [[ "$path" == "$REPORT_DIR/$base" ]] || return 2
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        return 0
    fi
    managed_report_path "$path" || return 2
    rm -f -- "$path"
}

interactive_terminal() {
    [[ ${AWTARCHY_REPORT_NO_PROMPT:-0} != 1 ]] || return 1
    [[ -t 0 && -t 1 && -r /dev/tty && -w /dev/tty ]]
}

prompt_report() {
    local path="$1" choice="" rc=0
    interactive_terminal || return 0

    while true; do
        printf '\nAwtarchy detected a failure.\n' >/dev/tty
        printf 'A sanitized failure report can be sent to the Awtarchy project.\n' >/dev/tty
        printf 'If accepted, the sanitized report may become part of a public GitHub issue in the Awtarchy repository.\n' >/dev/tty
        printf 'It does not include your username, hostname, home path, raw logs, or a persistent machine ID.\n\n' >/dev/tty
        printf '  [S] Send report\n' >/dev/tty
        printf '  [R] Review report\n' >/dev/tty
        printf "  [N] Don't send\n" >/dev/tty
        printf 'Choose [N]: ' >/dev/tty
        IFS= read -r choice </dev/tty || return 0
        case "${choice,,}" in
            s|send)
                rc=0
                submit_report "$path" >/dev/tty 2>&1 || rc=$?
                if (( rc == 0 || rc == 75 )); then
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
                discard_report "$path" || true
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
    local count=0 path=""
    [[ -d "$REPORT_DIR" && ! -L "$REPORT_DIR" && -O "$REPORT_DIR" ]] || return 0
    shopt -s nullglob
    local reports=("$REPORT_DIR"/*.json)
    shopt -u nullglob
    for path in "${reports[@]}"; do
        managed_report_path "$path" || continue
        ((count += 1))
    done
    (( count > 0 )) || return 0
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send \
        'Awtarchy failure report pending' \
        "${count} sanitized failure report(s) are waiting. Run ~/.config/hypr/scripts/awtarchy_report_failure.sh pending to review." \
        >/dev/null 2>&1 || true
}

pending_reports() {
    [[ -d "$REPORT_DIR" && ! -L "$REPORT_DIR" && -O "$REPORT_DIR" ]] || return 0
    shopt -s nullglob
    local reports=("$REPORT_DIR"/*.json)
    shopt -u nullglob
    local path valid_count=0
    for path in "${reports[@]}"; do
        managed_report_path "$path" || continue
        ((valid_count += 1))
        prompt_report "$path"
    done
    if (( valid_count == 0 )); then
        printf 'No pending Awtarchy failure reports.\n'
    fi
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