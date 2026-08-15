#!/usr/bin/bash
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin

# usb_refresh_fixer.sh
#
# Use lsusb yourself.
#
# Example:
#   lsusb
#   Bus 005 Device 004: ID 20b1:3008 XMOS Ltd iFi (by AMR) HD USB Audio
#
# First map the working device:
#   ./usb_refresh_fixer.sh map 20b1:3008 ifi
#
# Later refresh it:
#   ./usb_refresh_fixer.sh refresh ifi
#
# Refresh an audio device without forcing default sink:
#   ./usb_refresh_fixer.sh refresh-audio ifi
#
# Refresh an audio device and force it as default sink:
#   ./usb_refresh_fixer.sh refresh-audio-default ifi
#
# Force the mapped audio device as default sink without refresh:
#   ./usb_refresh_fixer.sh audio-default ifi
#
# Refresh all mapped devices:
#   ./usb_refresh_fixer.sh

PRIVILEGED_HELPER="/usr/local/libexec/awtarchy/usb-refresh-fixer"
CONFIG_DIR="/etc/usb_refresh_fixer"
RUNTIME_DIR="/run/awtarchy/usb-refresh"
RESET_DELAY_SECONDS=2
POST_PORT_REBIND_WAIT_SECONDS=2
POST_CONTROLLER_REBIND_WAIT_SECONDS=3

AUDIO_WAIT_SECS=30
AUDIO_POLL_SECS=0.20
AUDIO_STABLE_POLLS=5

SELF_PATH="$(readlink -f "$0")"
RUN_USER="${SUDO_USER:-${USER:-$(id -un)}}"

log() { printf '[usb_refresh_fixer] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

readf() {
    local f="$1"
    [[ -r "$f" ]] || return 1
    tr -d '\n' < "$f"
}

validate_id() {
    [[ "$1" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$ ]] || die "invalid USB ID: $1"
}

validate_mapping_name() {
    local name="$1"
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] \
        || die "invalid mapping name: $name"
}

get_run_user_uid() {
    id -u "$RUN_USER" 2>/dev/null
}

get_run_user_home() {
    getent passwd "$RUN_USER" | awk -F: '{print $6}'
}

user_session_cmd() {
    local uid home
    uid="$(get_run_user_uid)" || return 1
    home="$(get_run_user_home)" || return 1
    [[ -S "/run/user/$uid/bus" ]] || return 1

    /usr/bin/runuser -u "$RUN_USER" -- env \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        HOME="$home" \
        PATH="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}" \
        "$@"
}

enter_privileged_helper() {
    if [[ "$SELF_PATH" != "$PRIVILEGED_HELPER" ]]; then
        [[ -x "$PRIVILEGED_HELPER" ]] \
            || die "root-owned helper is missing; run the Awtarchy installer once to repair it"
        if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
            exec "$PRIVILEGED_HELPER" "$@"
        elif [[ -t 0 || -t 1 ]]; then
            exec /usr/bin/sudo "$PRIVILEGED_HELPER" "$@"
        else
            exec /usr/bin/sudo -n "$PRIVILEGED_HELPER" "$@" \
                || die "USB refresh authorization is missing; run the Awtarchy installer once"
        fi
    fi

    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "the root-owned USB helper must run as root"
}

run_with_refresh_lock() {
    local uid lock_file active_file lock_fd rc=0

    uid="$(get_run_user_uid)" || die "could not resolve user: $RUN_USER"
    install -d -m 0755 -o root -g root /run/awtarchy "$RUNTIME_DIR"
    [[ ! -L /run/awtarchy && ! -L "$RUNTIME_DIR" ]] \
        || die "USB refresh runtime directory must not be a symbolic link"

    lock_file="${RUNTIME_DIR}/${uid}.lock"
    active_file="${RUNTIME_DIR}/${uid}.active"
    exec {lock_fd}>"$lock_file"
    chmod 0644 "$lock_file"
    flock -x "$lock_fd"
    printf '%s\n' "$$" >"$active_file"
    chmod 0644 "$active_file"
    trap 'rm -f -- "$active_file"' EXIT INT TERM HUP

    "$@" || rc=$?

    rm -f -- "$active_file"
    trap - EXIT INT TERM HUP
    exec {lock_fd}>&-
    return "$rc"
}

