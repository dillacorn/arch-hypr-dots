#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$RUNTIME" ]] || fail "missing runtime"

gate_lib="${TMP}/lockscreen-gate.sh"
python3 - "$RUNTIME" "$gate_lib" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
start_marker = "runtime_catalog_has_exact_package() {\n"
end_marker = "retired_hyprlock_backup_path() {\n"
start = source.find(start_marker)
end = source.find(end_marker, start + 1)
if start < 0 or end < 0 or end <= start:
    raise SystemExit("could not extract production lockscreen retirement gate")
Path(sys.argv[2]).write_text(source[start:end], encoding="utf-8")
PY

make_clean_target() {
    local target="$1"
    mkdir -p \
        "$target/config/quickshell/awtarchy-lock" \
        "$target/config/hypr/scripts" \
        "$target/local/share/awtarchy"
    : >"$target/config/quickshell/awtarchy-lock/shell.qml"
    : >"$target/config/hypr/scripts/awtarchy_lock.sh"
    cat >"$target/local/share/awtarchy/awtarchy-runtime.sh" <<'EOF'
declare -a PKG_GROUPS=(
  "Window Management:hyprland hyprpaper hypridle quickshell"
)
EOF
}

run_gate() {
    local target="$1"
    bash -c 'set -euo pipefail; source "$1"; lockscreen_target_retires_hyprlock "$2"' \
        bash "$gate_lib" "$target"
}

target="${TMP}/target"
make_clean_target "$target"
run_gate "$target" \
    || fail "clean retired target was rejected by the lockscreen migration gate"

# Missing or malformed package-catalog structure must never be interpreted as
# proof that Hyprlock has been retired.
printf '%s\n' 'declare -a OPTIONAL_ARCH_PACKAGES=()' \
    >"$target/local/share/awtarchy/awtarchy-runtime.sh"
if run_gate "$target" >/dev/null 2>&1; then
    fail "lockscreen migration gate accepted a target with no PKG_GROUPS catalog"
fi

# A config scan error must fail closed. Simulate grep being unable to inspect the
# target rather than treating grep exit status 2 as equivalent to no matches.
make_clean_target "$target"
fakebin="${TMP}/fakebin"
mkdir -p "$fakebin"
cat >"${fakebin}/grep" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
chmod 0755 "${fakebin}/grep"
if PATH="${fakebin}:$PATH" run_gate "$target" >/dev/null 2>&1; then
    fail "lockscreen migration gate accepted a target after config scan failure"
fi

printf 'PASS: lockscreen migration target validation fails closed.\n'
