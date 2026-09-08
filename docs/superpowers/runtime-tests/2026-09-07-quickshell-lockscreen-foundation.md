# Quickshell Lockscreen Foundation Runtime Test

Exact validated branch head when this checklist was written:

`b4a1bf047c6cbb99c7208b63599fde9510ff6058`

This is a foundation test only. Existing production Hyprlock entrypoints remain active.

## Install the exact Git-testing revision

```bash
awtarchy git update --branch feature/quickshell-lockscreen --commit b4a1bf047c6cbb99c7208b63599fde9510ff6058
```

Verify the new foundation files were deployed before attempting a session lock:

```bash
test -x ~/.config/hypr/scripts/awtarchy_lock.sh \
  && test -f ~/.config/quickshell/awtarchy-lock/shell.qml \
  && test -f ~/.config/quickshell/awtarchy-lock/LockAuth.qml \
  && test -f ~/.config/quickshell/awtarchy-lock/LockSurface.qml \
  && printf 'lockscreen foundation installed\n'
```

## First lock/unlock test

Before running this, know how to reach a TTY (`Ctrl+Alt+F2` or another available VT). If the new Quickshell locker acquires the secure Wayland session lock but its authentication UI fails, killing the locker will not expose the desktop. Do not test locker crashes yet; supervised session-lock restoration is intentionally not part of this foundation slice.

Start the new locker manually:

```bash
~/.config/hypr/scripts/awtarchy_lock.sh lock
```

Expected behavior:

- every active monitor is covered by the native Awtarchy lockscreen;
- background is solid black;
- the Awtarchy Fastfetch ASCII mark is visible;
- clock/date/current username and a minimal password input are visible;
- no rounded lock card is present;
- entering the correct password unlocks the session normally.

## Authentication retry

Run the manual lock again. Enter one intentionally wrong password, confirm the session stays locked and the field becomes usable again, then enter the correct password.

## Multi-monitor/scale check

With the normal monitor layout active, confirm each output is fully covered and the content is sensibly scaled. If monitors use different scale values, check both.

## Do not test yet

Do not deliberately kill the secure lock process, unplug displays while locked, suspend/hibernate while using the new locker, or replace `SUPER+L`/Hypridle/Power Menu yet. Those behaviors belong to the next migration/recovery slice after basic real-session lock/authentication is proven.

## Report useful evidence

If the locker fails before becoming usable, return from the TTY or unlocked session and capture:

```bash
~/.config/hypr/scripts/awtarchy_lock.sh status
printf '%s\n' '--- lockscreen log ---'
tail -n 120 ~/.cache/awtarchy/lockscreen.log
```

Do not include passwords or other secrets in issue reports.
