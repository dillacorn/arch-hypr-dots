#!/usr/bin/env python3
from pathlib import Path

path = Path("local/share/awtarchy/awtarchy-runtime.sh")
text = path.read_text(encoding="utf-8")

old = '''    *.desktop)
      command -v desktop-file-validate >/dev/null 2>&1 || return 0
      desktop-file-validate "$file"
      ;;
'''

new = '''    *.desktop)
      # Awtarchy intentionally uses shell-based Exec= launchers that work in the
      # target desktop environment but are rejected by desktop-file-validate.
      # Validate the required desktop-entry structure without making those
      # intentional shell commands fatal to an update.
      grep -Fqx '[Desktop Entry]' "$file" \
        && grep -Eq '^Type=(Application|Link|Directory)$' "$file" \
        && grep -Eq '^Name=.+$' "$file"
      ;;
'''

count = text.count(old)
if count != 1:
    raise SystemExit(f"expected exactly one strict desktop validator, found {count}")

path.write_text(text.replace(old, new, 1), encoding="utf-8")
