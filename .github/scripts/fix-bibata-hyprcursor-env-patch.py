#!/usr/bin/env python3
from pathlib import Path

path = Path('.github/scripts/apply-bibata-hyprcursor-env-followup.py')
text = path.read_text()
old = '''    if count != 1:
        raise SystemExit(f"{label}: expected exactly one marker, found {count}")
    path.write_text(text.replace(old, new, 1))
'''
new = '''    expected = 2 if label == "initial cursor fixture" else 1
    if count != expected:
        raise SystemExit(f"{label}: expected exactly {expected} marker(s), found {count}")
    path.write_text(text.replace(old, new, 1))
'''
if text.count(old) != 1:
    raise SystemExit('patch helper marker did not match exactly once')
path.write_text(text.replace(old, new, 1))
