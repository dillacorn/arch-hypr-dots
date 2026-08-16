from pathlib import Path

runtime = Path("local/share/awtarchy/awtarchy-runtime.sh")
text = runtime.read_text(encoding="utf-8")


def replace_section(start: str, end: str, replacement: str) -> None:
    global text
    start_i = text.find(start)
    if start_i < 0:
        raise SystemExit(f"missing start marker: {start!r}")
    end_i = text.find(end, start_i)
    if end_i < 0:
        raise SystemExit(f"missing end marker: {end!r}")
    text = text[:start_i] + replacement.rstrip() + "\n\n" + text[end_i:]


helper_anchor = '''managed_package_recorded() {
'''
helper = r'''run_update_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
    return
  fi

  have sudo || {
    warn "sudo is required for hardware system reconciliation."
    return 1
  }
  sudo -- "$@"
}

'''
if "run_update_root() {" not in text:
    if text.count(helper_anchor) != 1:
        raise SystemExit("expected one managed_package_recorded anchor")
    text = text.replace(helper_anchor, helper + helper_anchor, 1)

replace_section(
    "remove_managed_packages_matching() {\n",
    "record_managed_packages() {\n",
    r'''remove_managed_packages_matching() {
  local label="$1" regex="$2"
  local manifest tmp pkg
  local -a pkgs=()

  manifest="$(managed_packages_file)"
  [[ -r "$manifest" ]] || {
    warn "No Awtarchy package ownership manifest exists; refusing automatic ${label} package removal."
    return 0
  }

  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    [[ "$pkg" =~ $regex ]] || continue
    pacman -Qq "$pkg" >/dev/null 2>&1 && pkgs+=("$pkg")
  done <"$manifest"

  (( ${#pkgs[@]} )) || return 0
  printf '%s\n' "${label} packages installed by Awtarchy:" >&2
  printf '  %s\n' "${pkgs[@]}" >&2
  ask_yes_no "Remove these obsolete ${label} packages?" || return 0

  run_update_root /usr/bin/pacman -Rns --noconfirm "${pkgs[@]}"

  tmp="$(mktemp)"
  grep -Fvx -f <(printf '%s\n' "${pkgs[@]}") "$manifest" >"$tmp" || true
  if ! run_update_root /usr/bin/install -m 0644 "$tmp" "$manifest"; then
    rm -f -- "$tmp"
    return 1
  fi
  rm -f -- "$tmp"
}''',
)

replace_section(
    "record_managed_packages() {\n",
    "install_managed_pacman_packages() {\n",
    r'''record_managed_packages() {
  local manifest package tmp
  manifest="$(managed_packages_file)"
  tmp="$(mktemp)"

  if [[ -r "$manifest" ]]; then
    cat -- "$manifest" >"$tmp"
  else
    : >"$tmp"
  fi

  for package in "$@"; do
    [[ -n "$package" ]] || continue
    pacman -Qq "$package" >/dev/null 2>&1 || continue
    grep -Fxq "$package" "$tmp" || printf '%s\n' "$package" >>"$tmp"
  done
  LC_ALL=C sort -u -o "$tmp" "$tmp"

  if ! run_update_root /usr/bin/install -d -m 0755 "$(dirname "$manifest")" \
    || ! run_update_root /usr/bin/install -m 0644 "$tmp" "$manifest";
  then
    rm -f -- "$tmp"
    return 1
  fi
  rm -f -- "$tmp"
}''',
)

replace_section(
    "install_managed_pacman_packages() {\n",
    "multilib_enabled_update() {\n",
    r'''install_managed_pacman_packages() {
  local label="$1"
  shift
  local -a requested=("$@") missing=()
  local package

  command -v pacman >/dev/null 2>&1 || return 0

  for package in "${requested[@]}"; do
    pacman -Qq "$package" >/dev/null 2>&1 || missing+=("$package")
  done
  (( ${#missing[@]} )) || return 0

  printf '%s\n' "Required ${label} packages are missing:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  ask_yes_no "Install the missing ${label} packages?" || return 0
  run_update_root /usr/bin/pacman -S --needed --noconfirm "${missing[@]}"
  record_managed_packages "${missing[@]}"
}''',
)

