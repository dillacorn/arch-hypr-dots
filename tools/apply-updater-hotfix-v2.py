#!/usr/bin/env python3
from pathlib import Path
from textwrap import dedent
import re

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one {label}, found {count}")
    return text.replace(old, new, 1)


runtime_path = ROOT / "local/share/awtarchy/awtarchy-runtime.sh"
runtime = runtime_path.read_text(encoding="utf-8")

runtime = replace_once(
    runtime,
    "      lua -e 'assert(loadfile(arg[1]))' \"$file\"",
    "      AWTARCHY_LUA_VALIDATE_FILE=\"$file\" lua -e 'local path = assert(os.getenv(\"AWTARCHY_LUA_VALIDATE_FILE\")); assert(loadfile(path))'",
    "legacy Lua validator",
)

old_stage_tail = "\n".join([
    '  chown "${TARGET_USER}:${TARGET_USER}" "$command_version_file" "$config_version_file"',
    '  chmod 0644 "$command_version_file" "$config_version_file"',
    "",
    '  ok "Installed Awtarchy command: ${bin_dir}/awtarchy"',
    "",
])
new_stage_tail = "\n".join([
    '  chown "${TARGET_USER}:${TARGET_USER}" "$command_version_file" "$config_version_file"',
    '  chmod 0644 "$command_version_file" "$config_version_file"',
    "",
    '  log "Verifying the installed Awtarchy command against GitHub\'s latest release..."',
    '  if ! env -u XDG_DATA_HOME -u XDG_STATE_HOME \\',
    '    HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \\',
    '    "${bin_dir}/awtarchy" self-update',
    "  then",
    '    die "Could not verify the installed Awtarchy command against GitHub\'s latest release."',
    "  fi",
    "",
    '  ok "Installed Awtarchy command: ${bin_dir}/awtarchy"',
    "",
])
runtime = replace_once(runtime, old_stage_tail, new_stage_tail, "command-stage tail")
runtime_path.write_text(runtime, encoding="utf-8")

installer_path = ROOT / "awtarchy-install.sh"
installer = installer_path.read_text(encoding="utf-8")

refresh_function = dedent('''
refresh_existing_command() {
  local bin_dir="${TARGET_HOME}/.local/bin"
  local data_dir="${TARGET_HOME}/.local/share/awtarchy"
  local state_dir="${TARGET_HOME}/.local/state/awtarchy"
  local command_version="${state_dir}/command-version"
  local command_tag revision

  bash -n "$RUNTIME_SOURCE" || {
    printf 'ERROR: Awtarchy runtime failed Bash syntax validation.\n' >&2
    exit 1
  }
  bash -n "$LAUNCHER_SOURCE" || {
    printf 'ERROR: Awtarchy command failed Bash syntax validation.\n' >&2
    exit 1
  }

  install -d -m 0755 "$bin_dir" "$data_dir" "$state_dir"
  install -m 0755 "$LAUNCHER_SOURCE" "${bin_dir}/awtarchy"
  install -m 0755 "$RUNTIME_SOURCE" "${data_dir}/awtarchy-runtime.sh"

  command_tag="$(source_release_tag)"
  revision="$(source_revision)"
  write_version_file "$command_version" "$command_tag" "$revision" installed_at
  repair_target_ownership

  printf '%s\n' "Verifying the Awtarchy command against GitHub's latest release..."
  if ! env -u XDG_DATA_HOME -u XDG_STATE_HOME \
    HOME="$TARGET_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
    "${bin_dir}/awtarchy" self-update
  then
    printf '%s\n' "ERROR: Could not verify the Awtarchy command against GitHub's latest release." >&2
    exit 1
  fi
  repair_target_ownership
}

''').lstrip()

marker = "show_existing_install_message() {\n"
if "refresh_existing_command()" in installer:
    raise SystemExit("refresh_existing_command already exists unexpectedly")
installer = replace_once(installer, marker, refresh_function + marker, "existing-install message marker")

message_pattern = re.compile(
    r"show_existing_install_message\(\) \{\n.*?\n\}\n\nshow_legacy_dry_run_message\(\) \{",
    re.S,
)
message_replacement = dedent('''
show_existing_install_message() {
  cat <<EOF_MESSAGE
Awtarchy is already installed for ${TARGET_USER}.

The installed launcher and runtime were replaced from this installer, then
verified against GitHub's latest release. No packages or managed configs
were changed.

  awtarchy                 Open the maintenance menu
  awtarchy self-update     Update the Awtarchy command
  awtarchy update          Update configs and preserve personal changes
  awtarchy reset           Reset managed configs to release defaults
  awtarchy version         Show installed and latest releases

To intentionally run the complete installer again:

  sudo ./awtarchy-install.sh --reinstall
EOF_MESSAGE
}

show_legacy_dry_run_message() {''').lstrip()
installer, count = message_pattern.subn(message_replacement, installer, count=1)
if count != 1:
    raise SystemExit(f"expected one existing-install message function, replaced {count}")

