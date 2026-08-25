#!/usr/bin/env bash
# Static/security contract for the real Awtarchy PolicyKit agent.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_DIR="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent"
QML="${SOURCE_DIR}/shell.qml"
LAUNCHER="${SOURCE_DIR}/launcher.sh"
GUARD="${SOURCE_DIR}/window-guard.sh"
SERVICE="${SOURCE_DIR}/awtarchy-polkit-agent.service"
CONTROLLER="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent-live-test.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

require_file() {
    [[ -f $1 ]] || fail "missing $1"
}

require_contains() {
    local file="$1" pattern="$2"
    grep -Fq -- "$pattern" "$file" || fail "$file missing: $pattern"
}

require_regex() {
    local file="$1" pattern="$2"
    grep -Eq -- "$pattern" "$file" || fail "$file missing regex: $pattern"
}

reject_regex() {
    local file="$1" pattern="$2"
    if grep -Eq -- "$pattern" "$file"; then
        fail "$file contains forbidden regex: $pattern"
    fi
}

test_qml_contract() {
    require_file "$QML"
    require_contains "$QML" 'import Quickshell.Services.Polkit'
    require_contains "$QML" 'PolkitAgent {'
    require_contains "$QML" 'property bool detailsExpanded: false'
    require_contains "$QML" 'detailsExpanded = false'
    require_contains "$QML" 'flow.submit(response)'
    require_contains "$QML" 'flow.cancelAuthenticationRequest()'
    require_contains "$QML" 'flow.responseVisible ? TextInput.Normal : TextInput.Password'
    require_contains "$QML" 'textFormat: Text.PlainText'
    require_contains "$QML" '"/usr/bin/pkaction"'
    require_contains "$QML" 'implicitWidth: 900'
    require_contains "$QML" 'implicitHeight: 520'
    require_contains "$QML" 'inputField.text = ""'
    require_contains "$QML" 'polkitAgent.isRegistered'
    require_contains "$QML" 'Qt.exit(78)'

    # No credential transport outside AuthFlow and no executable user theme/import path.
    reject_regex "$QML" 'sudo[[:space:]]+-S|pkexec.*(password|response)|/tmp/.*(password|response)|Socket|ServerSocket'
    reject_regex "$QML" 'QML2_IMPORT_PATH|QML_IMPORT_PATH|\.config/quickshell|Theme\.qml'
}

test_launcher_contract() {
    require_file "$LAUNCHER"
    bash -n "$LAUNCHER"
    require_contains "$LAUNCHER" 'RUNTIME_DIR="/usr/local/libexec/awtarchy/polkit-agent"'
    require_contains "$LAUNCHER" '/usr/bin/quickshell'
    require_contains "$LAUNCHER" '/usr/bin/env -i'
    require_contains "$LAUNCHER" 'QML2_IMPORT_PATH'
    require_contains "$LAUNCHER" 'QML_IMPORT_PATH'
    require_contains "$LAUNCHER" 'QT_PLUGIN_PATH'
    require_contains "$LAUNCHER" 'LD_PRELOAD'
    require_contains "$LAUNCHER" 'LD_LIBRARY_PATH'
    require_contains "$LAUNCHER" 'POLKIT_DEBUG'
    require_contains "$LAUNCHER" 'stat -Lc'
    require_contains "$LAUNCHER" '[[ ! -L $path ]]'
    reject_regex "$LAUNCHER" '(^|[^[:alnum:]_])eval([[:space:]]|$)'
}

test_window_guard_contract() {
    require_file "$GUARD"
    bash -n "$GUARD"
    require_contains "$GUARD" 'APP_ID="awtarchy-polkit-agent"'
    require_contains "$GUARD" 'WINDOW_WIDTH=900'
    require_contains "$GUARD" 'WINDOW_HEIGHT=520'
    require_contains "$GUARD" '/usr/bin/hyprctl -j clients'
    require_contains "$GUARD" 'window.float({ action = "set", window = w })'
    require_contains "$GUARD" 'window.resize({ x = 900, y = 520, relative = false, window = w })'
    require_contains "$GUARD" 'window.center({ window = w })'
    require_contains "$GUARD" 'last_address'
    require_contains "$GUARD" 'if [[ $address != "$last_address" ]]'
    reject_regex "$GUARD" 'password|AuthFlow|submit\('
}

test_service_contract() {
    require_file "$SERVICE"
    require_contains "$SERVICE" 'ExecStart=/usr/local/libexec/awtarchy/polkit-agent/launcher'
    require_contains "$SERVICE" 'Restart=on-failure'
    reject_regex "$SERVICE" '%h/|HOME=|EnvironmentFile='
}

test_controller_contract() {
    require_file "$CONTROLLER"
    bash -n "$CONTROLLER"
    require_contains "$CONTROLLER" 'RUNTIME_DIR="/usr/local/libexec/awtarchy/polkit-agent"'
    require_contains "$CONTROLLER" 'USER_UNIT_DIR="/usr/local/lib/systemd/user"'
    require_contains "$CONTROLLER" 'GNOME_BIN="/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"'
    require_contains "$CONTROLLER" 'install -m 0644 -o root -g root'
    require_contains "$CONTROLLER" 'install -m 0755 -o root -g root'
    require_contains "$CONTROLLER" 'systemctl --user daemon-reload'
    require_contains "$CONTROLLER" 'systemctl --user start "$SERVICE_NAME"'
    require_contains "$CONTROLLER" 'restore_gnome'
    require_contains "$CONTROLLER" '/usr/bin/pkcheck --revoke-temp'
    require_contains "$CONTROLLER" '/usr/bin/pkexec --disable-internal-agent /usr/bin/true'
    require_contains "$CONTROLLER" 'readlink -f -- "/proc/${pid}/exe"'
    require_contains "$CONTROLLER" 'verify_installed_runtime'
    require_contains "$CONTROLLER" 'rollback_to_gnome'

    # Testing must not uninstall GNOME or rewrite permanent Hyprland autostart.
    reject_regex "$CONTROLLER" 'pacman[[:space:]].*-R|hyprland\.lua|sed[[:space:]].*polkit-gnome'
}

test_qml_contract
test_launcher_contract
test_window_guard_contract
test_service_contract
test_controller_contract

printf '%s\n' 'secure Polkit agent static/security tests passed'
