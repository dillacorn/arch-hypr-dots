from pathlib import Path

path = Path("local/share/awtarchy/awtarchy-runtime.sh")
text = path.read_text(encoding="utf-8")

old_pkg = '  "Multimedia:ffmpeg avahi mpv cheese exiv2 zathura zathura-pdf-mupdf mousai"\n'
new_pkg = '  "Multimedia:ffmpeg avahi nss-mdns mpv cheese exiv2 zathura zathura-pdf-mupdf mousai"\n'
if text.count(old_pkg) != 1:
    raise SystemExit("expected one Multimedia package group")
text = text.replace(old_pkg, new_pkg, 1)

anchor = "clear_screen() {\n"
if text.count(anchor) != 1:
    raise SystemExit("expected one clear_screen function anchor")

function = r'''configure_mdns_stack() {
  local resolved_dir="/etc/systemd/resolved.conf.d"
  local resolved_file="${resolved_dir}/90-awtarchy-mdns.conf"
  local nsswitch="/etc/nsswitch.conf"
  local marker="# Managed by Awtarchy: Avahi owns mDNS/DNS-SD."
  local tmp="" nss_tmp="" backup="" nss_rc=0 changed=0
  local -a root_cmd=()

  if (( DRY_RUN == 1 )); then
    log "DRY-RUN: configure Avahi as the single mDNS stack and ensure nss-mdns"
    return 0
  fi

  command -v pacman >/dev/null 2>&1 || return 0
  pacman -Qq avahi >/dev/null 2>&1 || return 0
  have python3 || {
    warn "python3 is unavailable; mDNS NSS integration was not changed."
    return 0
  }

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    root_cmd=()
  else
    have sudo || {
      warn "sudo is unavailable; mDNS system integration was not changed."
      return 0
    }
    if ! sudo -v; then
      warn "sudo authentication failed; mDNS system integration was not changed."
      return 0
    fi
    root_cmd=(sudo)
  fi

  if ! pacman -Qq nss-mdns >/dev/null 2>&1; then
    "${root_cmd[@]}" pacman -S --needed --noconfirm nss-mdns || {
      warn "Could not install nss-mdns; Avahi NSS integration was not changed."
      return 0
    }
    changed=1
    "${root_cmd[@]}" install -d -m 0755 /var/lib/awtarchy
    "${root_cmd[@]}" touch /var/lib/awtarchy/managed-packages
    if ! grep -Fxq nss-mdns /var/lib/awtarchy/managed-packages 2>/dev/null; then
      printf '%s\n' nss-mdns | "${root_cmd[@]}" tee -a /var/lib/awtarchy/managed-packages >/dev/null
    fi
    "${root_cmd[@]}" sh -c 'LC_ALL=C sort -u -o /var/lib/awtarchy/managed-packages /var/lib/awtarchy/managed-packages && chmod 0644 /var/lib/awtarchy/managed-packages'
  fi

  if "${root_cmd[@]}" test -L "$resolved_file"; then
    warn "Refusing symbolic-link resolved mDNS drop-in: ${resolved_file}"
  elif "${root_cmd[@]}" test -e "$resolved_file" \
    && ! "${root_cmd[@]}" grep -Fqx "$marker" "$resolved_file";
  then
    warn "Refusing to replace non-Awtarchy resolved mDNS drop-in: ${resolved_file}"
  else
    tmp="$(mktemp)"
    printf '%s\n' "$marker" '[Resolve]' 'MulticastDNS=no' >"$tmp"
    "${root_cmd[@]}" install -d -m 0755 "$resolved_dir"
    if ! "${root_cmd[@]}" cmp -s "$tmp" "$resolved_file" 2>/dev/null; then
      "${root_cmd[@]}" install -m 0644 "$tmp" "$resolved_file"
      changed=1
    fi
    rm -f -- "$tmp"
  fi

  if [[ -L "$nsswitch" ]]; then
    warn "Refusing symbolic-link NSS configuration: ${nsswitch}"
  elif [[ -f "$nsswitch" && -r "$nsswitch" ]]; then
    nss_tmp="$(mktemp)"
    cp -- "$nsswitch" "$nss_tmp"
    python3 - "$nss_tmp" <<'PY' || nss_rc=$?
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)
hosts = [i for i, line in enumerate(lines) if line.lstrip().startswith("hosts:")]
if len(hosts) != 1:
    raise SystemExit(3)

i = hosts[0]
line = lines[i]
newline = "\n" if line.endswith("\n") else ""
raw = line[:-1] if newline else line
prefix, rhs = raw.split(":", 1)
tokens = rhs.split()

if any(token.startswith("mdns") for token in tokens):
    raise SystemExit(0)

try:
    insert_at = tokens.index("resolve")
except ValueError:
    try:
        insert_at = tokens.index("dns")
    except ValueError:
        raise SystemExit(4)

tokens[insert_at:insert_at] = ["mdns_minimal", "[NOTFOUND=return]"]
lines[i] = f"{prefix}: {' '.join(tokens)}{newline}"
path.write_text("".join(lines), encoding="utf-8")
raise SystemExit(10)
PY
    case "$nss_rc" in
      0)
        :
        ;;
      10)
        backup="${nsswitch}.awtarchy-backup.$(date '+%Y%m%d-%H%M%S')"
        "${root_cmd[@]}" cp -a -- "$nsswitch" "$backup"
        "${root_cmd[@]}" install -m 0644 "$nss_tmp" "$nsswitch"
        changed=1
        log "Backed up NSS configuration: ${backup}"
        ;;
      3)
        warn "Expected exactly one hosts: line in ${nsswitch}; leaving it unchanged."
        ;;
      4)
        warn "No resolve/dns anchor found in ${nsswitch}; leaving hosts lookup order unchanged."
        ;;
      *)
        warn "Could not reconcile ${nsswitch}; leaving it unchanged."
        ;;
    esac
    rm -f -- "$nss_tmp"
  else
    warn "NSS configuration is unavailable: ${nsswitch}"
  fi

  if (( changed == 1 )) && have systemctl; then
    "${root_cmd[@]}" systemctl try-restart systemd-resolved.service >/dev/null 2>&1 || true
    "${root_cmd[@]}" systemctl try-restart avahi-daemon.service >/dev/null 2>&1 || true
  fi
}

'''
text = text.replace(anchor, function + anchor, 1)

service_old = '''  log "Configuring system services..."
  systemctl enable --now avahi-daemon || true
'''
service_new = '''  log "Configuring system services..."
  configure_mdns_stack
  systemctl enable --now avahi-daemon || true
'''
if text.count(service_old) != 1:
    raise SystemExit("expected one system service block")
text = text.replace(service_old, service_new, 1)

hardware_old = '''  if (( gpu_cleanup_allowed == 0 )); then
    local saved_gpu="$GPU_VENDORS"
    GPU_VENDORS=""
    ensure_current_hardware_packages
    GPU_VENDORS="$saved_gpu"
  else
    ensure_current_hardware_packages
  fi
}
'''
hardware_new = '''  if (( gpu_cleanup_allowed == 0 )); then
    local saved_gpu="$GPU_VENDORS"
    GPU_VENDORS=""
    ensure_current_hardware_packages
    GPU_VENDORS="$saved_gpu"
  else
    ensure_current_hardware_packages
  fi

  configure_mdns_stack
}
'''
if text.count(hardware_old) != 1:
    raise SystemExit("expected one hardware reconciliation tail")
text = text.replace(hardware_old, hardware_new, 1)

path.write_text(text, encoding="utf-8")