find_device_sysfs_by_id() {
    local target="${1,,}"
    local d vid pid cur

    for d in /sys/bus/usb/devices/*; do
        [[ -d "$d" ]] || continue
        [[ -f "$d/idVendor" && -f "$d/idProduct" ]] || continue

        vid="$(readf "$d/idVendor" 2>/dev/null || true)"
        pid="$(readf "$d/idProduct" 2>/dev/null || true)"
        [[ -n "$vid" && -n "$pid" ]] || continue

        cur="${vid,,}:${pid,,}"
        if [[ "$cur" == "$target" ]]; then
            basename "$d"
            return 0
        fi
    done

    return 1
}

find_controller_bdf_from_path() {
    local usb_path="$1"
    local rp part last=""

    rp="$(readlink -f "/sys/bus/usb/devices/$usb_path")" || return 1

    while IFS= read -r part; do
        [[ "$part" =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]$ ]] && last="$part"
    done < <(tr '/' '\n' <<< "$rp")

    [[ -n "$last" ]] || return 1
    printf '%s\n' "$last"
}

get_pci_driver_for_bdf() {
    local bdf="$1"
    local drv

    drv="$(readlink -f "/sys/bus/pci/devices/$bdf/driver" 2>/dev/null || true)"
    [[ -n "$drv" ]] || return 1
    basename "$drv"
}

device_present_by_id() {
    local want="${1,,}"
    local d vid pid cur

    for d in /sys/bus/usb/devices/*; do
        [[ -f "$d/idVendor" && -f "$d/idProduct" ]] || continue
        vid="$(readf "$d/idVendor" 2>/dev/null || true)"
        pid="$(readf "$d/idProduct" 2>/dev/null || true)"
        [[ -n "$vid" && -n "$pid" ]] || continue
        cur="${vid,,}:${pid,,}"
        [[ "$cur" == "$want" ]] && return 0
    done

    return 1
}

write_config() {
    local name="$1"
    local expected_id="$2"
    local usb_port_path="$3"
    local host_controller_bdf="$4"

    local destination="${CONFIG_DIR}/${name}.conf" temporary=""

    validate_mapping_name "$name"
    validate_id "$expected_id"
    [[ "$usb_port_path" =~ ^(usb[0-9]+|[0-9]+-[0-9]+([.][0-9]+)*)$ ]] \
        || die "invalid USB port path: $usb_port_path"
    [[ "$host_controller_bdf" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$ ]] \
        || die "invalid host controller BDF: $host_controller_bdf"

    install -d -m 0755 -o root -g root "$CONFIG_DIR"
    [[ ! -L "$CONFIG_DIR" ]] || die "USB mapping directory must not be a symbolic link"
    temporary="$(mktemp "${CONFIG_DIR}/.${name}.conf.XXXXXX")"
    {
        printf 'EXPECTED_ID=%s\n' "${expected_id,,}"
        printf 'USB_PORT_PATH=%s\n' "$usb_port_path"
        printf 'HOST_CONTROLLER_BDF=%s\n' "${host_controller_bdf,,}"
        printf 'RESET_DELAY_SECONDS=%s\n' "$RESET_DELAY_SECONDS"
    } >"$temporary"
    chmod 0644 "$temporary"
    chown root:root "$temporary"
    mv -Tf -- "$temporary" "$destination"
}

load_config() {
    local name="$1"
    local cfg="${CONFIG_DIR}/${name}.conf"
    local line key value mode owner
    local expected_seen=0 port_seen=0 controller_seen=0 delay_seen=0

    validate_mapping_name "$name"
    [[ -f "$cfg" && ! -L "$cfg" && -r "$cfg" ]] || die "missing or unsafe config: $cfg"
    owner="$(stat -c %u -- "$cfg")" || die "could not inspect config owner: $cfg"
    mode="$(stat -c %a -- "$cfg")" || die "could not inspect config mode: $cfg"
    [[ "$owner" == 0 ]] || die "USB config must be owned by root: $cfg"
    (( (8#$mode & 8#022) == 0 )) || die "USB config must not be group/world writable: $cfg"

    EXPECTED_ID=""
    USB_PORT_PATH=""
    HOST_CONTROLLER_BDF=""
    RESET_DELAY_SECONDS=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -n "$line" && "$line" != \#* ]] || continue
        [[ "$line" == *=* ]] || die "invalid USB config line in $cfg"
        key="${line%%=*}"
        value="${line#*=}"
        case "$key" in
            EXPECTED_ID)
                (( expected_seen == 0 )) || die "duplicate EXPECTED_ID in $cfg"
                EXPECTED_ID="$value"
                expected_seen=1
                ;;
            USB_PORT_PATH)
                (( port_seen == 0 )) || die "duplicate USB_PORT_PATH in $cfg"
                USB_PORT_PATH="$value"
                port_seen=1
                ;;
            HOST_CONTROLLER_BDF)
                (( controller_seen == 0 )) || die "duplicate HOST_CONTROLLER_BDF in $cfg"
                HOST_CONTROLLER_BDF="$value"
                controller_seen=1
                ;;
            RESET_DELAY_SECONDS)
                (( delay_seen == 0 )) || die "duplicate RESET_DELAY_SECONDS in $cfg"
                RESET_DELAY_SECONDS="$value"
                delay_seen=1
                ;;
            *)
                die "unexpected USB config key in $cfg: $key"
                ;;
        esac
    done <"$cfg"

    (( expected_seen && port_seen && controller_seen && delay_seen )) \
        || die "USB config is missing required values: $cfg"
    validate_id "$EXPECTED_ID"
    [[ "$USB_PORT_PATH" =~ ^(usb[0-9]+|[0-9]+-[0-9]+([.][0-9]+)*)$ ]] \
        || die "USB_PORT_PATH invalid in $cfg"
    [[ "$HOST_CONTROLLER_BDF" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$ ]] \
        || die "HOST_CONTROLLER_BDF invalid in $cfg"
    [[ "$RESET_DELAY_SECONDS" =~ ^[0-9]+$ ]] \
        || die "RESET_DELAY_SECONDS invalid in $cfg"
    (( RESET_DELAY_SECONDS <= 60 )) \
        || die "RESET_DELAY_SECONDS is too large in $cfg"
}

rebind_usb_port() {
    local usb_port_path="$1"
    local delay="$2"

    [[ -e "/sys/bus/usb/devices/$usb_port_path" ]] || return 1

    log "rebinding USB port path: $usb_port_path"
    printf '%s' "$usb_port_path" > /sys/bus/usb/drivers/usb/unbind
    sleep "$delay"
    printf '%s' "$usb_port_path" > /sys/bus/usb/drivers/usb/bind
    udevadm settle --timeout=10 || true
    return 0
}

rebind_usb_controller() {
    local bdf="$1"
    local delay="$2"
    local driver

    [[ -e "/sys/bus/pci/devices/$bdf" ]] || die "missing PCI device: $bdf"
    driver="$(get_pci_driver_for_bdf "$bdf")" || die "could not resolve PCI driver for $bdf"

    log "rebinding host controller: $bdf ($driver)"
    printf '%s' "$bdf" > "/sys/bus/pci/drivers/$driver/unbind"
    sleep "$delay"
    printf '%s' "$bdf" > "/sys/bus/pci/drivers/$driver/bind"
    udevadm settle --timeout=15 || true
}

audio_prereqs_ok() {
    [[ -x /usr/bin/runuser ]] || return 1
    command -v wpctl >/dev/null 2>&1 || return 1
    command -v pw-dump >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1
    user_session_cmd true >/dev/null 2>&1 || return 1
}

wait_for_audio_prereqs() {
    local end
    end=$(( $(date +%s) + AUDIO_WAIT_SECS ))

    while (( $(date +%s) < end )); do
        if audio_prereqs_ok; then
            return 0
        fi
        sleep "$AUDIO_POLL_SECS"
    done

    return 1
}

audio_default_sink_name() {
    user_session_cmd wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'"' '
        /node\.name =/        { print $2; found=1; exit }
        /node\.nick =/        { if (nick == "") nick=$2 }
        /node\.description =/ { if (desc == "") desc=$2 }
        END {
            if (!found) {
                if (nick != "") print nick
                else if (desc != "") print desc
            }
        }
    '
}

audio_sink_name_from_id() {
    local id="$1"
    [[ -n "$id" ]] || return 1

    user_session_cmd wpctl inspect "$id" 2>/dev/null | awk -F'"' '
        /node\.name =/        { print $2; found=1; exit }
        /node\.nick =/        { if (nick == "") nick=$2 }
        /node\.description =/ { if (desc == "") desc=$2 }
        END {
            if (!found) {
                if (nick != "") print nick
                else if (desc != "") print desc
            }
        }
    '
}

audio_default_sink_matches_name() {
    local name="$1"
    local want="${EXPECTED_ID,,}"

    [[ -n "$name" ]] || return 1
    [[ -n "$want" ]] || return 1

    user_session_cmd pw-dump 2>/dev/null | jq -e -r --arg name "$name" --arg expected_id "$want" '
        def norm: ascii_downcase;
        def split_id: $expected_id | split(":");
        .[]
        | select(.type == "PipeWire:Interface:Node")
        | select(.info.props["media.class"] == "Audio/Sink")
        | select(
            (.info.props["node.name"] == $name)
            or (.info.props["node.description"] == $name)
            or (.info.props["node.nick"] == $name)
        )
        | select(
            (
                (((.info.props["device.vendor.id"] // "") | norm) == (split_id[0]))
                and
                (((.info.props["device.product.id"] // "") | norm) == (split_id[1]))
            )
            or
            ((((.info.props["device.vendor.id"] // "") | norm) + ":" + ((.info.props["device.product.id"] // "") | norm)) == $expected_id)
            or
            (((.info.props["device.bus-id"] // "") | norm) | contains($expected_id))
        )
    ' >/dev/null
}

audio_find_sink_id_for_name() {
    local name="$1"
    local id=""

    load_config "$name"
    audio_prereqs_ok || return 1

    id="$(user_session_cmd pw-dump 2>/dev/null | jq -r --arg expected_id "${EXPECTED_ID,,}" '
        def norm: ascii_downcase;
        def split_id: $expected_id | split(":");
        .[]
        | select(.type == "PipeWire:Interface:Node")
        | select(.info.props["media.class"] == "Audio/Sink")
        | select(
            (
                (((.info.props["device.vendor.id"] // "") | norm) == (split_id[0]))
                and
                (((.info.props["device.product.id"] // "") | norm) == (split_id[1]))
            )
            or
            ((((.info.props["device.vendor.id"] // "") | norm) + ":" + ((.info.props["device.product.id"] // "") | norm)) == $expected_id)
            or
            (((.info.props["device.bus-id"] // "") | norm) | contains($expected_id))
        )
        | .id
    ' | head -n1 || true)"

    [[ -n "$id" ]] || return 1
    printf '%s\n' "$id"
}

wait_for_mapped_sink_id() {
    local name="$1"
    local end id=""

    end=$(( $(date +%s) + AUDIO_WAIT_SECS ))
    while (( $(date +%s) < end )); do
        id="$(audio_find_sink_id_for_name "$name" || true)"
        if [[ -n "$id" ]]; then
            printf '%s\n' "$id"
            return 0
        fi
        sleep "$AUDIO_POLL_SECS"
    done

    return 1
}

cmd_map() {
    local id="${1,,}"
    local name="$2"
    local usb_port_path host_controller_bdf

    validate_id "$id"
    validate_mapping_name "$name"

    usb_port_path="$(find_device_sysfs_by_id "$id")" || die "device $id is not currently detected. map it while it is working."
    host_controller_bdf="$(find_controller_bdf_from_path "$usb_port_path")" || die "could not resolve PCI controller for $usb_port_path"

    write_config "$name" "$id" "$usb_port_path" "$host_controller_bdf"

    log "mapped $name"
    log "  id: $id"
    log "  usb path: $usb_port_path"
    log "  controller: $host_controller_bdf"
}

cmd_refresh() {
    local name="$1"
    load_config "$name"

    log "refreshing $name"
    log "  id: $EXPECTED_ID"
    log "  usb path: $USB_PORT_PATH"
    log "  controller: $HOST_CONTROLLER_BDF"

    if rebind_usb_port "$USB_PORT_PATH" "$RESET_DELAY_SECONDS"; then
        sleep "$POST_PORT_REBIND_WAIT_SECONDS"
        if device_present_by_id "$EXPECTED_ID"; then
            log "success: $name came back after port rebind"
            return 0
        fi
        log "$name still missing after port rebind, trying controller fallback"
    else
        log "usb path missing, trying controller fallback"
    fi

    rebind_usb_controller "$HOST_CONTROLLER_BDF" "$RESET_DELAY_SECONDS"
    sleep "$POST_CONTROLLER_REBIND_WAIT_SECONDS"

    if device_present_by_id "$EXPECTED_ID"; then
        log "success: $name came back after controller rebind"
        return 0
    fi

    die "$name is still missing after all reset attempts"
}

cmd_audio_default() {
    local name="$1"
    local id="" target_name="" current="" last="" count=0
    local end

    load_config "$name"
    wait_for_audio_prereqs || die "audio restore prerequisites missing after waiting: need runuser, wpctl, pw-dump, jq, and a live user session bus"

    end=$(( $(date +%s) + AUDIO_WAIT_SECS ))
    while (( $(date +%s) < end )); do
        if [[ -z "$id" ]]; then
            id="$(audio_find_sink_id_for_name "$name" || true)"
            if [[ -n "$id" && -z "$target_name" ]]; then
                target_name="$(audio_sink_name_from_id "$id" || true)"
            fi
        fi

        if [[ -n "$id" ]]; then
            user_session_cmd wpctl set-default "$id" >/dev/null 2>&1 || true
        fi

        current="$(audio_default_sink_name || true)"

        if [[ -n "$current" ]] && (
            [[ -n "$target_name" && "$current" == "$target_name" ]] ||
            audio_default_sink_matches_name "$current"
        ); then
            if [[ "$current" == "$last" ]]; then
                ((count++))
            else
                last="$current"
                count=1
            fi

            if (( count >= AUDIO_STABLE_POLLS )); then
                log "set mapped audio device as default sink: $name (${target_name:-$current})"
                return 0
            fi
        else
            last=""
            count=0

            id="$(audio_find_sink_id_for_name "$name" || true)"
            if [[ -n "$id" ]]; then
                target_name="$(audio_sink_name_from_id "$id" || true)"
            fi
        fi

        sleep "$AUDIO_POLL_SECS"
    done

    die "could not set mapped audio device as default sink: $name"
}

cmd_refresh_audio() {
    local name="$1"
    cmd_refresh "$name"
    wait_for_audio_prereqs || die "audio prerequisites missing after refresh: need runuser, wpctl, pw-dump, jq, and a live user session bus"
    wait_for_mapped_sink_id "$name" >/dev/null || die "mapped audio sink did not appear after refresh: $name"
    log "mapped audio sink is present after refresh: $name"
}

cmd_refresh_audio_default() {
    local name="$1"
    cmd_refresh "$name"
    cmd_audio_default "$name"
}

cmd_refresh_all() {
    local cfg name rc=0

    shopt -s nullglob
    for cfg in "$CONFIG_DIR"/*.conf; do
        name="$(basename "$cfg" .conf)"
        cmd_refresh "$name" || rc=1
    done
    shopt -u nullglob

    return "$rc"
}

usage() {
    cat <<'EOF'
Usage:
  usb_refresh_fixer.sh map <vendor:product> <name>
  usb_refresh_fixer.sh refresh <name>
  usb_refresh_fixer.sh refresh-audio <name>
  usb_refresh_fixer.sh refresh-audio-default <name>
  usb_refresh_fixer.sh audio-default <name>
  usb_refresh_fixer.sh

Examples:
  lsusb
  ./usb_refresh_fixer.sh map 20b1:3008 ifi
  ./usb_refresh_fixer.sh refresh ifi
  ./usb_refresh_fixer.sh refresh-audio ifi
  ./usb_refresh_fixer.sh refresh-audio-default ifi
  ./usb_refresh_fixer.sh audio-default ifi
  ./usb_refresh_fixer.sh
EOF
}

main() {
    if [[ $# -eq 0 ]]; then
        set -- refresh-all
    fi

    enter_privileged_helper "$@"

    case "$1" in
        map)
            [[ $# -eq 3 ]] || { usage; exit 1; }
            cmd_map "$2" "$3"
            ;;
        refresh)
            [[ $# -eq 2 ]] || { usage; exit 1; }
            run_with_refresh_lock cmd_refresh "$2"
            ;;
        refresh-audio)
            [[ $# -eq 2 ]] || { usage; exit 1; }
            run_with_refresh_lock cmd_refresh_audio "$2"
            ;;
        refresh-audio-default)
            [[ $# -eq 2 ]] || { usage; exit 1; }
            run_with_refresh_lock cmd_refresh "$2"
            cmd_audio_default "$2"
            ;;
        audio-default)
            [[ $# -eq 2 ]] || { usage; exit 1; }
            cmd_audio_default "$2"
            ;;
        refresh-all)
            [[ $# -eq 1 ]] || { usage; exit 1; }
            run_with_refresh_lock cmd_refresh_all
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
