#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_REF="${TARGET_REF:?TARGET_REF is required}"
ARTIFACT_DIR="${ARTIFACT_DIR:-runtime-artifacts}"
WORK_DIR="${RUNNER_TEMP:-/tmp}/awtarchy-qemu-runtime"
SSH_PORT="${SSH_PORT:-2222}"
ARCH_IMAGE_URL="${ARCH_IMAGE_URL:-https://fastly.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2}"

rm -rf -- "$WORK_DIR"
mkdir -p "$WORK_DIR" "$ARTIFACT_DIR"

BASE_IMAGE="$WORK_DIR/Arch-Linux-x86_64-cloudimg.qcow2"
CHECKSUM_FILE="$WORK_DIR/Arch-Linux-x86_64-cloudimg.qcow2.SHA256"
GUEST_IMAGE="$WORK_DIR/guest.qcow2"
SEED_IMAGE="$WORK_DIR/seed.img"
SSH_KEY="$WORK_DIR/id_ed25519"
SERIAL_LOG="$ARTIFACT_DIR/qemu-serial.log"
QEMU_LOG="$ARTIFACT_DIR/qemu-host.log"
QEMU_PID_FILE="$WORK_DIR/qemu.pid"
USER_DATA="$WORK_DIR/user-data"
META_DATA="$WORK_DIR/meta-data"
FAILURE_CONTEXT="$ARTIFACT_DIR/failure-context.txt"

cleanup() {
    if [[ -f "$QEMU_PID_FILE" ]]; then
        qemu_pid="$(cat "$QEMU_PID_FILE" 2>/dev/null || true)"
        if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
            kill "$qemu_pid" >/dev/null 2>&1 || true
            for _ in $(seq 1 30); do
                kill -0 "$qemu_pid" 2>/dev/null || break
                sleep 0.2
            done
            kill -KILL "$qemu_pid" >/dev/null 2>&1 || true
        fi
    fi
}
trap cleanup EXIT

for command_name in curl qemu-img qemu-system-x86_64 cloud-localds ssh scp ssh-keygen tar; do
    command -v "$command_name" >/dev/null 2>&1 || {
        printf 'Missing host dependency: %s\n' "$command_name" >&2
        exit 1
    }
done

printf '%s\n' 'Downloading current official Arch Linux cloud image...'
curl --fail --location --retry 3 --retry-delay 2 \
    "$ARCH_IMAGE_URL" -o "$BASE_IMAGE"
curl --fail --location --retry 3 --retry-delay 2 \
    "${ARCH_IMAGE_URL}.SHA256" -o "$CHECKSUM_FILE"
(
    cd "$WORK_DIR"
    sha256sum --check "$(basename "$CHECKSUM_FILE")"
)

qemu-img create -q -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$GUEST_IMAGE"
qemu-img resize -q "$GUEST_IMAGE" 16G
ssh-keygen -q -t ed25519 -N '' -f "$SSH_KEY"
PUBLIC_KEY="$(cat "${SSH_KEY}.pub")"

cat >"$USER_DATA" <<EOF_CLOUD
#cloud-config
users:
  - name: arch
    gecos: Awtarchy Runtime Test
    groups: [wheel]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ${PUBLIC_KEY}
disable_root: true
ssh_pwauth: false
growpart:
  mode: auto
  devices: ['/']
resize_rootfs: true
EOF_CLOUD

cat >"$META_DATA" <<'EOF_META'
instance-id: awtarchy-qemu-runtime
local-hostname: awtarchy-runtime
EOF_META

cloud-localds "$SEED_IMAGE" "$USER_DATA" "$META_DATA"

: >"$SERIAL_LOG"
: >"$QEMU_LOG"
: >"$FAILURE_CONTEXT"

printf '%s\n' 'Starting QEMU Arch guest with virtio-gpu 2D device...'
qemu-system-x86_64 \
    -name awtarchy-runtime \
    -machine q35,accel=tcg \
    -cpu max \
    -smp 4 \
    -m 4096 \
    -drive "if=virtio,file=${GUEST_IMAGE},format=qcow2" \
    -drive "if=virtio,file=${SEED_IMAGE},format=raw,readonly=on" \
    -device virtio-vga,max_outputs=1 \
    -display none \
    -serial "file:${SERIAL_LOG}" \
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" \
    -device virtio-net-pci,netdev=net0 \
    -pidfile "$QEMU_PID_FILE" \
    -daemonize \
    >>"$QEMU_LOG" 2>&1

