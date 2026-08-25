#!/usr/bin/bash
set -euo pipefail

AUTH_CONFIG="config/hypr/scripts/awtarchy-polkit-agent/alacritty.toml"
MAIN_CONFIG="config/alacritty/alacritty.toml"

[[ -f $AUTH_CONFIG ]]
[[ -f $MAIN_CONFIG ]]

/usr/bin/python3 - "$AUTH_CONFIG" "$MAIN_CONFIG" <<'PY'
from pathlib import Path
import sys
import tomllib

auth_path = Path(sys.argv[1])
main_path = Path(sys.argv[2])
auth = tomllib.loads(auth_path.read_text(encoding="utf-8"))
main = tomllib.loads(main_path.read_text(encoding="utf-8"))

assert main["window"]["padding"] == {"x": 22, "y": 22}
assert main["window"]["opacity"] == 0.85
assert main["window"]["decorations"] == "Buttonless"
assert main["font"]["size"] == 12.0
assert "~/.config/alacritty/themes/themes/wombat.toml" in main["general"]["import"]

assert auth["window"]["padding"] == {"x": 22, "y": 22}
assert auth["window"]["opacity"] == 0.85
assert auth["window"]["decorations"] == "Buttonless"
assert auth["font"]["size"] == 12.0
assert auth["scrolling"]["history"] == 0

assert auth["colors"]["primary"] == {
    "background": "#1f1f1f",
    "foreground": "#e5e1d8",
}
assert auth["colors"]["normal"] == {
    "black": "#000000",
    "red": "#f7786d",
    "green": "#bde97c",
    "yellow": "#efdfac",
    "blue": "#6ebaf8",
    "magenta": "#ef88ff",
    "cyan": "#90fdf8",
    "white": "#e5e1d8",
}
assert auth["colors"]["bright"] == {
    "black": "#b4b4b4",
    "red": "#f99f92",
    "green": "#e3f7a1",
    "yellow": "#f2e9bf",
    "blue": "#b3d2ff",
    "magenta": "#e5bdff",
    "cyan": "#c2fefa",
    "white": "#ffffff",
}

text = auth_path.read_text(encoding="utf-8")
assert "import =" not in text
assert "~/.config" not in text
assert "/home/" not in text
PY

echo 'Polkit Alacritty appearance contract passed.'
