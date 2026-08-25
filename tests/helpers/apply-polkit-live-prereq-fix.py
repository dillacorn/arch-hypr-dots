#!/usr/bin/env python3
from pathlib import Path

path = Path("config/hypr/scripts/awtarchy-polkit-agent-live-test.sh")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    text = text.replace(old, new, 1)


replace_once(
    "        /usr/bin/nohup \\\n        /usr/bin/pgrep \\\n        /usr/bin/pkcheck \\\n",
    "        /usr/bin/nohup \\\n        /usr/bin/pacman \\\n        /usr/bin/pgrep \\\n        /usr/bin/pkcheck \\\n",
    "pacman command prerequisite",
)

replace_once(
    "verify_python_source() {\n",
    r'''ensure_test_prerequisites() {
    local pkg
    local -a missing=()

    for pkg in polkit python-gobject; do
        /usr/bin/pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done

    if ((${#missing[@]} > 0)); then
        note "Installing terminal PolicyKit test prerequisites: ${missing[*]}"
        /usr/bin/sudo /usr/bin/pacman -S --needed --noconfirm "${missing[@]}" \
            || fail 'could not install terminal PolicyKit test prerequisites' || return 1
    fi

    /usr/bin/python3 -I -c 'import gi; gi.require_version("Polkit", "1.0"); gi.require_version("PolkitAgent", "1.0"); from gi.repository import Gio, GLib, Polkit, PolkitAgent' \
        || fail 'PolicyKit Python bindings are unavailable after prerequisite installation' || return 1
}

verify_python_source() {
''',
    "test prerequisite function",
)

replace_once(
    "    /usr/bin/sudo -v || fail 'sudo authentication failed' || return 1\n    ensure_root_directory \"$RUNTIME_PARENT\" || return 1\n",
    "    /usr/bin/sudo -v || fail 'sudo authentication failed' || return 1\n    ensure_test_prerequisites || return 1\n    ensure_root_directory \"$RUNTIME_PARENT\" || return 1\n",
    "install prerequisite call",
)

path.write_text(text, encoding="utf-8")