SSH_COMMON_OPTS=(
    -i "$SSH_KEY"
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=4
    -o ServerAliveInterval=5
    -o ServerAliveCountMax=2
)
SSH_OPTS=("${SSH_COMMON_OPTS[@]}" -p "$SSH_PORT")
SCP_OPTS=("${SSH_COMMON_OPTS[@]}" -P "$SSH_PORT")

vm_ssh() {
    ssh "${SSH_OPTS[@]}" arch@127.0.0.1 "$@"
}

qemu_alive() {
    local qemu_pid=""
    [[ -f "$QEMU_PID_FILE" ]] || return 1
    qemu_pid="$(cat "$QEMU_PID_FILE" 2>/dev/null || true)"
    [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null
}

collect_failure_evidence() {
    local stage="$1"
    local guest_probe="$WORK_DIR/guest-failure-probe.txt"

    {
        printf 'stage=%s\n' "$stage"
        date -u '+utc=%Y-%m-%dT%H:%M:%SZ'
        if qemu_alive; then
            printf 'qemu_alive=yes\n'
            ps -o pid,ppid,stat,etime,cmd -p "$(cat "$QEMU_PID_FILE")" 2>&1 || true
        else
            printf 'qemu_alive=no\n'
        fi
        printf '%s\n' '=== qemu host log ==='
        cat "$QEMU_LOG" 2>&1 || true
        printf '%s\n' '=== serial tail ==='
        tail -n 300 "$SERIAL_LOG" 2>&1 || true
    } >>"$FAILURE_CONTEXT" 2>&1

    if vm_ssh 'set +e
        mkdir -p /tmp/awtarchy-vm
        {
            echo "=== guest failure probe ==="
            date -u
            uname -a
            id
            echo "=== uptime ==="
            uptime
            echo "=== processes ==="
            ps -ef | grep -E "Hyprland|dbus-run-session|seatd" | grep -v grep
            echo "=== hypr runtime ==="
            find /run/user/1000/hypr -maxdepth 3 -type f -o -type s 2>/dev/null
            echo "=== dri ==="
            ls -la /dev/dri 2>/dev/null
            echo "=== input ==="
            ls -la /dev/input 2>/dev/null
            echo "=== seatd ==="
            systemctl --no-pager --full status seatd.service
            echo "=== kernel tail ==="
            sudo dmesg | tail -n 200
            echo "=== hyprland log ==="
            tail -n 300 /tmp/awtarchy-vm/hyprland.log 2>/dev/null
        } >/tmp/awtarchy-vm/failure-probe.txt 2>&1
        cp /tmp/awtarchy-vm/hyprland.log /tmp/awtarchy-vm/hyprland-failure.log 2>/dev/null
        exit 0' >"$guest_probe" 2>&1; then
        cat "$guest_probe" >>"$FAILURE_CONTEXT" 2>&1 || true
        scp "${SCP_OPTS[@]}" -r \
            arch@127.0.0.1:/tmp/awtarchy-vm/. \
            "$ARTIFACT_DIR/" >/dev/null 2>&1 || true
    else
        {
            printf '%s\n' '=== guest SSH failure ==='
            cat "$guest_probe" 2>&1 || true
        } >>"$FAILURE_CONTEXT"
    fi
}

printf '%s\n' 'Waiting for SSH/cloud-init...'
ssh_ready=0
for _ in $(seq 1 150); do
    if vm_ssh 'true' >/dev/null 2>&1; then
        ssh_ready=1
        break
    fi
    if ! qemu_alive; then
        printf '%s\n' 'QEMU exited before SSH became available.' >&2
        collect_failure_evidence 'qemu-exited-before-ssh'
        exit 1
    fi
    sleep 2
done
(( ssh_ready == 1 )) || {
    printf '%s\n' 'Timed out waiting for the Arch guest SSH service.' >&2
    collect_failure_evidence 'ssh-timeout'
    exit 1
}

vm_ssh 'timeout 90 cloud-init status --wait >/dev/null 2>&1 || true'

printf '%s\n' 'Installing runtime packages inside the real Arch guest...'
vm_ssh 'sudo pacman -Syu --noconfirm --needed hyprland quickshell mesa mesa-utils seatd jq dbus wl-clipboard cliphist grim foot qt6-wayland ttf-dejavu procps-ng >/tmp/awtarchy-pacman.log 2>&1'
vm_ssh 'sudo systemctl enable --now seatd.service; sudo usermod -aG seat,video,render,input arch; sudo install -d -o arch -g arch -m 0700 /run/user/1000'

printf '%s\n' 'Copying exact feature-branch Awtarchy config into the guest...'
tar -C . -czf - config/hypr config/quickshell \
    | ssh "${SSH_OPTS[@]}" arch@127.0.0.1 \
        'rm -rf ~/.config/hypr ~/.config/quickshell; mkdir -p ~/.config; tar -C ~ -xzf -; cp -a ~/config/hypr ~/.config/hypr; cp -a ~/config/quickshell ~/.config/quickshell; rm -rf ~/config'

vm_ssh 'id; test -S /run/seatd.sock; test -r ~/.config/hypr/hyprland.lua'

vm_ssh 'mkdir -p /tmp/awtarchy-vm; {
    echo "=== uname ==="; uname -a;
    echo "=== groups ==="; id;
    echo "=== /dev/dri ==="; ls -la /dev/dri || true;
    echo "=== DRM drivers ===";
    for node in /dev/dri/card* /dev/dri/renderD*; do
        test -e "$node" || continue;
        printf "%s: " "$node";
        udevadm info --query=property --name="$node" 2>/dev/null | grep -E "^(DRIVER|ID_PATH|DEVNAME)=" || true;
    done;
    echo "=== /dev/input ==="; ls -la /dev/input || true;
    echo "=== modules ==="; lsmod | grep -E "virtio_gpu|drm" || true;
    echo "=== seatd ==="; systemctl --no-pager --full status seatd.service || true;
} >/tmp/awtarchy-vm/hardware.txt 2>&1'
vm_ssh 'timeout 15 eglinfo -B >/tmp/awtarchy-vm/eglinfo.txt 2>&1 || true'

