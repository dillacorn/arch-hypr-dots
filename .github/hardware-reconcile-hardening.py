from pathlib import Path

path = Path("local/share/awtarchy/awtarchy-runtime.sh")
text = path.read_text(encoding="utf-8")

anchor = '''managed_package_recorded() {
'''
helper = r'''atomic_update_root_file_from_stdin() {
  local mode="$1" uid="$2" gid="$3" dest="$4"
  local dir tmp=""

  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
  [[ "$uid" =~ ^[0-9]+$ && "$gid" =~ ^[0-9]+$ ]] || return 1
  [[ "$dest" == /* && "$dest" != *$'\n'* && "$dest" != *$'\r'* ]] || return 1

  dir="${dest%/*}"
  run_update_root /usr/bin/test -d "$dir" || return 1
  if ! run_update_root /usr/bin/test ! -L "$dir"; then
    warn "Refusing root write through symbolic-link directory: ${dir}"
    return 1
  fi
  if run_update_root /usr/bin/test -L "$dest"; then
    warn "Refusing root write to symbolic-link destination: ${dest}"
    return 1
  fi

  tmp="$(run_update_root /usr/bin/mktemp "${dir}/.awtarchy-write.XXXXXX")" || return 1
  if ! run_update_root /usr/bin/tee "$tmp" >/dev/null; then
    run_update_root /usr/bin/rm -f -- "$tmp" || true
    return 1
  fi
  if ! run_update_root /usr/bin/chmod "$mode" "$tmp" \
    || ! run_update_root /usr/bin/chown "${uid}:${gid}" "$tmp" \
    || ! run_update_root /usr/bin/mv -Tf -- "$tmp" "$dest";
  then
    run_update_root /usr/bin/rm -f -- "$tmp" || true
    return 1
  fi
}

'''
if "atomic_update_root_file_from_stdin() {" not in text:
    if text.count(anchor) != 1:
        raise SystemExit("expected one managed_package_recorded anchor")
    text = text.replace(anchor, helper + anchor, 1)

old = '''  if ! run_update_root /usr/bin/install -m 0644 "$tmp" "$manifest"; then
    rm -f -- "$tmp"
    return 1
  fi
'''
new = '''  if ! cat -- "$tmp" | atomic_update_root_file_from_stdin 0644 0 0 "$manifest"; then
    rm -f -- "$tmp"
    return 1
  fi
'''
if text.count(old) != 1:
    raise SystemExit("expected one removal ledger install")
text = text.replace(old, new, 1)

old = '''  if ! run_update_root /usr/bin/install -d -m 0755 "$(dirname "$manifest")" \\
    || ! run_update_root /usr/bin/install -m 0644 "$tmp" "$manifest";
  then
    rm -f -- "$tmp"
    return 1
  fi
'''
new = '''  if ! run_update_root /usr/bin/install -d -m 0755 "$(dirname "$manifest")" \\
    || ! cat -- "$tmp" | atomic_update_root_file_from_stdin 0644 0 0 "$manifest";
  then
    rm -f -- "$tmp"
    return 1
  fi
'''
if text.count(old) != 1:
    raise SystemExit("expected one record ledger install")
text = text.replace(old, new, 1)

text = text.replace(
    '  local changed=0 file tmp mode backup source_tmp\n',
    '  local changed=0 file tmp mode uid gid backup source_tmp\n',
    1,
)

old = '''    mode="$(run_update_root /usr/bin/stat -c '%a' -- "$file")"
    backup="${file}.backup.$(stamp)"
    run_update_root /usr/bin/cp -a -- "$file" "$backup"
    run_update_root /usr/bin/install -m "$mode" "$tmp" "$file"
    rm -f -- "$tmp"
'''
new = '''    mode="$(run_update_root /usr/bin/stat -c '%a' -- "$file")"
    uid="$(run_update_root /usr/bin/stat -c '%u' -- "$file")"
    gid="$(run_update_root /usr/bin/stat -c '%g' -- "$file")"
    backup="${file}.backup.$(stamp)"
    run_update_root /usr/bin/cp -a -- "$file" "$backup"
    if ! cat -- "$tmp" | atomic_update_root_file_from_stdin "$mode" "$uid" "$gid" "$file"; then
      rm -f -- "$tmp"
      return 1
    fi
    rm -f -- "$tmp"
'''
if text.count(old) != 1:
    raise SystemExit("expected one boot file install block")
text = text.replace(old, new, 1)

old = '''    mode="$(run_update_root /usr/bin/stat -c '%a' -- /etc/mkinitcpio.conf)"
    backup="/etc/mkinitcpio.conf.backup.$(stamp)"
    run_update_root /usr/bin/cp -a -- /etc/mkinitcpio.conf "$backup"
    run_update_root /usr/bin/install -m "$mode" "$tmp" /etc/mkinitcpio.conf
    rm -f -- "$source_tmp" "$tmp"
'''
new = '''    mode="$(run_update_root /usr/bin/stat -c '%a' -- /etc/mkinitcpio.conf)"
    uid="$(run_update_root /usr/bin/stat -c '%u' -- /etc/mkinitcpio.conf)"
    gid="$(run_update_root /usr/bin/stat -c '%g' -- /etc/mkinitcpio.conf)"
    backup="/etc/mkinitcpio.conf.backup.$(stamp)"
    run_update_root /usr/bin/cp -a -- /etc/mkinitcpio.conf "$backup"
    if ! cat -- "$tmp" | atomic_update_root_file_from_stdin "$mode" "$uid" "$gid" /etc/mkinitcpio.conf; then
      rm -f -- "$source_tmp" "$tmp"
      return 1
    fi
    rm -f -- "$source_tmp" "$tmp"
'''
if text.count(old) != 1:
    raise SystemExit("expected one mkinitcpio install block")
text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