migration_old = "\n".join([
    "  repair_target_ownership",
    "",
    "  cat <<EOF_MESSAGE",
    "",
])
migration_new = "\n".join([
    "  repair_target_ownership",
    "  refresh_existing_command",
    "",
    "  cat <<EOF_MESSAGE",
    "",
])
installer = replace_once(installer, migration_old, migration_new, "migration ownership tail")

existing_old = "\n".join([
    "  if installed_command_exists; then",
    "    show_existing_install_message",
    "    exit 0",
    "  fi",
    "",
])
existing_new = "\n".join([
    "  if installed_command_exists; then",
    "    if (( DRY_RUN_REQUESTED == 1 )); then",
    "      printf 'Awtarchy is already installed for %s. No files were changed because --dry-run was used.\\n' \\",
    '        "$TARGET_USER"',
    "    else",
    "      refresh_existing_command",
    "      show_existing_install_message",
    "    fi",
    "    exit 0",
    "  fi",
    "",
])
installer = replace_once(installer, existing_old, existing_new, "installed-command branch")
installer_path.write_text(installer, encoding="utf-8")

command_test_path = ROOT / "tests/test-awtarchy-command.sh"
command_test = command_test_path.read_text(encoding="utf-8")

anchor = "\n".join([
    "grep -Fq 'AWTARCHY_REPO_DIR' \"$RUNTIME_SOURCE\" \\",
    '  || fail "runtime does not accept the installer source directory"',
    "",
])
addition = anchor + "\n".join([
    "grep -Fq 'refresh_existing_command()' \"$INSTALLER_SOURCE\" \\",
    '  || fail "installer does not refresh an existing command"',
    "grep -Fq '\"${bin_dir}/awtarchy\" self-update' \"$RUNTIME_SOURCE\" \\",
    '  || fail "fresh install command stage does not verify the latest release"',
    "",
])
command_test = replace_once(command_test, anchor, addition, "command-test anchor")

old_existing = "\n".join([
    'existing_output="$(HOME="$home" USER="$(id -un)" bash "$INSTALLER_SOURCE")"',
    "grep -Fq 'Awtarchy is already installed' <<<\"$existing_output\" \\",
    '  || fail "installer did not detect the existing command"',
    "grep -Fq 'awtarchy self-update' <<<\"$existing_output\" \\",
    '  || fail "installer did not explain the new update command"',
    "",
])
new_existing = "\n".join([
    "printf '%s\\n' '#!/usr/bin/env bash' 'exit 99' >\"$home/.local/bin/awtarchy\"",
    "printf '%s\\n' '#!/usr/bin/env bash' 'exit 98' >\"$home/.local/share/awtarchy/awtarchy-runtime.sh\"",
    "chmod 0755 \\",
    '  "$home/.local/bin/awtarchy" \\',
    '  "$home/.local/share/awtarchy/awtarchy-runtime.sh"',
    "printf 'tag=v0.0.0\\nupdated_at=2000-01-01T00:00:00Z\\n' \\",
    '  >"$home/.local/state/awtarchy/command-version"',
    "",
    'existing_output="$(' ,
    '  HOME="$home" USER="$(id -un)" PATH="${fakebin}:$PATH" \\',
    '    AWTARCHY_SYSTEM_BIN_DIR="${TMP}/existing-system-bin" \\',
    '    AWTARCHY_TEST_ARCHIVE="${TMP}/release.tar.gz" \\',
    '    bash "$INSTALLER_SOURCE"',
    ')"',
    "grep -Fq 'Awtarchy is already installed' <<<\"$existing_output\" \\",
    '  || fail "installer did not detect the existing command"',
    "grep -Fq \"verified against GitHub's latest release\" <<<\"$existing_output\" \\",
    '  || fail "installer did not report latest-release verification"',
    'cmp -s "$home/.local/bin/awtarchy" "$release_root/local/bin/awtarchy" \\',
    '  || fail "installer did not replace the stale command launcher"',
    "cmp -s \\",
    '  "$home/.local/share/awtarchy/awtarchy-runtime.sh" \\',
    '  "$release_root/local/share/awtarchy/awtarchy-runtime.sh" \\',
    '  || fail "installer did not replace the stale command runtime"',
    "grep -Fxq 'tag=v9.9.9' \"$home/.local/state/awtarchy/command-version\" \\",
    '  || fail "installer did not record the latest command release"',
    "grep -Fxq 'tag=v0.0.1' \"$home/.local/state/awtarchy/config-version\" \\",
    '  || fail "command refresh changed the installed config release"',
    "",
])
command_test = replace_once(command_test, old_existing, new_existing, "existing command test block")

