#!/usr/bin/env python3
from pathlib import Path

path = Path("tests/test-floating-windows-global-mode.sh")
text = path.read_text()
old = '''bind_count="$(grep -Fc 'hl.bind("SUPER + ALT + F", hl.dsp.exec_cmd(floating_windows_toggle), {})' "$HYPR_LUA" || true)"
'''
new = '''bind_count="$(grep -Fc '{ "SUPER + ALT + F", floating_windows_toggle },' "$HYPR_LUA" || true)"
'''
if text.count(old) != 1:
    raise SystemExit("expected one stale direct-bind assertion")
path.write_text(text.replace(old, new, 1))
