#!/usr/bin/env python3
from pathlib import Path


def read(path):
    return Path(path).read_text(encoding="utf-8")


def write(path, text):
    Path(path).write_text(text, encoding="utf-8")


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


volume_script = r'''#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# Route-aware default output volume control for the Awtarchy bar.

set -euo pipefail
IFS=$'\n\t'

ACTION="${1:-}"
VALUE="${2:-}"

case "$ACTION" in
  up|down|set) ;;
  *)
    printf 'Usage: %s {up|down|set} PERCENT\n' "${0##*/}" >&2
    exit 2
    ;;
esac

[[ $VALUE =~ ^[0-9]+([.][0-9]+)?$ ]] || {
  printf 'ERROR: invalid volume percentage: %s\n' "$VALUE" >&2
  exit 2
}

for command in wpctl pw-dump pw-cli python3; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'ERROR: required command not found: %s\n' "$command" >&2
    exit 127
  }
done

fallback_volume() {
  local limit_ratio
  limit_ratio="$(python3 -c 'import sys; print(max(0.0, min(2.0, float(sys.argv[1]) / 100.0)))' "$VALUE")"
  case "$ACTION" in
    up)
      wpctl set-volume --limit "$limit_ratio" @DEFAULT_AUDIO_SINK@ 5%+
      ;;
    down)
      wpctl set-volume --limit "$limit_ratio" @DEFAULT_AUDIO_SINK@ 5%-
      ;;
    set)
      wpctl set-volume @DEFAULT_AUDIO_SINK@ "${VALUE}%"
      ;;
  esac
}

inspect="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)"
device_id="$(sed -nE 's/^[[:space:]]*\*?[[:space:]]*device\.id[[:space:]]*=[[:space:]]*"?([0-9]+)"?.*/\1/p' <<<"$inspect" | head -n1)"
route_device="$(sed -nE 's/^[[:space:]]*\*?[[:space:]]*card\.profile\.device[[:space:]]*=[[:space:]]*"?([0-9]+)"?.*/\1/p' <<<"$inspect" | head -n1)"

if [[ ! $device_id =~ ^[0-9]+$ || ! $route_device =~ ^[0-9]+$ ]]; then
  fallback_volume
  exit 0
fi

route_dump="$(pw-dump "$device_id" 2>/dev/null || true)"
[[ -n $route_dump ]] || {
  fallback_volume
  exit 0
}

if ! route_result="$(printf '%s\n' "$route_dump" | python3 -c '
import json
import math
import sys

route_device = int(sys.argv[1])
action = sys.argv[2]
value = float(sys.argv[3])

data = json.load(sys.stdin)
obj = data[0] if isinstance(data, list) and data else {}
routes = (((obj.get("info") or {}).get("params") or {}).get("Route") or [])
route = next((r for r in routes if int(r.get("device", -1)) == route_device), None)
if route is None:
    raise SystemExit(2)

props = route.get("props") or {}
volumes = props.get("channelVolumes") or props.get("softVolumes") or []
if not isinstance(volumes, list) or not volumes:
    raise SystemExit(3)

avg_raw = sum(float(v) for v in volumes) / len(volumes)
current = max(avg_raw, 0.0) ** (1.0 / 3.0) * 100.0

if action == "up":
    target = (math.floor(current / 5.0 + 1e-6) + 1.0) * 5.0
    maximum = value
elif action == "down":
    target = (math.ceil(current / 5.0 - 1e-6) - 1.0) * 5.0
    maximum = value
else:
    target = value
    maximum = value

maximum = max(0.0, min(200.0, maximum))
target = max(0.0, min(maximum, target))
raw = (target / 100.0) ** 3
channel_values = ", ".join(f"{raw:.9f}" for _ in volumes)
mute = "true" if bool(props.get("mute", False)) else "false"
print(f"{int(route[\"index\"])}|{route_device}|{channel_values}|{mute}")
' "$route_device" "$ACTION" "$VALUE")"; then
  fallback_volume
  exit 0
fi

IFS='|' read -r route_index route_device_out channel_values mute_state <<<"$route_result"
[[ $route_index =~ ^-?[0-9]+$ && $route_device_out =~ ^-?[0-9]+$ && -n $channel_values ]] || {
  fallback_volume
  exit 0
}

pw-cli s "$device_id" Route \
  "{ index: ${route_index}, device: ${route_device_out}, props: { channelVolumes: [ ${channel_values} ], mute: ${mute_state} }, save: true }" \
  >/dev/null
'''

path = "config/hypr/scripts/quickshell_volume.sh"
Path(path).write_text(volume_script, encoding="utf-8")
Path(path).chmod(0o755)

# Bar: route all scroll changes through the route-aware helper.
path = "config/quickshell/awtarchy/Bar.qml"
text = read(path)
text = replace_once(
    text,
    '    readonly property string wiremixScript: configHome + "/hypr/scripts/wiremix-toggle.sh"\n',
    '    readonly property string wiremixScript: configHome + "/hypr/scripts/wiremix-toggle.sh"\n'
    '    readonly property string volumeScript: configHome + "/hypr/scripts/quickshell_volume.sh"\n',
    "Bar volume helper path",
)
old = '''    function adjustAudio(delta) {
        if (delta === 0)
            return;
        const stepPercent = Math.max(1, Math.round(Math.abs(delta) * 100));
        const direction = delta > 0 ? "+" : "-";
        Quickshell.execDetached([
            "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@",
            String(stepPercent) + "%" + direction,
            "--limit", String(AudioLimitState.limitPercent / 100)
        ]);
    }
'''
new = '''    function adjustAudio(delta) {
        if (delta === 0)
            return;
        Quickshell.execDetached([
            volumeScript,
            delta > 0 ? "up" : "down",
            String(AudioLimitState.limitPercent)
        ]);
    }
'''
text = replace_once(text, old, new, "Bar route-aware volume scrolling")
write(path, text)