old_legacy_env = "\n".join([
    '  HOME="$legacy_home" USER="$(id -un)" AWTARCHY_INSTALL_TAG=v9.9.9 \\',
    '    bash "$INSTALLER_SOURCE"',
    "",
])
new_legacy_env = "\n".join([
    '  HOME="$legacy_home" USER="$(id -un)" PATH="${fakebin}:$PATH" \\',
    '    AWTARCHY_SYSTEM_BIN_DIR="${TMP}/legacy-system-bin" \\',
    '    AWTARCHY_TEST_ARCHIVE="${TMP}/release.tar.gz" \\',
    '    AWTARCHY_INSTALL_TAG=v9.9.9 bash "$INSTALLER_SOURCE"',
    "",
])
command_test = replace_once(command_test, old_legacy_env, new_legacy_env, "legacy installer environment")
command_test_path.write_text(command_test, encoding="utf-8")

lua_test_lines = [
    "#!/usr/bin/env bash",
    "set -Eeuo pipefail",
    "IFS=$'\\n\\t'",
    "",
    'ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"',
    'RUNTIME_SOURCE="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"',
    'TMP="$(mktemp -d)"',
    "trap 'rm -rf -- \"$TMP\"' EXIT",
    "",
    "fail() {",
    "  printf 'FAIL: %s\\n' \"$*\" >&2",
    "  exit 1",
    "}",
    "",
    'command -v lua >/dev/null 2>&1 || fail "lua is required for this test"',
    "",
    "if grep -Fq \"lua -e 'assert(loadfile(arg[1]))'\" \"$RUNTIME_SOURCE\"; then",
    '  fail "runtime still validates Lua through arg[1] and standard input"',
    "fi",
    "",
    "awk '",
    "  /^validate_candidate\\(\\) \\{/ { capture=1 }",
    "  capture { print }",
    "  capture && /^}$/ { exit }",
    "' \"$RUNTIME_SOURCE\" > \"$TMP/validate_candidate.sh\"",
    "",
    "grep -Fq 'AWTARCHY_LUA_VALIDATE_FILE=\"$file\" lua -e' \"$TMP/validate_candidate.sh\" \\",
    '  || fail "validate_candidate does not pass the Lua path explicitly"',
    "",
    "# shellcheck source=/dev/null",
    'source "$TMP/validate_candidate.sh"',
    "",
    'valid_lua="$TMP/valid config.lua"',
    'invalid_lua="$TMP/invalid config.lua"',
    'execution_marker="$TMP/lua-config-executed"',
    "",
    "printf '%s\\n' \\",
    "  'local marker = os.getenv(\"AWTARCHY_LUA_EXECUTION_MARKER\")' \\",
    "  'if marker then' \\",
    "  '  local output = assert(io.open(marker, \"w\"))' \\",
    "  '  output:write(\"executed\\\\n\")' \\",
    "  '  output:close()' \\",
    "  'end' \\",
    "  'return true' >\"$valid_lua\"",
    "printf '%s\\n' 'local broken =' >\"$invalid_lua\"",
    "",
    'export AWTARCHY_LUA_EXECUTION_MARKER="$execution_marker"',
    "",
    "validate_candidate \"$valid_lua\" '.config/hypr/valid config.lua' </dev/null \\",
    '  || fail "valid Lua failed validation with closed standard input"',
    '[[ ! -e $execution_marker ]] \\',
    '  || fail "Lua validation executed the config instead of only compiling it"',
    "",
    "printf '/terminal input must not be parsed as Lua\\n' \\",
    "  | validate_candidate \"$valid_lua\" '.config/hypr/valid config.lua' \\",
    '  || fail "Lua validation consumed terminal input"',
    '[[ ! -e $execution_marker ]] \\',
    '  || fail "Lua validation executed the config while terminal input was present"',
    "",
    "if validate_candidate \"$invalid_lua\" '.config/hypr/invalid config.lua' </dev/null; then",
    '  fail "invalid Lua passed validation"',
    "fi",
    "",
    "printf 'Lua validation tests passed.\\n'",
    "",
]
lua_test_path = ROOT / "tests/test-lua-validation.sh"
lua_test_path.write_text("\n".join(lua_test_lines), encoding="utf-8")
lua_test_path.chmod(0o755)

ci = dedent('''
name: Validate Awtarchy

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install validation tools
        run: sudo apt-get update && sudo apt-get install -y shellcheck lua5.4
      - name: Bash syntax
        run: |
          test ! -e awtarchy.sh
          bash -n awtarchy-install.sh
          bash -n local/bin/awtarchy
          bash -n local/share/awtarchy/awtarchy-runtime.sh
          bash -n tests/test-awtarchy-command.sh
          bash -n tests/test-awtarchy-command-shim.sh
          bash -n tests/test-lua-validation.sh
      - name: ShellCheck command code
        run: |
          shellcheck \
            awtarchy-install.sh \
            local/bin/awtarchy \
            tests/test-awtarchy-command.sh \
            tests/test-awtarchy-command-shim.sh \
            tests/test-lua-validation.sh
      - name: Command and updater integration tests
        run: |
          bash tests/test-awtarchy-command.sh
          bash tests/test-awtarchy-command-shim.sh
          bash tests/test-lua-validation.sh
''').lstrip()
(ROOT / ".github/workflows/validate-awtarchy.yml").write_text(ci, encoding="utf-8")
