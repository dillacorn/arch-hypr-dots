#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HYPRLAND="${ROOT}/config/hypr/hyprland.lua"
POWER_MENU="${ROOT}/config/quickshell/awtarchy/PowerMenu.qml"
MIGRATOR="${ROOT}/local/share/awtarchy/awtarchy-lockscreen-hyprland-migrate.py"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-package-reconcile.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

reject_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

# Awtarchy's intended manual lock path is the existing power menu:
# SUPER+P, then L. SUPER+L remains available to the normal movement bindings.
reject_text "$HYPRLAND" \
    'hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})' \
    'native locker still steals SUPER+L instead of using SUPER+P then L'
require_text "$HYPRLAND" \
    'hl.bind("SUPER + P", hl.dsp.exec_cmd(power_menu), {})' \
    'power menu bind is missing after lockscreen cutover'
require_text "$POWER_MENU" \
    '{ label: "", text: "Lock (L)", key: "l", command: "~/.config/hypr/scripts/awtarchy_lock.sh lock && ~/.config/hypr/scripts/awtarchy_lock.sh wait-secure 5", closeAfterSuccess: true }' \
    'power menu L action does not keep coverage until the native locker is secure'
reject_text "$MIGRATOR" \
    'NEW_BIND = '\''hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})'\''' \
    'personalized Hyprland migration still creates a direct SUPER+L lock bind'

# Once the updater has confirmed that the target no longer uses Hyprlock,
# any installed Hyprlock package is obsolete and must be retired automatically.
reject_text "$RECONCILER" \
    "confirm_yes_no 'Hyprlock is no longer used by Awtarchy but was not recorded as Awtarchy-owned. Remove it now?'" \
    'Hyprlock retirement still prompts the user'
reject_text "$RECONCILER" \
    'AWTARCHY_LOCKSCREEN_RETIRE_UNOWNED_CONFIRMED' \
    'Hyprlock retirement still depends on a one-time confirmation override'

fakebin="${TMP}/fakebin"
mkdir -p -- "$fakebin"

cat >"${fakebin}/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == -- ]] && shift
exec "$@"
EOF

cat >"${fakebin}/pacman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${AWTARCHY_TEST_PACKAGE_STATE:?}"
action="${1:-}"
shift || true
case "$action" in
    -Q|-Qq)
        if (( $# == 0 )); then
            cat "$state"
            exit 0
        fi
        pkg="$1"
        grep -Fxq -- "$pkg" "$state" || exit 1
        if [[ $action == -Qq ]]; then
            printf '%s\n' "$pkg"
        fi
        # A successful pacman -Q lookup must not inherit the false -Qq test.
        exit 0
        ;;
    -R)
        [[ ${1:-} == --noconfirm ]] && shift
        [[ ${1:-} == hyprlock && $# == 1 ]] || exit 64
        grep -Fxq hyprlock "$state" || exit 1
        grep -Fxv hyprlock "$state" >"${state}.tmp" || true
        mv -f -- "${state}.tmp" "$state"
        ;;
    *)
        exit 65
        ;;
esac
EOF
chmod 0755 "${fakebin}/sudo" "${fakebin}/pacman"

runtime="${TMP}/runtime.sh"
cat >"$runtime" <<'EOF'
declare -a PKG_GROUPS=(
  "Window Management:hyprland hyprpaper hypridle quickshell"
)
EOF

state="${TMP}/packages"
managed="${TMP}/managed-packages"
printf '%s\n' hyprlock quickshell >"$state"
printf '%s\n' quickshell >"$managed"

PATH="${fakebin}:$PATH" \
AWTARCHY_RUNTIME="$runtime" \
AWTARCHY_MANAGED_PACKAGES_FILE="$managed" \
AWTARCHY_TEST_PACKAGE_STATE="$state" \
AWTARCHY_LOCKSCREEN_RETIRE_CONFIRMED=1 \
    bash "$RECONCILER" --migrate-lockscreen-retirement >/dev/null \
    || fail 'automatic legacy Hyprlock retirement failed'

if grep -Fxq hyprlock "$state"; then
    fail 'legacy Hyprlock was not removed automatically'
fi

printf 'PASS: lockscreen user cutover contracts\n'
