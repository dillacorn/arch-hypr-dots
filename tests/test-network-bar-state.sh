#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML="${ROOT}/config/quickshell/awtarchy/NetworkMenu.qml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# A wired device object may exist while no wired network is actually connected.
# The bar must key wired connectivity from the network object, not merely device.connected.
grep -Fq 'connectedWiredDevices: wiredDevices.filter(device => device && device.network && device.network.connected)' "$QML" \
  || fail 'wired connectivity still trusts device.connected instead of the active wired network'

python3 - "$QML" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index("    function buildBarLabel() {")
end = text.index("    function buildVerticalBarLabel() {", start)
block = text[start:end]

wifi_connected = block.index("if (wifiConnected)")
wired_connected = block.index("if (wiredConnected)")
wifi_present = block.index("if (wifiPresent)")
wired_present = block.index("if (wiredPresent)")

if not wifi_connected < wired_connected:
    raise SystemExit("FAIL: horizontal bar does not prefer an active Wi-Fi connection over Ethernet")
if not wifi_present < wired_present:
    raise SystemExit("FAIL: disconnected laptop does not show Wi-Fi state before an unused Ethernet adapter")
if 'return "󰤯";' not in block:
    raise SystemExit("FAIL: horizontal bar has no explicit muted/disconnected Wi-Fi symbol")

start = text.index("    function buildVerticalBarLabel() {")
end = text.index("    function wiredConnectionName", start)
block = text[start:end]

if not block.index("if (wifiConnected)") < block.index("if (wiredConnected)"):
    raise SystemExit("FAIL: vertical bar does not prefer an active Wi-Fi connection over Ethernet")
if not block.index("if (wifiPresent)") < block.index("if (wiredPresent)"):
    raise SystemExit("FAIL: vertical disconnected state does not prefer Wi-Fi over unused Ethernet")
if 'return "󰤯";' not in block:
    raise SystemExit("FAIL: vertical bar has no explicit muted/disconnected Wi-Fi symbol")
PY

printf '%s\n' 'PASS: network bar distinguishes active Wi-Fi, wired connectivity, and disconnected adapter state.'