# Preserve pre-Hyprland evidence immediately. If compositor startup crashes or
# disconnects the guest, the GPU/seat/input baseline still reaches the artifact.
scp "${SCP_OPTS[@]}" \
    arch@127.0.0.1:/tmp/awtarchy-vm/hardware.txt \
    arch@127.0.0.1:/tmp/awtarchy-vm/eglinfo.txt \
    "$ARTIFACT_DIR/" >/dev/null 2>&1 || true

cat >"$WORK_DIR/start-hyprland.sh" <<'GUEST'
#!/usr/bin/env bash
set -Eeuo pipefail
export HOME=/home/arch
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_RUNTIME_DIR=/run/user/1000
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_DESKTOP=Hyprland
export LIBSEAT_BACKEND=seatd
export SEATD_VTBOUND=0
export AQ_TRACE=1
export AQ_NO_MODIFIERS=1
export HYPRLAND_NO_RT=1
export HYPRLAND_NO_SD_VARS=1
mkdir -p "$XDG_CACHE_HOME"
exec dbus-run-session -- Hyprland --config "$HOME/.config/hypr/hyprland.lua"
GUEST

scp "${SCP_OPTS[@]}" "$WORK_DIR/start-hyprland.sh" arch@127.0.0.1:/tmp/start-hyprland.sh >/dev/null
vm_ssh 'chmod 0755 /tmp/start-hyprland.sh; rm -rf /run/user/1000/hypr; setsid /tmp/start-hyprland.sh >/tmp/awtarchy-vm/hyprland.log 2>&1 </dev/null & echo $! >/tmp/awtarchy-vm/hyprland.pid'

printf '%s\n' 'Waiting for Hyprland inside the QEMU guest...'
hypr_ready=0
for _ in $(seq 1 60); do
    if vm_ssh 'lock=$(find /run/user/1000/hypr -mindepth 2 -maxdepth 2 -name hyprland.lock -print -quit 2>/dev/null); test -n "$lock" || exit 1; export HYPRLAND_INSTANCE_SIGNATURE=$(basename "$(dirname "$lock")"); timeout 3 hyprctl -j monitors | jq -e "length > 0" >/dev/null' >/dev/null 2>&1; then
        hypr_ready=1
        break
    fi
    if ! qemu_alive; then
        printf '%s\n' 'QEMU exited while Hyprland was starting.' >&2
        break
    fi
    if ! vm_ssh 'pgrep -x Hyprland >/dev/null 2>&1 || pgrep -f "Hyprland --config" >/dev/null 2>&1' >/dev/null 2>&1; then
        printf '%s\n' 'Hyprland exited before exposing a monitor in the QEMU guest.' >&2
        break
    fi
    sleep 1
done

