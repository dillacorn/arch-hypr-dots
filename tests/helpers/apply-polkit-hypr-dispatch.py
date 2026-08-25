#!/usr/bin/env python3
from pathlib import Path

path = Path("config/hypr/scripts/awtarchy-polkit-agent/tui.py")
text = path.read_text(encoding="utf-8")

old = '''    def _move_window(self, workspace: str, focus: bool) -> None:\n        client = self._window()\n        if client is None:\n            raise RuntimeError("Awtarchy PolicyKit terminal window not found")\n        address = str(client["address"])\n        self._hypr("dispatch", "movetoworkspacesilent", f"{workspace},address:{address}")\n        if focus:\n            lua = (\n                f'local w="address:{address}"; '\n                'hl.dispatch(hl.dsp.window.float({ action = "set", window = w })); '\n                f'hl.dispatch(hl.dsp.window.resize({{ x = {WINDOW_WIDTH}, y = {WINDOW_HEIGHT}, relative = false, window = w }})); '\n                'hl.dispatch(hl.dsp.window.center({ window = w }))'\n            )\n            self._hypr("eval", lua)\n            self._hypr("dispatch", "focuswindow", f"address:{address}")\n'''

new = '''    @staticmethod\n    def _lua_string(value: str) -> str:\n        return (\n            value.replace("\\\\", "\\\\\\\\")\n            .replace('"', '\\\\"')\n            .replace("\\n", "\\\\n")\n            .replace("\\r", "\\\\r")\n        )\n\n    def _move_window(self, workspace: str, focus: bool) -> None:\n        client = self._window()\n        if client is None:\n            raise RuntimeError("Awtarchy PolicyKit terminal window not found")\n        address = str(client["address"])\n        selector = self._lua_string(f"address:{address}")\n        workspace_value = self._lua_string(workspace)\n        commands = [\n            f'local w="{selector}"',\n            f'local workspace="{workspace_value}"',\n            'hl.dispatch(hl.dsp.window.move({ workspace = workspace, follow = false, window = w }))',\n        ]\n        if focus:\n            commands.extend(\n                [\n                    'hl.dispatch(hl.dsp.window.float({ action = "enable", window = w }))',\n                    f'hl.dispatch(hl.dsp.window.resize({{ x = {WINDOW_WIDTH}, y = {WINDOW_HEIGHT}, relative = false, window = w }}))',\n                    'hl.dispatch(hl.dsp.window.center({ window = w }))',\n                    'hl.dispatch(hl.dsp.focus({ window = w }))',\n                ]\n            )\n        self._hypr("eval", "; ".join(commands))\n'''

count = text.count(old)
if count != 1:
    raise SystemExit(f"expected exactly one old _move_window implementation, found {count}")

path.write_text(text.replace(old, new, 1), encoding="utf-8")
