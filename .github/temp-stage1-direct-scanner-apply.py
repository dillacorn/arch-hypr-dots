from pathlib import Path
import re

path = Path("local/share/awtarchy/awtarchy-runtime.sh")
text = path.read_text(encoding="utf-8")


def replace_function(source: str, name: str, replacement: str) -> str:
    pattern = re.compile(rf"(?ms)^{re.escape(name)}\(\)\s*\{{\n.*?^\}}\n")
    matches = list(pattern.finditer(source))
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one {name}() function, found {len(matches)}")
    return source[: matches[0].start()] + replacement.rstrip() + "\n" + source[matches[0].end() :]


text = replace_function(
    text,
    "ensure_aur_sudo_access",
    r'''ensure_aur_sudo_access() {
  command -v sudo >/dev/null 2>&1 \
    || die "sudo is required for AUR package transactions."
  log "Confirming the target user's normal sudo authorization for AUR package installation..."
  if ! run_as_target sudo -v; then
    die "AUR installation requires the target user's normal sudo authorization."
  fi
}''',
)

text = replace_function(
    text,
    "ensure_aur_guard_requirements",
    r'''ensure_aur_install_requirements() {
  log "Installing AUR package build requirements..."
  pacman -S --needed --noconfirm base-devel git gnupg
}''',
)

# Delete the installer-side bridge that sourced AurGuard out of the managed bashrc.
bridge_pattern = re.compile(r"(?ms)^run_aur_guard_as_target\(\)\s*\{\n.*?^\}\n")
bridge_matches = list(bridge_pattern.finditer(text))
if len(bridge_matches) != 1:
    raise SystemExit(f"expected one run_aur_guard_as_target() bridge, found {len(bridge_matches)}")
text = text[: bridge_matches[0].start()] + text[bridge_matches[0].end() :]

text = replace_function(
    text,
    "ensure_yay",
    r'''ensure_yay() {
  local tmp pkg

  if [[ -x /usr/bin/yay ]] && run_as_target /usr/bin/yay --version >/dev/null 2>&1; then
    return 0
  fi

  warn "yay not found. Bootstrapping the standard AUR helper..."
  tmp="$(run_as_target mktemp -d)" || die "Could not create a temporary yay build directory."

  if ! run_as_target git clone --depth 1 https://aur.archlinux.org/yay.git "${tmp}/yay"; then
    rm -rf -- "$tmp"
    die "Failed to download yay from the AUR."
  fi

  if ! run_as_target bash --noprofile --norc -c \
      'cd -- "$1" && makepkg -s --noconfirm --needed' awtarchy-yay "${tmp}/yay"; then
    rm -rf -- "$tmp"
    die "Failed to build yay."
  fi

  pkg="$(find "${tmp}/yay" -maxdepth 1 -type f -name 'yay-*.pkg.tar*' ! -name '*-debug*' -print -quit)"
  if [[ -z "$pkg" ]]; then
    rm -rf -- "$tmp"
    die "Built yay package archive was not found."
  fi

  if ! pacman -U --noconfirm --needed "$pkg"; then
    rm -rf -- "$tmp"
    die "Failed to install yay."
  fi
  rm -rf -- "$tmp"

  [[ -x /usr/bin/yay ]] && run_as_target /usr/bin/yay --version >/dev/null 2>&1 \
    || die "yay bootstrap completed without a usable /usr/bin/yay."
}''',
)

# Insert the upstream scanner bootstrap and the single normal AUR write helper.
anchor = '''ensure_yay() {'''
start = text.index(anchor)
match = re.search(r"(?ms)^ensure_yay\(\)\s*\{\n.*?^\}\n", text[start:])
if match is None:
    raise SystemExit("could not locate rewritten ensure_yay()")
insert_at = start + match.end()
scanner_helpers = r'''

ensure_aur_scanner() {
  if [[ -x /usr/bin/aur-scan ]] \
      && run_as_target /usr/bin/aur-scan --version >/dev/null 2>&1; then
    return 0
  fi

  ensure_aur_install_requirements
  ensure_aur_sudo_access
  ensure_yay

  log "Installing stable aur-scanner through yay for the initial bootstrap..."
  if ! run_as_target /usr/bin/yay -S --noconfirm aur-scanner; then
    die "Failed to bootstrap stable aur-scanner."
  fi

  [[ -x /usr/bin/aur-scan ]] \
    && run_as_target /usr/bin/aur-scan --version >/dev/null 2>&1 \
    || die "aur-scanner installed without a usable /usr/bin/aur-scan."
}

install_aur_with_scanner() {
  (( $# > 0 )) || return 0

  if (( DRY_RUN == 1 )); then
    log "DRY-RUN: would run aur-scan install for: $*"
    return 0
  fi

  ensure_aur_scanner
  run_as_target /usr/bin/aur-scan install "$@" --noconfirm
}
'''
text = text[:insert_at] + scanner_helpers + text[insert_at:]