if (( hypr_ready == 0 )); then
    collect_failure_evidence 'hyprland-not-ready'
    printf '%s\n' 'QEMU guest did not reach a usable Hyprland monitor.' >&2
    exit 1
fi

vm_ssh 'lock=$(find /run/user/1000/hypr -mindepth 2 -maxdepth 2 -name hyprland.lock -print -quit); export HYPRLAND_INSTANCE_SIGNATURE=$(basename "$(dirname "$lock")"); export WAYLAND_DISPLAY=$(sed -n "2p" "$lock"); export XDG_RUNTIME_DIR=/run/user/1000; hyprctl -j monitors >/tmp/awtarchy-vm/monitors.json; hyprctl configerrors >/tmp/awtarchy-vm/configerrors-initial.txt; test ! -s /tmp/awtarchy-vm/configerrors-initial.txt'

printf '%s\n' 'Starting Awtarchy Quickshell inside the QEMU guest...'
vm_ssh 'lock=$(find /run/user/1000/hypr -mindepth 2 -maxdepth 2 -name hyprland.lock -print -quit); export HYPRLAND_INSTANCE_SIGNATURE=$(basename "$(dirname "$lock")"); export WAYLAND_DISPLAY=$(sed -n "2p" "$lock"); export XDG_RUNTIME_DIR=/run/user/1000; export XDG_CONFIG_HOME=$HOME/.config; export XDG_CACHE_HOME=$HOME/.cache; ~/.config/hypr/scripts/quickshell.sh start >/tmp/awtarchy-vm/quickshell-manager.log 2>&1 || true'

qs_ready=0
for _ in $(seq 1 60); do
    if vm_ssh 'lock=$(find /run/user/1000/hypr -mindepth 2 -maxdepth 2 -name hyprland.lock -print -quit); export HYPRLAND_INSTANCE_SIGNATURE=$(basename "$(dirname "$lock")"); export WAYLAND_DISPLAY=$(sed -n "2p" "$lock"); export XDG_RUNTIME_DIR=/run/user/1000; timeout 2 qs -c awtarchy ipc call control ping >/dev/null' >/dev/null 2>&1; then
        qs_ready=1
        break
    fi
    sleep 1
done

if (( qs_ready == 0 )); then
    collect_failure_evidence 'quickshell-not-ready'
    printf '%s\n' 'Quickshell did not become IPC-ready in the QEMU guest.' >&2
    exit 1
fi

vm_ssh 'lock=$(find /run/user/1000/hypr -mindepth 2 -maxdepth 2 -name hyprland.lock -print -quit); export HYPRLAND_INSTANCE_SIGNATURE=$(basename "$(dirname "$lock")"); export WAYLAND_DISPLAY=$(sed -n "2p" "$lock"); export XDG_RUNTIME_DIR=/run/user/1000; export XDG_CONFIG_HOME=$HOME/.config; export XDG_CACHE_HOME=$HOME/.cache; timeout 5 ~/.config/hypr/scripts/quickshell_quick_settings_toggle.sh; sleep 1; timeout 5 qs -c awtarchy ipc call control ping >/dev/null; hyprctl -j layers >/tmp/awtarchy-vm/layers-quicksettings.json; timeout 5 grim /tmp/awtarchy-vm/quicksettings.png >/dev/null 2>&1 || true; cp ~/.cache/awtarchy/quickshell.log /tmp/awtarchy-vm/quickshell.log 2>/dev/null || true; hyprctl configerrors >/tmp/awtarchy-vm/configerrors-final.txt; test ! -s /tmp/awtarchy-vm/configerrors-final.txt'

vm_ssh 'if test -f /tmp/awtarchy-vm/quickshell.log && grep -Eiq "QQmlApplicationEngine failed|QQmlComponent: Component is not ready|Type .* unavailable|module .* is not installed|SyntaxError:|ReferenceError:" /tmp/awtarchy-vm/quickshell.log; then grep -Ein "QQmlApplicationEngine failed|QQmlComponent: Component is not ready|Type .* unavailable|module .* is not installed|SyntaxError:|ReferenceError:" /tmp/awtarchy-vm/quickshell.log >&2; exit 1; fi'

scp "${SCP_OPTS[@]}" -r arch@127.0.0.1:/tmp/awtarchy-vm/. "$ARTIFACT_DIR/" >/dev/null
printf 'PASS: real QEMU Arch guest reached Hyprland + Awtarchy Quickshell runtime for %s\n' "$TARGET_REF"
