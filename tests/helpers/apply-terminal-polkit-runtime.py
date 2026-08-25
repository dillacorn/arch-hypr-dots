#!/usr/bin/env python3
from pathlib import Path
import re

path = Path("local/share/awtarchy/awtarchy-runtime.sh")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    text = text.replace(old, new, 1)


def replace_function(name: str, next_name: str, replacement: str) -> None:
    global text
    pattern = re.compile(
        rf"{re.escape(name)}\(\) \{{\n.*?\n\}}\n\n(?={re.escape(next_name)}\(\) \{{)",
        re.S,
    )
    text, count = pattern.subn(replacement.rstrip() + "\n\n", text, count=1)
    if count != 1:
        raise SystemExit(f"{name}: expected exactly one function block, found {count}")


replace_once(
    '"Utilities:upower polkit gnome-keyring ',
    '"Utilities:upower polkit python-gobject gnome-keyring ',
    "fresh-install PolicyKit Python dependency",
)
replace_once(
    "local -a required=(quickshell upower playerctl hyprland-qt-support) missing=()",
    "local -a required=(quickshell upower playerctl hyprland-qt-support polkit python-gobject) missing=()",
    "update PolicyKit Python prerequisites",
)

replace_function(
    "awtarchy_polkit_verify_runtime",
    "awtarchy_polkit_restore_install_transaction",
    r'''awtarchy_polkit_verify_runtime_tree() {
  local directory="$1" actual expected
  awtarchy_polkit_verify_root_directory "$directory" || return 1
  awtarchy_polkit_verify_root_file "${directory}/agent.py" 644 || return 1
  awtarchy_polkit_verify_root_file "${directory}/alacritty.toml" 644 || return 1
  awtarchy_polkit_verify_root_file "${directory}/launcher" 755 || return 1
  awtarchy_polkit_verify_root_file "${directory}/tui.py" 644 || return 1
  actual="$(awtarchy_polkit_root /usr/bin/find "$directory" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | LC_ALL=C sort)" || return 1
  expected=$'agent.py\nalacritty.toml\nlauncher\ntui.py'
  [[ "$actual" == "$expected" ]] || { warn "Unexpected files in Awtarchy PolicyKit runtime."; return 1; }
}

awtarchy_polkit_verify_runtime() {
  awtarchy_polkit_verify_runtime_tree "$AWTARCHY_POLKIT_RUNTIME_DIR" || return 1
  awtarchy_polkit_verify_root_file "$AWTARCHY_POLKIT_SERVICE_DEST" 644 || return 1
}''',
)

