#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-package-reconcile.sh"
HYPRLOCK_CONF="${ROOT}/config/hypr/hyprlock.conf"
HYPRIDLE="${ROOT}/config/hypr/hypridle.conf"
HYPRLAND="${ROOT}/config/hypr/hyprland.lua"
POWER_MENU="${ROOT}/config/quickshell/awtarchy/PowerMenu.qml"
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

require_order() {
    local file="$1" first="$2" second="$3" message="$4"
    python3 - "$file" "$first" "$second" "$message" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
first = sys.argv[2]
second = sys.argv[3]
message = sys.argv[4]
text = path.read_text(encoding="utf-8")
a = text.find(first)
b = text.find(second)
if a < 0 or b < 0 or a >= b:
    raise SystemExit(message)
PY
}

[[ -f "$RUNTIME" ]] || fail "missing runtime"
[[ -f "$RECONCILER" ]] || fail "missing package reconciler"

# This branch still uses Hyprlock in production. The migration plumbing must be
# dormant until the later production switch actually removes these requirements.
[[ -f "$HYPRLOCK_CONF" ]] || fail "foundation branch unexpectedly retired hyprlock.conf"
require_text "$RUNTIME" 'hyprpaper hyprlock hypridle' \
    'foundation branch unexpectedly removed hyprlock from the installer catalog'
require_text "$HYPRIDLE" 'lock_cmd = pidof hyprlock || hyprlock' \
    'foundation branch unexpectedly switched Hypridle'
require_text "$HYPRLAND" 'hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"), {})' \
    'foundation branch unexpectedly switched SUPER + L'
require_text "$POWER_MENU" 'command: "hyprlock"' \
    'foundation branch unexpectedly switched Power Menu Lock'

# Target-driven retirement is allowed only after the target itself proves that
# Hyprlock is no longer part of the production configuration.
require_text "$RUNTIME" 'lockscreen_target_retires_hyprlock()' \
    'runtime has no target-driven Hyprlock retirement gate'
require_text "$RUNTIME" 'config/quickshell/awtarchy-lock/shell.qml' \
    'retirement gate does not require the native lock shell'
require_text "$RUNTIME" 'config/hypr/scripts/awtarchy_lock.sh' \
    'retirement gate does not require the Awtarchy lock manager'
require_text "$RUNTIME" 'config/hypr/hyprlock.conf' \
    'retirement gate does not inspect the retired Hyprlock config'
require_text "$RUNTIME" 'migrate_retired_hyprlock_stage()' \
    'runtime has no Hyprlock retirement stage'
require_text "$RUNTIME" 'Git testing keeps Hyprlock installed as an emergency lock fallback.' \
    'Git-testing fallback contract is missing'
require_text "$RUNTIME" 'AWTARCHY_LOCKSCREEN_RETIRE_CONFIRMED=1' \
    'runtime does not explicitly authorize the package retirement helper'
require_text "$RUNTIME" 'hyprlock.conf.backup.' \
    'runtime does not preserve a remaining Hyprlock config before retirement'

# Installer retirement happens only after the normal config/package setup. Stable
# updater retirement happens after rollback-capable legacy cleanup and before the
# new baseline is committed. Current target gating keeps both calls as no-ops.
require_order "$RUNTIME" \
    '  remove_legacy_shell_packages_stage' \
    '  migrate_retired_hyprlock_stage "$REPO_DIR"' \
    'installer Hyprlock retirement is not ordered after normal shell cleanup'
require_order "$RUNTIME" \
    '  remove_quickshell_update_legacy_packages' \
    '  migrate_retired_hyprlock_stage "$repo_dir"' \
    'stable updater Hyprlock retirement is not ordered after rollback-capable cleanup'
require_order "$RUNTIME" \
    '  migrate_retired_hyprlock_stage "$repo_dir"' \
    '  commit_baseline "$target_home" "$source_label" "$active_theme"' \
    'stable updater commits the new baseline before Hyprlock retirement'

