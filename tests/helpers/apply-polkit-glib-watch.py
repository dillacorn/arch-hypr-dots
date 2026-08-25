#!/usr/bin/env python3
from pathlib import Path

path = Path('config/hypr/scripts/awtarchy-polkit-agent/agent.py')
text = path.read_text()

old_watch = '''        conditions = GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR
        GLib.unix_fd_add(GLib.PRIORITY_DEFAULT, self.ui.tty_fd, conditions, self._on_tty_ready)
        GLib.timeout_add(45, self._flush_pending_escape)
'''
new_watch = '''        conditions = GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR
        self.tty_channel = GLib.IOChannel.unix_new(self.ui.tty_fd)
        self.tty_channel.set_close_on_unref(False)
        self.tty_channel.add_watch(conditions, self._on_tty_ready)
        GLib.timeout_add(45, self._flush_pending_escape)
'''

old_callback = '''    def _on_tty_ready(self, fd: int, condition: GLib.IOCondition) -> bool:
        del fd
'''
new_callback = '''    def _on_tty_ready(self, channel: GLib.IOChannel, condition: GLib.IOCondition) -> bool:
        del channel
'''

if text.count(old_watch) != 1:
    raise SystemExit('expected exactly one GLib.unix_fd_add watch block')
if text.count(old_callback) != 1:
    raise SystemExit('expected exactly one TTY callback signature')

text = text.replace(old_watch, new_watch, 1)
text = text.replace(old_callback, new_callback, 1)
path.write_text(text)