replace_function(
    "install_awtarchy_polkit_agent_runtime",
    "migrate_awtarchy_polkit_autostart",
    r'''install_awtarchy_polkit_agent_runtime() {
  local repo_dir="$1"
  local source_dir="${repo_dir}/config/hypr/scripts/awtarchy-polkit-agent"
  local agent_source="${source_dir}/agent.py"
  local tui_source="${source_dir}/tui.py"
  local terminal_config_source="${source_dir}/alacritty.toml"
  local launcher_source="${source_dir}/launcher.sh"
  local service_source="${source_dir}/awtarchy-polkit-agent.service"
  local stage="" previous_runtime="" failed_runtime="" service_tmp="" previous_service=""

  awtarchy_polkit_verify_source_file "$agent_source" || return 1
  awtarchy_polkit_verify_source_file "$tui_source" || return 1
  awtarchy_polkit_verify_source_file "$terminal_config_source" || return 1
  awtarchy_polkit_verify_source_file "$launcher_source" || return 1
  awtarchy_polkit_verify_source_file "$service_source" || return 1
  bash -n "$launcher_source" || { warn "PolicyKit launcher failed Bash syntax validation."; return 1; }
  /usr/bin/python3 -c 'import ast,pathlib,sys; [ast.parse(pathlib.Path(p).read_text(encoding="utf-8"), filename=p) for p in sys.argv[1:]]' \
    "$agent_source" "$tui_source" || { warn "PolicyKit Python source failed syntax validation."; return 1; }

  awtarchy_polkit_root /usr/bin/install -d -m 0755 -o root -g root -- "$AWTARCHY_POLKIT_RUNTIME_PARENT" || return 1
  awtarchy_polkit_root /usr/bin/install -d -m 0755 -o root -g root -- "$AWTARCHY_POLKIT_USER_UNIT_DIR" || return 1
  awtarchy_polkit_verify_root_directory "$AWTARCHY_POLKIT_RUNTIME_PARENT" || return 1
  awtarchy_polkit_verify_root_directory "$AWTARCHY_POLKIT_USER_UNIT_DIR" || return 1

  stage="$(awtarchy_polkit_root /usr/bin/mktemp -d "${AWTARCHY_POLKIT_RUNTIME_PARENT}/.polkit-agent.stage.XXXXXX")" || return 1
  if ! awtarchy_polkit_root /usr/bin/install -m 0644 -o root -g root -- "$agent_source" "${stage}/agent.py" \
    || ! awtarchy_polkit_root /usr/bin/install -m 0644 -o root -g root -- "$tui_source" "${stage}/tui.py" \
    || ! awtarchy_polkit_root /usr/bin/install -m 0644 -o root -g root -- "$terminal_config_source" "${stage}/alacritty.toml" \
    || ! awtarchy_polkit_root /usr/bin/install -m 0755 -o root -g root -- "$launcher_source" "${stage}/launcher" \
    || ! awtarchy_polkit_root /usr/bin/chmod 0755 -- "$stage";
  then
    awtarchy_polkit_root /usr/bin/rm -rf --one-file-system -- "$stage" 2>/dev/null || true
    return 1
  fi
  awtarchy_polkit_verify_runtime_tree "$stage" || {
    awtarchy_polkit_root /usr/bin/rm -rf --one-file-system -- "$stage" 2>/dev/null || true
    return 1
  }

  if awtarchy_polkit_root /usr/bin/test -L "$AWTARCHY_POLKIT_RUNTIME_DIR"; then
    awtarchy_polkit_root /usr/bin/rm -rf --one-file-system -- "$stage" 2>/dev/null || true
    warn "Refusing symbolic-link Awtarchy PolicyKit runtime destination."
    return 1
  fi
  if awtarchy_polkit_root /usr/bin/test -e "$AWTARCHY_POLKIT_RUNTIME_DIR"; then
    [[ "$(awtarchy_polkit_root /usr/bin/stat -Lc '%F' -- "$AWTARCHY_POLKIT_RUNTIME_DIR")" == directory ]] || {
      awtarchy_polkit_root /usr/bin/rm -rf --one-file-system -- "$stage" 2>/dev/null || true
      return 1
    }
    previous_runtime="${AWTARCHY_POLKIT_RUNTIME_PARENT}/.polkit-agent.previous.$$"
    awtarchy_polkit_root /usr/bin/test ! -e "$previous_runtime" || return 1
    awtarchy_polkit_root /usr/bin/mv -Tf -- "$AWTARCHY_POLKIT_RUNTIME_DIR" "$previous_runtime" || return 1
  fi

  failed_runtime="${AWTARCHY_POLKIT_RUNTIME_PARENT}/.polkit-agent.failed.$$"
  if ! awtarchy_polkit_root /usr/bin/mv -Tf -- "$stage" "$AWTARCHY_POLKIT_RUNTIME_DIR"; then
    [[ -z "$previous_runtime" ]] || awtarchy_polkit_root /usr/bin/mv -Tf -- "$previous_runtime" "$AWTARCHY_POLKIT_RUNTIME_DIR" 2>/dev/null || true
    return 1
  fi

  if awtarchy_polkit_root /usr/bin/test -L "$AWTARCHY_POLKIT_SERVICE_DEST"; then
    awtarchy_polkit_restore_install_transaction "$previous_runtime" "$failed_runtime" ""
    warn "Refusing symbolic-link Awtarchy PolicyKit service destination."
    return 1
  fi
  if awtarchy_polkit_root /usr/bin/test -e "$AWTARCHY_POLKIT_SERVICE_DEST"; then
    [[ "$(awtarchy_polkit_root /usr/bin/stat -Lc '%F' -- "$AWTARCHY_POLKIT_SERVICE_DEST")" == 'regular file' ]] \
      || { awtarchy_polkit_restore_install_transaction "$previous_runtime" "$failed_runtime" ""; return 1; }
    previous_service="${AWTARCHY_POLKIT_USER_UNIT_DIR}/.awtarchy-polkit-agent.service.previous.$$"
    awtarchy_polkit_root /usr/bin/test ! -e "$previous_service" || return 1
    awtarchy_polkit_root /usr/bin/mv -Tf -- "$AWTARCHY_POLKIT_SERVICE_DEST" "$previous_service" || return 1
  fi

  service_tmp="$(awtarchy_polkit_root /usr/bin/mktemp "${AWTARCHY_POLKIT_USER_UNIT_DIR}/.awtarchy-polkit-agent.service.XXXXXX")" || {
    awtarchy_polkit_restore_install_transaction "$previous_runtime" "$failed_runtime" "$previous_service"
    return 1
  }
  if ! awtarchy_polkit_root /usr/bin/install -m 0644 -o root -g root -- "$service_source" "$service_tmp" \
    || ! awtarchy_polkit_root /usr/bin/mv -Tf -- "$service_tmp" "$AWTARCHY_POLKIT_SERVICE_DEST";
  then
    awtarchy_polkit_root /usr/bin/rm -f -- "$service_tmp" 2>/dev/null || true
    awtarchy_polkit_restore_install_transaction "$previous_runtime" "$failed_runtime" "$previous_service"
    return 1
  fi

  if ! awtarchy_polkit_verify_runtime; then
    awtarchy_polkit_restore_install_transaction "$previous_runtime" "$failed_runtime" "$previous_service"
    warn "Awtarchy PolicyKit runtime verification failed."
    return 1
  fi

  [[ -z "$previous_runtime" ]] || awtarchy_polkit_root /usr/bin/rm -rf --one-file-system -- "$previous_runtime" || return 1
  [[ -z "$previous_service" ]] || awtarchy_polkit_root /usr/bin/rm -f -- "$previous_service" || return 1
  log "Installed root-owned Awtarchy terminal PolicyKit authentication runtime."
}''',
)