# AudioLimitState: lowering the maximum must clamp the same route that Wiremix controls.
path = "config/quickshell/awtarchy/AudioLimitState.qml"
text = read(path)
text = replace_once(
    text,
    '    readonly property string configPath: configHome + "/wiremix/wiremix.toml"\n',
    '    readonly property string configPath: configHome + "/wiremix/wiremix.toml"\n'
    '    readonly property string volumeScript: configHome + "/hypr/scripts/quickshell_volume.sh"\n',
    "AudioLimitState helper path",
)
old = '''    function clampCurrentOutput() {
        const sink = Pipewire.defaultAudioSink;
        const maximum = limitPercent / 100;
        if (sink && sink.audio && sink.audio.volume > maximum) {
            Quickshell.execDetached([
                "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@",
                String(limitPercent) + "%"
            ]);
        }
    }
'''
new = '''    function clampCurrentOutput() {
        const sink = Pipewire.defaultAudioSink;
        const maximum = limitPercent / 100;
        if (sink && sink.audio && sink.audio.volume > maximum)
            Quickshell.execDetached([volumeScript, "set", String(limitPercent)]);
    }
'''
text = replace_once(text, old, new, "AudioLimitState route-aware clamp")
write(path, text)

# Production regression checks and a mocked route-level write above 100%.
path = "tests/test-quickshell-production-readiness.sh"
text = read(path)
old = '''assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/Bar.qml" '\"wpctl\", \"set-volume\", \"@DEFAULT_AUDIO_SINK@\"'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/Bar.qml" '\"--limit\", String(AudioLimitState.limitPercent / 100)'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/AudioLimitState.qml" 'String(limitPercent) + \"%\"'
'''
new = '''assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/Bar.qml" 'configHome + "/hypr/scripts/quickshell_volume.sh"'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/Bar.qml" 'String(AudioLimitState.limitPercent)'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/AudioLimitState.qml" 'Quickshell.execDetached([volumeScript, "set", String(limitPercent)])'
assert_contains "${REPO_ROOT}/config/hypr/scripts/quickshell_volume.sh" 'pw-cli s "$device_id" Route'
assert_contains "${REPO_ROOT}/config/hypr/scripts/quickshell_volume.sh" 'channelVolumes: [ ${channel_values} ]'
assert_not_contains "${REPO_ROOT}/config/quickshell/awtarchy/Bar.qml" '\"wpctl\", \"set-volume\", \"@DEFAULT_AUDIO_SINK@\"'

volume_test_bin="${TMPD}/volume-route-bin"
volume_test_log="${TMPD}/volume-route.log"
mkdir -p "$volume_test_bin"
cat >"${volume_test_bin}/wpctl" <<'EOF_WPCTL'
#!/usr/bin/env bash
if [[ ${1:-} == inspect ]]; then
  cat <<'EOF_INSPECT'
id 60, type PipeWire:Interface:Node
    * device.id = "42"
    * card.profile.device = "7"
EOF_INSPECT
  exit 0
fi
printf 'unexpected wpctl fallback: %s\\n' "$*" >&2
exit 90
EOF_WPCTL
cat >"${volume_test_bin}/pw-dump" <<'EOF_PWDUMP'
#!/usr/bin/env bash
cat <<'EOF_JSON'
[{"id":42,"info":{"params":{"Route":[{"index":3,"device":7,"props":{"mute":false,"channelVolumes":[1.0,1.0]}}]}}}]
EOF_JSON
EOF_PWDUMP
cat >"${volume_test_bin}/pw-cli" <<'EOF_PWCLI'
#!/usr/bin/env bash
printf '%s\\n' "$*" >>"${AWTARCHY_VOLUME_TEST_LOG:?}"
EOF_PWCLI
chmod +x "${volume_test_bin}/wpctl" "${volume_test_bin}/pw-dump" "${volume_test_bin}/pw-cli"
PATH="${volume_test_bin}:$PATH" AWTARCHY_VOLUME_TEST_LOG="$volume_test_log" \
  bash "${REPO_ROOT}/config/hypr/scripts/quickshell_volume.sh" up 125
grep -Fq 'Route { index: 3, device: 7, props: { channelVolumes: [ 1.157625000, 1.157625000 ]' \
  "$volume_test_log" || fail 'Route-aware bar volume did not write 105% through the device route'
'''
text = replace_once(text, old, new, "production readiness route volume checks")
write(path, text)

# Validate the new helper as normal command code.
path = ".github/workflows/validate-awtarchy.yml"
text = read(path)
text = replace_once(
    text,
    '          bash -n config/hypr/scripts/quickshell_theme_apply.sh\n',
    '          bash -n config/hypr/scripts/quickshell_theme_apply.sh\n'
    '          bash -n config/hypr/scripts/quickshell_volume.sh\n',
    "workflow bash syntax",
)
text = replace_once(
    text,
    '            config/hypr/scripts/quickshell_sensitive_capture.sh \\\n            config/hypr/scripts/quickshell_wireguard.sh \\\n',
    '            config/hypr/scripts/quickshell_sensitive_capture.sh \\\n'
    '            config/hypr/scripts/quickshell_volume.sh \\\n'
    '            config/hypr/scripts/quickshell_wireguard.sh \\\n',
    "workflow shellcheck",
)
write(path, text)
