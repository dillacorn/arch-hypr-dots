from pathlib import Path

path = Path("local/share/awtarchy/awtarchy-runtime.sh")
text = path.read_text(encoding="utf-8")
old = '  if ! run_as_target /usr/bin/yay -S --noconfirm aur-scanner; then\n'
new = '  if ! run_as_target /usr/bin/yay -S --noconfirm --pgpfetch aur-scanner; then\n'
count = text.count(old)
if count != 1:
    raise SystemExit(f"expected one aur-scanner bootstrap transaction, found {count}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
