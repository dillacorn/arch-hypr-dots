from pathlib import Path

path = Path("local/share/awtarchy/awtarchy-runtime.sh")
text = path.read_text(encoding="utf-8")

anchor = "multilib_enabled_update() {\n"
if text.count(anchor) != 1:
    raise SystemExit("unexpected updater hardware helper anchor")

helpers = r'''target_uses_direct_aur_scanner() {
  local target_home="$1"
  local target_bashrc="${target_home}/.bashrc"

  [[ -f "$target_bashrc" && ! -L "$target_bashrc" ]] || return 1
  grep -Fq 'github.com/dillacorn/awtarchy' "$target_bashrc" || return 1
  grep -Fq 'aur-scan' "$target_bashrc" || return 1
  if grep -Eq '^(aurguard|aurverify|aurinstall)[[:space:]]*\(\)' "$target_bashrc"; then
    return 1
  fi
}

ensure_update_aur_scanner() {
  if [[ -x /usr/bin/aur-scan ]] && /usr/bin/aur-scan --version >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -x /usr/bin/yay ]] || ! /usr/bin/yay --version >/dev/null 2>&1; then
    warn "The direct aur-scanner shell is ready to migrate, but /usr/bin/aur-scan is missing and a usable /usr/bin/yay is unavailable for bootstrap."
    return 1
  fi

  log "Installing stable aur-scanner before replacing the AurGuard-era shell..."
  if ! /usr/bin/yay -S --noconfirm --pgpfetch aur-scanner; then
    warn "Failed to bootstrap stable aur-scanner; the managed shell has not been migrated."
    return 1
  fi

  if [[ ! -x /usr/bin/aur-scan ]] || ! /usr/bin/aur-scan --version >/dev/null 2>&1; then
    warn "aur-scanner bootstrap completed without a usable /usr/bin/aur-scan."
    return 1
  fi
}

'''
text = text.replace(anchor, helpers + anchor, 1)

old = '''  if [[ "$UPDATE_MODE" == "preserve" ]]; then
    log "Selected update mode: preserve hyprland.lua; update other managed files"
  else
    log "Selected update mode: clean"
  fi

  if [[ ${AWTARCHY_TEST_SKIP_SCXCTL_HELPER_REPAIR:-0} != 1 ]]; then'''
new = '''  if [[ "$UPDATE_MODE" == "preserve" ]]; then
    log "Selected update mode: preserve hyprland.lua; update other managed files"
  else
    log "Selected update mode: clean"
  fi

  if target_uses_direct_aur_scanner "$target_home"; then
    ensure_update_aur_scanner \
      || die "aur-scanner is required before replacing the AurGuard-era managed shell. No managed files were changed."
  fi

  if [[ ${AWTARCHY_TEST_SKIP_SCXCTL_HELPER_REPAIR:-0} != 1 ]]; then'''
if text.count(old) != 1:
    raise SystemExit("unexpected updater pre-apply boundary")
text = text.replace(old, new, 1)

if text.index('ensure_update_aur_scanner \\\n      || die') > text.index('apply_plan "$plan_file"'):
    raise SystemExit("scanner prerequisite landed after managed-file application")

path.write_text(text, encoding="utf-8")