# Package removal itself belongs to the existing reconciler. It must require an
# explicit confirmed target, refuse a runtime that still catalogs Hyprlock, and
# remove only an Awtarchy-owned installation.
require_text "$RECONCILER" '--migrate-lockscreen-retirement' \
    'package reconciler has no lockscreen retirement mode'
require_text "$RECONCILER" 'AWTARCHY_LOCKSCREEN_RETIRE_CONFIRMED' \
    'package reconciler does not require explicit retirement confirmation'
require_text "$RECONCILER" 'managed_package hyprlock' \
    'package reconciler does not ownership-gate Hyprlock removal'
require_text "$RECONCILER" 'pacman -Rns --noconfirm hyprlock' \
    'package reconciler does not use exact Hyprlock package removal'
require_text "$RECONCILER" 'forget_managed_packages hyprlock' \
    'package reconciler does not clear retired Hyprlock ownership state'

fakebin="${TMP}/fakebin"
mkdir -p "$fakebin"

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
        grep -Fxq -- "$pkg" "$state"
        [[ $action == -Qq ]] && printf '%s\n' "$pkg"
        ;;
    -Rns)
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

retired_runtime="${TMP}/runtime-retired.sh"
cat >"$retired_runtime" <<'EOF'
declare -a PKG_GROUPS=(
  "Window Management:hyprland hyprpaper hypridle quickshell"
)
EOF

active_runtime="${TMP}/runtime-active.sh"
cat >"$active_runtime" <<'EOF'
declare -a PKG_GROUPS=(
  "Window Management:hyprland hyprpaper hyprlock hypridle quickshell"
)
EOF

run_retirement() {
    local runtime="$1" state="$2" managed="$3"
    PATH="${fakebin}:$PATH" \
    AWTARCHY_RUNTIME="$runtime" \
    AWTARCHY_MANAGED_PACKAGES_FILE="$managed" \
    AWTARCHY_TEST_PACKAGE_STATE="$state" \
    AWTARCHY_LOCKSCREEN_RETIRE_CONFIRMED=1 \
        bash "$RECONCILER" --migrate-lockscreen-retirement
}

state="${TMP}/packages"
managed="${TMP}/managed-packages"
printf '%s\n' hyprlock quickshell >"$state"
printf '%s\n' hyprlock quickshell >"$managed"
run_retirement "$retired_runtime" "$state" "$managed" >/dev/null \
    || fail 'confirmed retired target could not remove Awtarchy-owned Hyprlock'
! grep -Fxq hyprlock "$state" \
    || fail 'Awtarchy-owned Hyprlock remained installed after confirmed retirement'
! grep -Fxq hyprlock "$managed" \
    || fail 'retired Hyprlock remained in the managed-package ledger'

printf '%s\n' hyprlock quickshell >"$state"
printf '%s\n' quickshell >"$managed"
run_retirement "$retired_runtime" "$state" "$managed" >/dev/null \
    || fail 'unowned Hyprlock retirement check failed'
grep -Fxq hyprlock "$state" \
    || fail 'unowned Hyprlock was removed automatically'

printf '%s\n' hyprlock quickshell >"$state"
printf '%s\n' hyprlock quickshell >"$managed"
if run_retirement "$active_runtime" "$state" "$managed" >/dev/null 2>&1; then
    fail 'retirement helper accepted a target runtime that still requires Hyprlock'
fi
grep -Fxq hyprlock "$state" \
    || fail 'Hyprlock changed after active-target retirement refusal'

printf '%s\n' hyprlock quickshell >"$state"
printf '%s\n' hyprlock quickshell >"$managed"
if PATH="${fakebin}:$PATH" \
   AWTARCHY_RUNTIME="$retired_runtime" \
   AWTARCHY_MANAGED_PACKAGES_FILE="$managed" \
   AWTARCHY_TEST_PACKAGE_STATE="$state" \
       bash "$RECONCILER" --migrate-lockscreen-retirement >/dev/null 2>&1; then
    fail 'retirement helper ran without explicit target confirmation'
fi
grep -Fxq hyprlock "$state" \
    || fail 'Hyprlock changed without explicit target confirmation'

printf 'PASS: Quickshell lockscreen install/update migration contracts\n'
