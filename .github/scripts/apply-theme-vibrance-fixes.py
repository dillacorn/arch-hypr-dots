#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
THEME = ROOT / "config/quickshell/awtarchy/ThemePicker.qml"
QUICK = ROOT / "config/quickshell/awtarchy/QuickSettings.qml"
VIBRANCE = ROOT / "config/hypr/scripts/vibrance_shader.sh"
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"


def replace_exact(text: str, old: str, new: str, *, expected: int = 1, label: str) -> str:
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"{label}: expected {expected} match(es), found {count}")
    return text.replace(old, new)


def patch_theme_picker() -> None:
    text = THEME.read_text(encoding="utf-8")
    text = replace_exact(
        text,
        '''    Shortcut {\n        sequence: "Escape"\n        context: Qt.ApplicationShortcut\n        enabled: root.open && FlyoutManager.overlaySurface === "themes"\n        autoRepeat: false\n        onActivated: root.close()\n    }\n\n''',
        "",
        label="remove ThemePicker application Escape shortcut",
    )
    text = replace_exact(
        text,
        "        focusable: true\n",
        "        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive\n",
        label="ThemePicker keyboard focus",
    )
    text = replace_exact(
        text,
        '''            radius: 0\n            MouseArea {\n                anchors.fill: parent\n                onPressed: mouse => mouse.accepted = true\n            }\n''',
        '''            radius: 0\n            focus: true\n            Keys.onEscapePressed: event => {\n                root.close();\n                event.accepted = true;\n            }\n            MouseArea {\n                anchors.fill: parent\n                onPressed: mouse => mouse.accepted = true\n            }\n''',
        label="ThemePicker panel Escape handler",
    )
    THEME.write_text(text, encoding="utf-8")


def patch_quick_settings() -> None:
    text = QUICK.read_text(encoding="utf-8")
    text = replace_exact(
        text,
        'text: "SUPER+ALT+CTRL+- warmer  ·  SUPER+ALT+CTRL+= cooler  ·  SUPER+ALT+CTRL+BACKSPACE toggle"',
        'text: "CTRL+SUPER+ALT+[ warmer  ·  CTRL+SUPER+ALT+] cooler  ·  CTRL+SUPER+ALT+N toggle"',
        label="Night Light shortcut hint",
    )
    text = replace_exact(
        text,
        'text: "SUPER+ALT+CTRL+V toggle"',
        'text: "SUPER+ALT+[ decrease  ·  SUPER+ALT+] increase  ·  CTRL+SUPER+ALT+V toggle"',
        label="Vibrance shortcut hint",
    )
    QUICK.write_text(text, encoding="utf-8")


def patch_vibrance() -> None:
    text = VIBRANCE.read_text(encoding="utf-8")
    text = replace_exact(
        text,
        '''reload_hypr() {\n  command -v hyprctl >/dev/null 2>&1 || return 0\n  hyprctl reload >/dev/null 2>&1 || true\n}\n''',
        '''reload_hypr() {\n  command -v hyprctl >/dev/null 2>&1 || return 0\n  hyprctl reload >/dev/null 2>&1 || true\n}\n\napply_live_vibrance_state() {\n  local enable="$1"\n  command -v hyprctl >/dev/null 2>&1 || return 0\n\n  if [[ "$enable" == "1" ]]; then\n    hyprctl keyword decoration:screen_shader "$SHADER" >/dev/null 2>&1\n  else\n    hyprctl keyword decoration:screen_shader "" >/dev/null 2>&1\n  fi\n}\n''',
        label="live vibrance helper",
    )
    text = replace_exact(
        text,
        '''      set_vibrance_state "$want_enable"\n      reload_hypr\n      notify_enabled_or_off "$want_enable" "$new"''',
        '''      set_vibrance_state "$want_enable"\n      reload_hypr\n      apply_live_vibrance_state "$want_enable"\n      notify_enabled_or_off "$want_enable" "$new"''',
        expected=4,
        label="level actions live vibrance update",
    )
    text = replace_exact(
        text,
        '''        set_vibrance_state 0\n        reload_hypr\n        notify "off"''',
        '''        set_vibrance_state 0\n        reload_hypr\n        apply_live_vibrance_state 0\n        notify "off"''',
        label="toggle off live vibrance update",
    )
    text = replace_exact(
        text,
        '''        set_vibrance_state 1\n        reload_hypr\n        notify "$(read_vibrance)"''',
        '''        set_vibrance_state 1\n        reload_hypr\n        apply_live_vibrance_state 1\n        notify "$(read_vibrance)"''',
        label="toggle on live vibrance update",
    )
    text = replace_exact(
        text,
        '''      set_vibrance_state 0\n      reload_hypr\n      notify "off"''',
        '''      set_vibrance_state 0\n      reload_hypr\n      apply_live_vibrance_state 0\n      notify "off"''',
        label="explicit off live vibrance update",
    )
    VIBRANCE.write_text(text, encoding="utf-8")


def append_managed_hashes() -> None:
    history = HISTORY.read_text(encoding="utf-8")
    if history and not history.endswith("\n"):
        history += "\n"

    for path, rel in (
        (THEME, ".config/quickshell/awtarchy/ThemePicker.qml"),
        (QUICK, ".config/quickshell/awtarchy/QuickSettings.qml"),
    ):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        entry = f"{digest}\t{rel}"
        if entry not in history.splitlines():
            history += entry + "\n"

    HISTORY.write_text(history, encoding="utf-8")


patch_theme_picker()
patch_quick_settings()
patch_vibrance()
append_managed_hashes()
