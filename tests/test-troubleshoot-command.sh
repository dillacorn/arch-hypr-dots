#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

home="${TMP}/home"
fakebin="${TMP}/fakebin"
marker="${TMP}/network-called"
mkdir -p \
  "$home/.local/bin" \
  "$home/.local/share/awtarchy" \
  "$home/.local/state/awtarchy/logs" \
  "$home/.local/state/awtarchy/baseline/home/.config/hypr" \
  "$home/.config/hypr/scripts" \
  "$home/.config/quickshell/awtarchy" \
  "$home/.cache/awtarchy" \
  "$fakebin"

install -m 0755 "$ROOT/local/bin/awtarchy" "$home/.local/bin/awtarchy"
install -m 0755 "$ROOT/local/share/awtarchy/awtarchy-runtime.sh" "$home/.local/share/awtarchy/awtarchy-runtime.sh"

cat >"$home/.config/hypr/hyprland.lua" <<'EOF'
local wlogout = "~/.config/hypr/scripts/wlogout_toggle.sh"
local power_menu = "~/.config/hypr/scripts/quickshell_power_menu.sh"
local hypr_quicksettings = "~/.config/hypr/scripts/launch_handler.sh hypr_quicksettings \"alacritty --class hypr_quicksettings -e bash ~/.config/hypr/scripts/hypr_quicksettings.sh --ui\""
hl.bind("SUPER + P", hl.dsp.exec_cmd(wlogout), {})
hl.exec_cmd("~/.config/hypr/scripts/waybar.sh start &")
hl.exec_cmd("~/.config/hypr/scripts/quickshell.sh start &")
EOF
cp "$home/.config/hypr/hyprland.lua" "$home/.local/state/awtarchy/baseline/home/.config/hypr/hyprland.lua"
printf '%s\n' '.config/hypr/hyprland.lua' >"$home/.local/state/awtarchy/baseline/manifest.paths"
printf '%s\n' 'tag=v2.0.0-1' >"$home/.local/state/awtarchy/baseline/metadata"
printf '%s\n' 'tag=quickshell-conversion-testing@test' >"$home/.local/state/awtarchy/config-version"
printf '%s\n' '[awtarchy-update] fixture update log' >"$home/.local/state/awtarchy/logs/update-20260813-000000.log"
printf '%s\n' '{"enabled":true,"monitors":{}}' >"$home/.cache/awtarchy/quickshell-state.json"
printf '%s\n' 'fixture quickshell log' >"$home/.cache/awtarchy/quickshell.log"
printf '%s\n' 'import QtQuick' >"$home/.config/quickshell/awtarchy/shell.qml"

for script in quickshell.sh quickshell_power_menu.sh quickshell_quick_settings_toggle.sh hypr_quicksettings.sh wlogout_toggle.sh waybar.sh; do
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$home/.config/hypr/scripts/$script"
  chmod 0755 "$home/.config/hypr/scripts/$script"
done

cat >"$fakebin/curl" <<EOF
#!/usr/bin/env bash
: >"$marker"
exit 99
EOF
cat >"$fakebin/hyprctl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *version*) printf '%s\n' 'Hyprland 0.test' ;;
  *configerrors*) printf '%s\n' 'No config errors' ;;
  *monitors*) printf '%s\n' '[{"name":"eDP-1","focused":true}]' ;;
  *binds*) printf '%s\n' '[{"key":"P","arg":"wlogout_toggle.sh"}]' ;;
  *clients*) printf '%s\n' '[{"address":"0x1","pid":123,"class":"hypr_quicksettings","initialClass":"hypr_quicksettings","title":"Awtarchy Quick Settings","initialTitle":"Awtarchy Quick Settings"}]' ;;
  *) printf '%s\n' '{}' ;;
esac
EOF
cat >"$fakebin/qs" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == --version ]]; then printf '%s\n' 'quickshell test'; else printf '%s\n' 'ipc unavailable fixture'; fi
EOF
cat >"$fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat >"$fakebin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'fixture systemctl'
exit 0
EOF
cat >"$fakebin/journalctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'fixture awtarchy quickshell journal line'
EOF
cat >"$fakebin/coredumpctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'fixture quickshell coredump line'
EOF
cat >"$fakebin/lspci" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '00:02.0 VGA compatible controller: Fixture GPU'
EOF
cat >"$fakebin/lscpu" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'Architecture: x86_64' 'Vendor ID: GenuineFixture' 'Model name: Fixture CPU'
EOF
chmod 0755 "$fakebin/"*

common_env=(
  "HOME=$home"
  "USER=$(id -un)"
  "LOGNAME=$(id -un)"
  "PATH=${fakebin}:${home}/.local/bin:/usr/bin:/bin"
)

out="${TMP}/troubleshoot.out"
env "${common_env[@]}" "$home/.local/bin/awtarchy" troubleshoot >"$out"
[[ ! -e "$home/vpn" ]] || fail 'troubleshoot created ~/vpn'
[[ ! -e "$marker" ]] || fail 'troubleshoot accessed the network'

grep -Fq 'Awtarchy troubleshooting report' "$out" || fail 'missing report header'
grep -Fq 'SUPER + P' "$out" || fail 'missing Hyprland bind evidence'
grep -Fq 'wlogout_toggle.sh' "$out" || fail 'missing retired helper evidence'
grep -Fq 'quickshell_power_menu.sh' "$out" || fail 'missing current helper evidence'
grep -Fq 'fixture quickshell log' "$out" || fail 'missing Quickshell log'
grep -Fq 'fixture awtarchy quickshell journal line' "$out" || fail 'missing journal evidence'
grep -Fq 'No configuration, packages, services, or shell processes were changed by this command.' "$out" \
  || fail 'missing read-only statement'
grep -Fq 'command=awtarchy' "$out" || fail 'production command label missing'

compgen -G "$home/.local/state/awtarchy/logs/troubleshoot-*.log" >/dev/null \
  || fail 'troubleshoot report was not saved'

set +e
env "${common_env[@]}" "$home/.local/bin/awtarchy" troubleshoot --bad >/dev/null 2>&1
rc=$?
set -e
(( rc != 0 )) || fail 'troubleshoot accepted an option'

printf 'Troubleshoot command tests passed.\n'
