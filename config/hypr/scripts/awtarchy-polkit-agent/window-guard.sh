#!/usr/bin/bash
# Geometry-only guard for the Awtarchy PolicyKit authentication window.

set -u
set -o pipefail
IFS=$'\n\t'

APP_ID="awtarchy-polkit-agent"
WINDOW_WIDTH=900
WINDOW_HEIGHT=520
SIZE_TOLERANCE=4
WATCH_INTERVAL=0.60

query_window_state() {
    /usr/bin/hyprctl -j clients 2>/dev/null | /usr/bin/python3 -c '
import json
import sys

app_id = sys.argv[1]
try:
    clients = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)

matches = []
for client in clients if isinstance(clients, list) else []:
    if not isinstance(client, dict) or not client.get("mapped", True):
        continue
    if app_id not in (
        client.get("class"),
        client.get("initialClass"),
        client.get("title"),
        client.get("initialTitle"),
    ):
        continue

    address = str(client.get("address") or "")
    size = client.get("size")
    if not address.startswith("0x") or not isinstance(size, list) or len(size) != 2:
        continue
    if not all(isinstance(value, (int, float)) for value in size):
        continue

    matches.append((
        int(client.get("focusHistoryID", 999999)),
        address,
        bool(client.get("floating", False)),
        int(size[0]),
        int(size[1]),
    ))

if not matches:
    raise SystemExit(1)

matches.sort(key=lambda item: item[0])
_, address, floating, width, height = matches[0]
print(f"{address}\t{str(floating).lower()}\t{width}\t{height}")
' "$APP_ID"
}

size_is_correct() {
    local width="$1" height="$2" dw dh

    [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]] || return 1
    dw=$((width - WINDOW_WIDTH))
    dh=$((height - WINDOW_HEIGHT))
    (( dw < 0 )) && dw=$((-dw))
    (( dh < 0 )) && dh=$((-dh))
    (( dw <= SIZE_TOLERANCE && dh <= SIZE_TOLERANCE ))
}

correct_window() {
    local address="$1" lua

    [[ $address =~ ^0x[0-9A-Fa-f]+$ ]] || return 1
    printf -v lua \
        'local w="address:%s"; hl.dispatch(hl.dsp.window.float({ action = "set", window = w })); hl.dispatch(hl.dsp.window.resize({ x = 900, y = 520, relative = false, window = w })); hl.dispatch(hl.dsp.window.center({ window = w }))' \
        "$address"

    /usr/bin/hyprctl eval "$lua" >/dev/null 2>&1
}

main() {
    local state address floating width height

    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 0
    [[ -x /usr/bin/hyprctl && -x /usr/bin/python3 ]] || return 0

    while true; do
        if state="$(query_window_state)"; then
            IFS=$'\t' read -r address floating width height <<<"$state"
            if [[ $floating != true ]] || ! size_is_correct "$width" "$height"; then
                correct_window "$address" || true
            fi
        fi
        /usr/bin/sleep "$WATCH_INTERVAL"
    done
}

main "$@"
