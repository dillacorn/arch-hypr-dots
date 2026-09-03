#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "local/share/awtarchy/awtarchy-runtime.sh"
RECONCILER = ROOT / "local/share/awtarchy/awtarchy-package-reconcile.sh"
SELF = Path(__file__).resolve()


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one match in {path}: {old!r}; found {count}")
    path.write_text(text.replace(old, new, 1))


replace_once(
    RUNTIME,
    "cmatrix asciiquarium figlet termdown espeak-ng",
    "cmatrix asciiquarium figlet espeak-ng",
)

replace_once(
    RECONCILER,
    "  network-manager-applet\n  blueman\n)",
    "  network-manager-applet\n  blueman\n  termdown\n)",
)
replace_once(
    RECONCILER,
    'for _ in "${arch_labels[@]}"; do arch_flags+=(0); done',
    'for _ in "${arch_labels[@]}"; do arch_flags+=(1); done',
)
replace_once(
    RECONCILER,
    'for _ in "${aur_labels[@]}"; do aur_flags+=(0); done',
    'for _ in "${aur_labels[@]}"; do aur_flags+=(1); done',
)
replace_once(
    RECONCILER,
    "  flatpak_flags+=(0)\n",
    "  flatpak_flags+=(1)\n",
)
replace_once(
    RECONCILER,
    "printf '\\nRequired missing packages above will be selected automatically.\\n' >/dev/tty",
    "printf '\\nMissing current packages below start selected; Space opts out.\\n' >/dev/tty",
)

SELF.unlink()