replace_function(
    "awtarchy_polkit_verify_service_process",
    "activate_awtarchy_polkit_agent",
    r'''awtarchy_polkit_process_tree_has_agent() {
  local root_pid="$1" expected_python parent children_raw child child_exe
  local -a queue=() children=() argv=()
  expected_python="$(/usr/bin/readlink -f -- /usr/bin/python3 2>/dev/null)" || return 1
  queue=("$root_pid")

  while (( ${#queue[@]} > 0 )); do
    parent="${queue[0]}"
    queue=("${queue[@]:1}")
    children_raw=""
    if [[ -r "/proc/${parent}/task/${parent}/children" ]]; then
      IFS= read -r children_raw <"/proc/${parent}/task/${parent}/children" || true
    fi
    children=()
    IFS=' ' read -r -a children <<<"$children_raw"
    for child in "${children[@]}"; do
      [[ "$child" =~ ^[1-9][0-9]*$ ]] || continue
      queue+=("$child")
      child_exe="$(/usr/bin/readlink -f -- "/proc/${child}/exe" 2>/dev/null)" || continue
      [[ "$child_exe" == "$expected_python" ]] || continue
      argv=()
      mapfile -d '' -t argv <"/proc/${child}/cmdline" 2>/dev/null || continue
      if [[ "${argv[0]:-}" == /usr/bin/python3 \
        && "${argv[1]:-}" == -I \
        && "${argv[2]:-}" == "${AWTARCHY_POLKIT_RUNTIME_DIR}/agent.py" ]];
      then
        return 0
      fi
    done
  done
  return 1
}

awtarchy_polkit_verify_service_process() {
  local pid resolved expected_alacritty
  pid="$(awtarchy_polkit_user_command /usr/bin/systemctl --user show -p MainPID --value "$AWTARCHY_POLKIT_SERVICE_NAME" 2>/dev/null)" || return 1
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  expected_alacritty="$(/usr/bin/readlink -f -- /usr/bin/alacritty 2>/dev/null)" || return 1
  resolved="$(/usr/bin/readlink -f -- "/proc/${pid}/exe" 2>/dev/null)" || return 1
  [[ "$resolved" == "$expected_alacritty" ]] || return 1
  awtarchy_polkit_process_tree_has_agent "$pid"
}''',
)

if "shell.qml" in text or "window-guard.sh" in text or "/usr/bin/quickshell ]]" in text:
    raise SystemExit("obsolete Quickshell PolicyKit runtime reference remains after patch")

path.write_text(text, encoding="utf-8")

security_path = Path("tests/test-polkit-agent-secure.sh")
security = security_path.read_text(encoding="utf-8")
old_security = "    reject_regex \"$LAUNCHER\" 'quickshell|QML_IMPORT_PATH|QML2_IMPORT_PATH'\n"
new_security = "    reject_regex \"$LAUNCHER\" '/usr/bin/quickshell|quickshell[[:space:]].*--config|shell\\.qml'\n"
if security.count(old_security) != 1:
    raise SystemExit("launcher Quickshell security assertion: expected exactly one match")
security_path.write_text(security.replace(old_security, new_security, 1), encoding="utf-8")
