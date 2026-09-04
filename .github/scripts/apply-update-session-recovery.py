#!/usr/bin/env python3

from pathlib import Path

launcher_path = Path("local/bin/awtarchy")
notifier_path = Path("config/hypr/scripts/quickshell_update_notifications.sh")
launcher = launcher_path.read_text(encoding="utf-8")
notifier = notifier_path.read_text(encoding="utf-8")

if "start_update_privilege_session()" not in launcher:
    old = '''GIT_TEST_STATE_FILE=""

log()  { printf '%s\\n' "$*"; }
die()  { printf 'ERROR: %s\\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
'''
    new = '''GIT_TEST_STATE_FILE=""
UPDATE_SUDO_KEEPALIVE_PID=""

log()  { printf '%s\\n' "$*"; }
die()  { printf 'ERROR: %s\\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

stop_update_privilege_session() {
  local pid="${UPDATE_SUDO_KEEPALIVE_PID:-}"
  UPDATE_SUDO_KEEPALIVE_PID=""
  [[ $pid =~ ^[1-9][0-9]*$ ]] || return 0
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" 2>/dev/null || true
}

start_update_privilege_session() {
  (( EUID != 0 )) || return 0
  have sudo || die "sudo is required for Awtarchy updates."

  log "Authorizing privileged Awtarchy update actions..."
  sudo -v || die "sudo authentication failed; no update changes were applied."

  (
    while sleep "${AWTARCHY_SUDO_KEEPALIVE_SECONDS:-45}"; do
      sudo -n -v >/dev/null 2>&1 || break
    done
  ) &
  UPDATE_SUDO_KEEPALIVE_PID=$!
}

root_free_mib() {
  local available_kib=""
  available_kib="$(/usr/bin/df -Pk / 2>/dev/null | awk 'NR == 2 { print $4 }')"
  [[ $available_kib =~ ^[0-9]+$ ]] || return 1
  printf '%s\\n' "$(( available_kib / 1024 ))"
}

ensure_update_disk_headroom() {
  local preferred_mib="${AWTARCHY_UPDATE_PREFERRED_FREE_MIB:-4096}"
  local required_mib="${AWTARCHY_UPDATE_REQUIRED_FREE_MIB:-1024}"
  local free_mib="" paccache_bin=""

  [[ $preferred_mib =~ ^[0-9]+$ && $required_mib =~ ^[0-9]+$ ]] \\
    || die "Invalid update disk-space threshold override."
  (( preferred_mib >= required_mib )) \\
    || die "Preferred update disk-space threshold cannot be below the required threshold."

  free_mib="$(root_free_mib)" \\
    || die "Could not determine free space on the root filesystem."
  (( free_mib >= preferred_mib )) && return 0

  for paccache_bin in /usr/bin/paccache /usr/sbin/paccache; do
    [[ -x $paccache_bin ]] && break
    paccache_bin=""
  done

  if [[ -n $paccache_bin ]]; then
    log "Root filesystem has ${free_mib} MiB free; pruning old pacman cache entries while keeping two package versions..."
    if ! sudo -n "$paccache_bin" -rk2; then
      printf 'WARN: Automatic pacman cache pruning failed; continuing with the remaining free space.\\n' >&2
    fi
    free_mib="$(root_free_mib)" \\
      || die "Could not re-check free space after pacman cache pruning."
  fi

  (( free_mib >= required_mib )) \\
    || die "Root filesystem has only ${free_mib} MiB free; at least ${required_mib} MiB is required before continuing the update."

  if (( free_mib < preferred_mib )); then
    printf 'WARN: Root filesystem has %s MiB free; continuing above the %s MiB hard minimum.\\n' \\
      "$free_mib" "$required_mib" >&2
  fi
}
'''
    if launcher.count(old) != 1:
        raise SystemExit("launcher preamble changed; refusing automatic patch")
    launcher = launcher.replace(old, new, 1)

    old_update = '''    update)
      reject_stable_testing_overrides "$@"
      protect_git_state_before_updater_refresh "$@"
      ensure_latest_updater "$@"
      shift
      offer_package_reconciliation_before_update "$@"
      config_release_ready_or_noop "$@" || return 0
      run_runtime update-reset-backup --mode preserve "$@"
      reconcile_quickshell_ui_after_update
      ;;
'''
    new_update = '''    update)
      reject_stable_testing_overrides "$@"
      protect_git_state_before_updater_refresh "$@"
      ensure_latest_updater "$@"
      shift
      start_update_privilege_session
      trap stop_update_privilege_session EXIT HUP INT TERM
      ensure_update_disk_headroom
      offer_package_reconciliation_before_update "$@"
      ensure_update_disk_headroom
      if ! config_release_ready_or_noop "$@"; then
        stop_update_privilege_session
        trap - EXIT HUP INT TERM
        return 0
      fi
      run_runtime update-reset-backup --mode preserve "$@"
      reconcile_quickshell_ui_after_update
      stop_update_privilege_session
      trap - EXIT HUP INT TERM
      ;;
'''
    if launcher.count(old_update) != 1:
        raise SystemExit("stable update command arm changed; refusing automatic patch")
    launcher = launcher.replace(old_update, new_update, 1)

old_launch = '''        "$DEFAULT_TERMINAL" \\
            --class awtarchy-update \\
            --hold \\
            --no-profile \\
            -- \\
            "$SCRIPT_PATH" run-stable-update "$notification_id" "$target"
'''
new_launch = '''        /usr/bin/setsid -f --wait "$DEFAULT_TERMINAL" \\
            --class awtarchy-update \\
            --hold \\
            --no-profile \\
            -- \\
            "$SCRIPT_PATH" run-stable-update "$notification_id" "$target"
'''
old_other = '''        "$DEFAULT_TERMINAL" \\
            --class awtarchy-update \\
            --hold \\
            --no-profile \\
            -- \\
            awtarchy "$command"
'''
new_other = '''        /usr/bin/setsid -f --wait "$DEFAULT_TERMINAL" \\
            --class awtarchy-update \\
            --hold \\
            --no-profile \\
            -- \\
            awtarchy "$command"
'''
if "/usr/bin/setsid -f --wait" not in notifier:
    if notifier.count(old_launch) != 1 or notifier.count(old_other) != 1:
        raise SystemExit("notification launch path changed; refusing automatic patch")
    notifier = notifier.replace(old_launch, new_launch, 1)
    notifier = notifier.replace(old_other, new_other, 1)

launcher_path.write_text(launcher, encoding="utf-8")
notifier_path.write_text(notifier, encoding="utf-8")
