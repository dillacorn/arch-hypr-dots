from pathlib import Path
import re

reconciler_path = Path("local/share/awtarchy/awtarchy-package-reconcile.sh")
test_path = Path("tests/test-package-reconciler-aur-equivalents.sh")
text = reconciler_path.read_text(encoding="utf-8")

old_state = 'SYSTEM_TYPE="unknown"\nLY_STATUS="not installed"\nAUR_HELPER=""\n'
new_state = '''SYSTEM_TYPE="unknown"
LY_STATUS="not installed"
AUR_SCAN_BIN="/usr/bin/aur-scan"
if [[ ${AWTARCHY_TEST_MODE:-0} == 1 && -n ${AWTARCHY_AUR_SCAN_BIN:-} ]]; then
  AUR_SCAN_BIN="$AWTARCHY_AUR_SCAN_BIN"
fi
'''
if text.count(old_state) != 1:
    raise SystemExit("unexpected reconciler AUR helper state block")
text = text.replace(old_state, new_state, 1)

start = text.index("aur_helper_usable() {")
end = text.index("record_managed_packages() {", start)
replacement = '''ensure_aur_scanner() {
  if [[ -x "$AUR_SCAN_BIN" ]] && "$AUR_SCAN_BIN" --version >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$AUR_SCAN_BIN" != /usr/bin/aur-scan ]]; then
    warn "Configured aur-scan test binary is unavailable: ${AUR_SCAN_BIN}"
    return 1
  fi

  if [[ ! -x /usr/bin/yay ]] || ! /usr/bin/yay --version >/dev/null 2>&1; then
    warn "aur-scanner is missing and a usable /usr/bin/yay is unavailable for the one-time bootstrap."
    return 1
  fi

  log "Installing stable aur-scanner through yay for the one-time bootstrap..."
  if ! /usr/bin/yay -S --noconfirm --pgpfetch aur-scanner; then
    warn "Failed to bootstrap stable aur-scanner."
    return 1
  fi

  if [[ ! -x /usr/bin/aur-scan ]] || ! /usr/bin/aur-scan --version >/dev/null 2>&1; then
    warn "aur-scanner installed without a usable /usr/bin/aur-scan."
    return 1
  fi

  AUR_SCAN_BIN="/usr/bin/aur-scan"
}

install_selected_aur_packages() {
  local pkg

  for pkg in "$@"; do
    if aur_package_satisfied "$pkg"; then
      log "${pkg} or an equivalent installation is already present; skipping."
      continue
    fi

    log "Installing AUR package through upstream aur-scanner: ${pkg}"
    if ! "$AUR_SCAN_BIN" install "$pkg" --noconfirm; then
      warn "AUR package failed: ${pkg}. Continuing with remaining package actions."
      FAILED_AUR+=("$pkg")
      continue
    fi

    if ! aur_package_satisfied "$pkg"; then
      warn "aur-scanner returned success but ${pkg} is still not detected. Continuing with remaining package actions."
      FAILED_AUR+=("$pkg")
      continue
    fi

    if ! record_managed_packages "$pkg"; then
      warn "${pkg} installed, but Awtarchy could not update its managed-package ledger."
    fi
  done

  return 0
}

'''
text = text[:start] + replacement + text[end:]

old_dispatch = '''if (( ${#selected_aur[@]} )); then
  if ensure_aur_helper; then
    install_selected_aur_packages "${selected_aur[@]}"
  else
    warn 'AUR helper is unavailable; recording selected AUR packages as failed and continuing with remaining package actions.'
    FAILED_AUR+=("${selected_aur[@]}")
  fi
fi'''
new_dispatch = '''if (( ${#selected_aur[@]} )); then
  if ensure_aur_scanner; then
    install_selected_aur_packages "${selected_aur[@]}"
  else
    warn 'aur-scanner is unavailable; recording selected AUR packages as failed and continuing with remaining package actions.'
    FAILED_AUR+=("${selected_aur[@]}")
  fi
fi'''
if text.count(old_dispatch) != 1:
    raise SystemExit("unexpected selected AUR dispatch block")
text = text.replace(old_dispatch, new_dispatch, 1)

for forbidden in ("AUR_HELPER=", "ensure_aur_helper()", "rebuild_aur_helper()", "aur_helper_usable()"):
    if forbidden in text:
        raise SystemExit(f"obsolete helper machinery remains: {forbidden}")

reconciler_path.write_text(text, encoding="utf-8")

test = test_path.read_text(encoding="utf-8")
anchor = 'export TEST_SCAN_LOG="$scan_log"\nexport AWTARCHY_AUR_SCAN_BIN="$fakebin/aur-scan"\n'
replacement_test = 'export TEST_SCAN_LOG="$scan_log"\nexport AWTARCHY_TEST_MODE=1\nexport AWTARCHY_AUR_SCAN_BIN="$fakebin/aur-scan"\n'
if test.count(anchor) != 1:
    raise SystemExit("unexpected reconciler test scanner environment block")
test_path.write_text(test.replace(anchor, replacement_test, 1), encoding="utf-8")