old_guard = r'''ensure_current_hardware_packages() {
  [[ "${EUID}" -eq 0 ]] || {
    warn "Hardware package reconciliation requires sudo/root."
    return 0
  }
  command -v pacman >/dev/null 2>&1 || return 0
'''
new_guard = r'''ensure_current_hardware_packages() {
  command -v pacman >/dev/null 2>&1 || return 0
'''
if text.count(old_guard) != 1:
    raise SystemExit("expected one hardware reconciliation root guard")
text = text.replace(old_guard, new_guard, 1)

text = text.replace(
    "      systemctl enable --now tlp.service || true\n",
    "      run_update_root /usr/bin/systemctl enable --now tlp.service || true\n",
    1,
)
text = text.replace(
    "        systemctl enable --now thermald.service || true\n",
    "        run_update_root /usr/bin/systemctl enable --now thermald.service || true\n",
    1,
)

replace_section(
    "remove_exact_nvidia_files() {\n",
    "remove_nvidia_boot_entries() {\n",
    r'''remove_exact_nvidia_files() {
  local file normalized
  for file in /etc/modprobe.d/nvidia-drm.conf /etc/modprobe.d/blacklist-nouveau.conf; do
    [[ -e "$file" ]] || continue
    if [[ -L "$file" ]]; then
      warn "Leaving symbolic-link NVIDIA system file untouched: $file"
      continue
    fi
    normalized="$(run_update_root /usr/bin/cat -- "$file" 2>/dev/null | sed '/^[[:space:]]*$/d' | sed 's/[[:space:]]*$//')" || continue
    case "$file:$normalized" in
      "/etc/modprobe.d/nvidia-drm.conf:options nvidia_drm modeset=1")
        run_update_root /usr/bin/rm -f -- "$file"
        ;;
      "/etc/modprobe.d/blacklist-nouveau.conf:"$'blacklist nouveau\noptions nouveau modeset=0')
        run_update_root /usr/bin/rm -f -- "$file"
        ;;
      *)
        warn "Leaving modified NVIDIA system file untouched: $file"
        ;;
    esac
  done
}''',
)

