from pathlib import Path

path = Path("config/hypr/scripts/awtarchy-tips-tui.sh")
text = path.read_text(encoding="utf-8")

old = '''        packages-aur)
            cat <<'TEXT'
AUR Guard wraps Awtarchy's yay/AUR workflow so AUR package installation is explicit and isolated from the normal Arch repository package stage.

Keep Arch repository packages in the Arch package selector when they exist there. Use the AUR path only for packages that actually require it.

For cleanup guidance, see the AUR and Arch orphan-removal Extra Notes.
TEXT
            ;;
'''

new = '''        packages-aur)
            cat <<'TEXT'
Awtarchy delegates AUR scanning and installation to upstream aur-scanner.

Use yay for read-only AUR search and query commands such as:
  yay -Ss package
  yay -Si package
  yay -Qm

Awtarchy's interactive shell blocks package-changing yay/paru transactions. Install AUR packages with:
  aur-scan install package

Use:
  aur-scan -h
for the current upstream commands and options.

Upstream documentation:
  https://github.com/KiefStudioMA/ks-aur-scanner

Keep Arch repository packages in the Arch package selector when they exist there. Use the AUR path only for packages that actually require it.

For cleanup guidance, see the AUR and Arch orphan-removal Extra Notes.
TEXT
            ;;
'''

if text.count(old) != 1:
    raise SystemExit("unexpected packages-aur article anchor")
if text.count('        "AUR Guard"\n') != 1:
    raise SystemExit("unexpected AUR Tips menu label anchor")

updated = text.replace(old, new, 1)
updated = updated.replace('        "AUR Guard"\n', '        "AUR / aur-scanner"\n', 1)

for retired in ("AUR Guard", "AurGuard", "aurguard", "aurverify", "aurinstall"):
    if retired.lower() in updated.lower():
        raise SystemExit(f"retired AurGuard Tips reference remains: {retired}")
if "aur-scan install package" not in updated or "aur-scan -h" not in updated:
    raise SystemExit("new aur-scanner tips guidance is incomplete")

path.write_text(updated, encoding="utf-8")
