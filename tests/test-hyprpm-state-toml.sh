#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
AUTO_RELOAD="${ROOT}/config/hypr/scripts/hyprpm-auto-reload.sh"
TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

fakebin="$TMPD/bin"
home="$TMPD/home"
runtime="$TMPD/runtime"
hyprpm_state="$TMPD/hyprpm-state"
hyprpm_log="$TMPD/hyprpm.log"
loaded_marker="$TMPD/hyprbars-loaded"
mkdir -p \
  "$fakebin" \
  "$home/.local/state/awtarchy" \
  "$runtime" \
  "$hyprpm_state/hyprland-plugins" \
  "$hyprpm_state/headersRoot/include/hyprland/src" \
  "$hyprpm_state/headersRoot/share/pkgconfig"

cat >"$hyprpm_state/state.toml" <<'EOF_STATE'
[state]
dont_warn_install = true
hash = 'running-commit_aq_0.14_hu_0.14_hg_0.5_hc_0.1_hlg_0.6'
EOF_STATE

cat >"$hyprpm_state/hyprland-plugins/state.toml" <<'EOF_PLUGIN'
[repository]
name = "hyprland-plugins"
author = "hyprwm"
url = "https://github.com/hyprwm/hyprland-plugins"

[hyprbars]
enabled = true
failed = false
filename = "hyprbars.so"
EOF_PLUGIN

cat >"$hyprpm_state/headersRoot/include/hyprland/src/version.h" <<'EOF_HEADER'
#define GIT_COMMIT_HASH    "running-commit"
EOF_HEADER

cat >"$hyprpm_state/headersRoot/share/pkgconfig/hyprland.pc" <<EOF_PC
Name: Hyprland
Description: test fixture
Version: 1
Cflags: -I$hyprpm_state/headersRoot/include
EOF_PC

cat >"$fakebin/hyprpm" <<'EOF_HYPRPM'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_HYPRPM_LOG:?}"
if [[ ${1:-} == reload ]]; then
  : >"${TEST_LOADED_MARKER:?}"
fi
EOF_HYPRPM

cat >"$fakebin/hyprctl" <<'EOF_HYPRCTL'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == -j && ${2:-} == version ]]; then
  printf '%s\n' '{"commit":"running-commit","abiHash":"running-commit_aq_0.14_hu_0.14_hg_0.5_hc_0.1_hlg_0.6"}'
  exit 0
fi
if [[ ${1:-} == plugin && ${2:-} == list ]]; then
  if [[ -f ${TEST_LOADED_MARKER:?} ]]; then
    printf '%s\n' 'Plugin hyprbars by Vaxry:'
  else
    printf '%s\n' 'no plugins loaded'
  fi
  exit 0
fi
if [[ ${1:-} == notify ]]; then
  exit 0
fi
exit 0
EOF_HYPRCTL

cat >"$fakebin/pkgconf" <<'EOF_PKGCONF'
#!/usr/bin/env bash
set -euo pipefail
pc_dir="${PKG_CONFIG_PATH%%:*}"
awk '/^[[:space:]]*Cflags:/ { sub(/^[[:space:]]*Cflags:[[:space:]]*/, ""); print; exit }' \
  "$pc_dir/hyprland.pc"
EOF_PKGCONF

chmod 0755 "$fakebin/hyprpm" "$fakebin/hyprctl" "$fakebin/pkgconf"
: >"$hyprpm_log"

env \
  PATH="$fakebin:$PATH" \
  HOME="$home" \
  USER=tester \
  XDG_RUNTIME_DIR="$runtime" \
  XDG_STATE_HOME="$home/.local/state" \
  HYPRLAND_INSTANCE_SIGNATURE=test-single-quoted-state \
  HYPRPM_STATE_DIR="$hyprpm_state" \
  TEST_HYPRPM_LOG="$hyprpm_log" \
  TEST_LOADED_MARKER="$loaded_marker" \
  bash "$AUTO_RELOAD"

[[ $(grep -cFx reload "$hyprpm_log" || true) -eq 1 ]] \
  || fail 'single-quoted hyprpm ABI state was falsely rejected before reload'
[[ -f $loaded_marker ]] \
  || fail 'healthy single-quoted hyprpm state did not load hyprbars'
[[ ! -e $home/.local/state/awtarchy/hyprbars-repair-required ]] \
  || fail 'healthy single-quoted hyprpm state created a false repair marker'

printf '%s\n' 'PASS: real hyprpm single-quoted ABI state is accepted.'