# OBS package path: scanner first, then preserve the existing upstream plugin fallback.
text = text.replace(
    '  if run_aur_guard_as_target aurinstall "$pkg"; then\n    return 0\n  fi\n\n  warn "${pkg} failed through AUR Guard. Falling back to upstream per-user OBS plugin install."',
    '  if install_aur_with_scanner "$pkg"; then\n    return 0\n  fi\n\n  warn "${pkg} failed through aur-scanner. Falling back to upstream per-user OBS plugin install."',
    1,
)

# Main selected-package stage.
text = text.replace("  ensure_aur_guard_requirements\n", "  ensure_aur_install_requirements\n", 1)
stage_preamble = "  ensure_aur_install_requirements\n  ensure_aur_sudo_access\n  ensure_yay\n"
if text.count(stage_preamble) != 1:
    raise SystemExit("could not locate installer AUR stage preamble")
text = text.replace(stage_preamble, stage_preamble + "  ensure_aur_scanner\n", 1)
text = text.replace(
    '    log "Installing selected AUR packages through AUR Guard practical mode..."',
    '    log "Installing selected AUR packages through upstream aur-scanner..."',
    1,
)
old_selected = '''        if [[ "$pkg" == "obs-pipewire-audio-capture" ]]; then
          install_obs_pipewire_audio_capture_package
        else
          run_aur_guard_as_target aurinstall "$pkg"
        fi
        printf '%s\n' "${COLOR_GREEN}${pkg} installed successfully.${COLOR_RESET}"'''
new_selected = '''        if [[ "$pkg" == "obs-pipewire-audio-capture" ]]; then
          if ! install_obs_pipewire_audio_capture_package; then
            warn "AUR package failed: ${pkg}. Continuing with remaining selections."
            continue
          fi
        elif ! install_aur_with_scanner "$pkg"; then
          warn "AUR package failed: ${pkg}. Continuing with remaining selections."
          continue
        fi
        if ! aur_selected_package_installed "$pkg"; then
          warn "aur-scanner returned success but ${pkg} is still not detected. Continuing with remaining selections."
          continue
        fi
        printf '%s\n' "${COLOR_GREEN}${pkg} installed successfully.${COLOR_RESET}"'''
if text.count(old_selected) != 1:
    raise SystemExit("could not locate selected AUR install block")
text = text.replace(old_selected, new_selected, 1)

text = text.replace(
    '      log "Installing tlpui through AUR Guard practical mode..."\n      if run_aur_guard_as_target aurinstall tlpui && pacman -Qq tlpui >/dev/null 2>&1; then',
    '      log "Installing tlpui through upstream aur-scanner..."\n      if install_aur_with_scanner tlpui && pacman -Qq tlpui >/dev/null 2>&1; then',
    1,
)

# GPU legacy branches already have their own before/after managed-package accounting.
# Replace only the transaction engine so that bookkeeping remains unchanged.
old_gpu_transaction = '''  if have paru; then
    as_user paru -S --needed --noconfirm "$@"
  elif have yay; then
    as_user yay -S --needed --noconfirm "$@"
  else
    bootstrap_yay
    as_user yay -S --needed --noconfirm "$@"
  fi'''
if text.count(old_gpu_transaction) != 1:
    raise SystemExit("could not locate GPU AUR helper transaction block")
text = text.replace(old_gpu_transaction, '  install_aur_with_scanner "$@"', 1)

# The two GPU callers no longer need to pre-bootstrap yay; scanner bootstrap owns that.
for name in ("install_nvidia_580xx_stack", "install_nvidia_legacy_branch"):
    pattern = re.compile(rf"(?ms)^{name}\(\)\s*\{{\n.*?^\}}\n")
    match = pattern.search(text)
    if match is None:
        raise SystemExit(f"missing {name}()")
    function_text = match.group(0)
    if "  bootstrap_yay\n" not in function_text:
        raise SystemExit(f"{name}() did not contain expected yay bootstrap")
    replacement = function_text.replace("  bootstrap_yay\n", "  ensure_aur_scanner\n", 1)
    text = text[: match.start()] + replacement + text[match.end() :]

# Stage 1 must leave no installer invocation of AurGuard.
if "run_aur_guard_as_target" in text:
    raise SystemExit("run_aur_guard_as_target remains after Stage 1 rewrite")
if "run_aur_guard_as_target aurinstall" in text:
    raise SystemExit("aurinstall invocation remains after Stage 1 rewrite")

path.write_text(text, encoding="utf-8")