replace_section(
    "remove_nvidia_boot_entries() {\n",
    "hardware_reconcile() {\n",
    r'''remove_nvidia_boot_entries() {
  local changed=0 file tmp mode backup source_tmp
  local -a files=()

  if run_update_root /usr/bin/test -d /boot/loader/entries; then
    while IFS= read -r -d '' file; do
      files+=("$file")
    done < <(run_update_root /usr/bin/find /boot/loader/entries -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null || true)
  fi

  for file in /etc/default/grub /boot/limine/limine.conf /boot/limine.conf /boot/EFI/limine/limine.conf /boot/limine/limine.cfg /boot/limine.cfg; do
    run_update_root /usr/bin/test -f "$file" && files+=("$file")
  done

  for file in "${files[@]}"; do
    run_update_root /usr/bin/test ! -L "$file" || {
      warn "Leaving symbolic-link bootloader file untouched: $file"
      continue
    }
    run_update_root /usr/bin/grep -Eq 'nvidia[-_]drm\.modeset=1' "$file" || continue

    tmp="$(mktemp)"
    run_update_root /usr/bin/cat -- "$file" \
      | sed -E 's/(^|[[:space:]])nvidia[-_]drm\.modeset=1([[:space:]]|$)/ /g; s/[[:space:]]+/ /g; s/ =/=/g; s/[[:space:]]+$//' \
      >"$tmp"
    mode="$(run_update_root /usr/bin/stat -c '%a' -- "$file")"
    backup="${file}.backup.$(stamp)"
    run_update_root /usr/bin/cp -a -- "$file" "$backup"
    run_update_root /usr/bin/install -m "$mode" "$tmp" "$file"
    rm -f -- "$tmp"
    changed=1
  done

  if run_update_root /usr/bin/test -f /etc/mkinitcpio.conf \
    && run_update_root /usr/bin/test ! -L /etc/mkinitcpio.conf \
    && run_update_root /usr/bin/grep -Eq 'MODULES=.*nvidia' /etc/mkinitcpio.conf;
  then
    source_tmp="$(mktemp)"
    tmp="$(mktemp)"
    run_update_root /usr/bin/cat -- /etc/mkinitcpio.conf >"$source_tmp"
    python3 - "$source_tmp" "$tmp" <<'PY'
from pathlib import Path
import re, sys
source = Path(sys.argv[1])
out_path = Path(sys.argv[2])
remove = {"nvidia", "nvidia_modeset", "nvidia_uvm", "nvidia_drm"}
out = []
for line in source.read_text().splitlines():
    m = re.match(r'^(\s*MODULES=\()(.*)(\)\s*)$', line)
    if m:
        words = [w for w in m.group(2).split() if w not in remove]
        line = m.group(1) + " ".join(words) + m.group(3)
    out.append(line)
out_path.write_text("\n".join(out) + "\n")
PY
    mode="$(run_update_root /usr/bin/stat -c '%a' -- /etc/mkinitcpio.conf)"
    backup="/etc/mkinitcpio.conf.backup.$(stamp)"
    run_update_root /usr/bin/cp -a -- /etc/mkinitcpio.conf "$backup"
    run_update_root /usr/bin/install -m "$mode" "$tmp" /etc/mkinitcpio.conf
    rm -f -- "$source_tmp" "$tmp"
    changed=1
  fi

  if (( changed == 1 )); then
    if command -v grub-mkconfig >/dev/null 2>&1 && run_update_root /usr/bin/test -f /boot/grub/grub.cfg; then
      run_update_root /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg || true
    fi
    if command -v mkinitcpio >/dev/null 2>&1; then
      run_update_root /usr/bin/mkinitcpio -P
    elif command -v dracut >/dev/null 2>&1; then
      run_update_root /usr/bin/dracut --regenerate-all --force
    fi
  fi
}''',
)

old_thermald = '''      if [[ "${EUID}" -eq 0 ]] && systemctl is-enabled thermald.service >/dev/null 2>&1; then
        systemctl disable --now thermald.service || true
      fi
'''
new_thermald = '''      if systemctl is-enabled thermald.service >/dev/null 2>&1; then
        run_update_root /usr/bin/systemctl disable --now thermald.service || true
      fi
'''
if text.count(old_thermald) != 1:
    raise SystemExit("expected one thermald cleanup block")
text = text.replace(old_thermald, new_thermald, 1)

old_tlp = '''      if [[ "${EUID}" -eq 0 ]] && systemctl is-enabled tlp.service >/dev/null 2>&1; then
        systemctl disable --now tlp.service || true
      fi
'''
new_tlp = '''      if systemctl is-enabled tlp.service >/dev/null 2>&1; then
        run_update_root /usr/bin/systemctl disable --now tlp.service || true
      fi
'''
if text.count(old_tlp) != 1:
    raise SystemExit("expected one TLP cleanup block")
text = text.replace(old_tlp, new_tlp, 1)

runtime.write_text(text, encoding="utf-8")

workflow = Path(".github/workflows/validate-awtarchy.yml")
w = workflow.read_text(encoding="utf-8")
for anchor, line in [
    ("          bash -n tests/test-hybrid-brightness.sh\n", "          bash -n tests/test-hardware-reconcile-sudo.sh\n"),
    ("            tests/test-hybrid-brightness.sh \\\n", "            tests/test-hardware-reconcile-sudo.sh \\\n"),
    ("          bash tests/test-hybrid-brightness.sh\n", "          bash tests/test-hardware-reconcile-sudo.sh\n"),
]:
    if line not in w:
        if w.count(anchor) != 1:
            raise SystemExit(f"expected one workflow anchor: {anchor!r}")
        w = w.replace(anchor, anchor + line, 1)
workflow.write_text(w, encoding="utf-8")
