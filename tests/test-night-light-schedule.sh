#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/config/hypr/scripts/hyprsunset_ctl.sh"
BACKEND="${ROOT}/config/hypr/scripts/hypr_quicksettings.sh"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
HISTORY="${ROOT}/local/share/awtarchy/quickshell-managed-history.sha256"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

contains() {
  grep -Fq -- "$2" "$1" || fail "$3"
}

TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

export HOME="${TMPD}/home"
export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_STATE_HOME="${HOME}/.local/state"
mkdir -p -- "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$TMPD/bin"

CONFIG_FILE="${XDG_CONFIG_HOME}/hypr/hyprsunset.conf"
SCHEDULE_FILE="${XDG_STATE_HOME}/hyprsunset/schedule"
export HYPRSUNSET_IDENTITY_FILE="$TMPD/hyprsunset-identity"
export HYPRCTL_LOG="$TMPD/hyprctl.log"
printf '%s\n' false >"$HYPRSUNSET_IDENTITY_FILE"
: >"$HYPRCTL_LOG"

cat >"$TMPD/bin/hyprctl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${HYPRCTL_LOG:?}"
case "$*" in
  'hyprsunset identity get')
    cat "${HYPRSUNSET_IDENTITY_FILE:?}"
    ;;
  'hyprsunset identity')
    printf '%s\n' true >"${HYPRSUNSET_IDENTITY_FILE:?}"
    ;;
  hyprsunset\ temperature\ *)
    printf '%s\n' false >"${HYPRSUNSET_IDENTITY_FILE:?}"
    ;;
  *)
    exit 2
    ;;
esac
FAKE

cat >"$TMPD/bin/date" <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == '+%H:%M' ]]; then
  printf '%s\n' '12:00'
else
  /usr/bin/date "$@"
fi
FAKE
chmod 0755 "$TMPD/bin/hyprctl" "$TMPD/bin/date"
export PATH="$TMPD/bin:$PATH"

bash -n "$SCRIPT"

# Hyprsunset's IPC query is authoritative. Awtarchy must use identity get rather
# than inferring the current manual state from schedule time or saved fallback.
status="$(bash "$SCRIPT" status)"
grep -Fqx 'identity=false' <<<"$status" || fail 'status does not use Hyprsunset identity get for the live state'
grep -Fxq 'hyprsunset identity get' "$HYPRCTL_LOG" || fail 'Hyprsunset identity get was not queried'
if grep -Fxq -- '-j hyprsunset' "$HYPRCTL_LOG"; then
  fail 'Night Light still uses the obsolete hyprctl -j hyprsunset state query'
fi

# Overnight schedules must persist exact 24-hour times, generate native
# hyprsunset profiles, and identify that the end occurs on the next day.
bash "$SCRIPT" schedule set 20:00 07:00 4500 >/dev/null
[[ -f "$CONFIG_FILE" ]] || fail 'schedule did not create hyprsunset.conf'
[[ -f "$SCHEDULE_FILE" ]] || fail 'schedule state was not persisted'
contains "$CONFIG_FILE" '# Managed by Awtarchy Night Light schedule.' \
  'generated hyprsunset.conf is missing the Awtarchy ownership marker'
contains "$CONFIG_FILE" 'time = 20:00' 'generated config is missing the enable time'
contains "$CONFIG_FILE" 'temperature = 4500' 'generated config is missing the scheduled temperature'
contains "$CONFIG_FILE" 'time = 07:00' 'generated config is missing the disable time'
contains "$CONFIG_FILE" 'identity = true' 'generated config does not restore identity at disable time'

# The visible On/Off button is a manual override. With a schedule still enabled,
# an actually-on Night Light must toggle off immediately without disabling the
# saved schedule. The schedule can take control again at its next boundary.
printf '%s\n' false >"$HYPRSUNSET_IDENTITY_FILE"
: >"$HYPRCTL_LOG"
bash "$SCRIPT" toggle >/dev/null
[[ "$(<"$HYPRSUNSET_IDENTITY_FILE")" == true ]] \
  || fail 'manual toggle did not turn Night Light off while its schedule remained enabled'
grep -Fxq 'hyprsunset identity get' "$HYPRCTL_LOG" \
  || fail 'manual toggle did not query the live Hyprsunset identity state'
status="$(bash "$SCRIPT" status)"
grep -Fqx 'schedule_enabled=1' <<<"$status" \
  || fail 'manual Night Light toggle incorrectly disabled its schedule'

status="$(bash "$SCRIPT" status)"
grep -Fqx 'schedule_enabled=1' <<<"$status" || fail 'status does not report enabled schedule'
grep -Fqx 'schedule_start=20:00' <<<"$status" || fail 'status lost schedule start time'
grep -Fqx 'schedule_end=07:00' <<<"$status" || fail 'status lost schedule end time'
grep -Fqx 'schedule_temperature=4500' <<<"$status" || fail 'status lost scheduled temperature'
grep -Fqx 'schedule_next_day=1' <<<"$status" || fail 'overnight schedule is not labeled next-day'

# A daytime window must not be labeled next-day.
bash "$SCRIPT" schedule set 07:00 20:00 5000 >/dev/null
status="$(bash "$SCRIPT" status)"
grep -Fqx 'schedule_next_day=0' <<<"$status" || fail 'same-day schedule is incorrectly labeled next-day'
grep -Fqx 'schedule_temperature=5000' <<<"$status" || fail 'updated scheduled temperature was not persisted'

# Invalid times must fail closed without modifying the last valid schedule.
before_state="$(sha256sum "$SCHEDULE_FILE" | awk '{print $1}')"
before_config="$(sha256sum "$CONFIG_FILE" | awk '{print $1}')"
if bash "$SCRIPT" schedule set 24:00 07:00 4500 >/dev/null 2>&1; then
  fail 'invalid 24:00 schedule time was accepted'
fi
[[ "$(sha256sum "$SCHEDULE_FILE" | awk '{print $1}')" == "$before_state" ]] \
  || fail 'invalid schedule changed persisted state'
[[ "$(sha256sum "$CONFIG_FILE" | awk '{print $1}')" == "$before_config" ]] \
  || fail 'invalid schedule changed generated config'

if bash "$SCRIPT" schedule set 20:00 20:00 4500 >/dev/null 2>&1; then
  fail 'identical enable/disable times were accepted'
fi

# Disabling removes only the Awtarchy-generated profile file while preserving
# the chosen schedule values for a later re-enable.
bash "$SCRIPT" schedule disable >/dev/null
[[ -f "$SCHEDULE_FILE" ]] || fail 'disabled schedule did not preserve saved values'
[[ ! -e "$CONFIG_FILE" ]] || fail 'Awtarchy-managed hyprsunset.conf remains after disabling'
status="$(bash "$SCRIPT" status)"
grep -Fqx 'schedule_enabled=0' <<<"$status" || fail 'status still reports schedule enabled after disabling'
grep -Fqx 'schedule_start=07:00' <<<"$status" || fail 'disabled schedule lost its saved start time'
grep -Fqx 'schedule_end=20:00' <<<"$status" || fail 'disabled schedule lost its saved end time'
grep -Fqx 'schedule_temperature=5000' <<<"$status" || fail 'disabled schedule lost its saved temperature'

bash "$SCRIPT" schedule enable >/dev/null
[[ -f "$CONFIG_FILE" ]] || fail 'saved schedule did not recreate hyprsunset.conf when re-enabled'
status="$(bash "$SCRIPT" status)"
grep -Fqx 'schedule_enabled=1' <<<"$status" || fail 'saved schedule did not re-enable'
bash "$SCRIPT" schedule disable >/dev/null

# Never overwrite a user-owned Hyprsunset configuration.
mkdir -p -- "$(dirname -- "$CONFIG_FILE")"
printf '%s\n' '# personal hyprsunset config' >"$CONFIG_FILE"
user_config_before="$(sha256sum "$CONFIG_FILE" | awk '{print $1}')"
if bash "$SCRIPT" schedule set 20:00 07:00 4500 >/dev/null 2>&1; then
  fail 'schedule overwrote an existing user-owned hyprsunset.conf'
fi
[[ "$(sha256sum "$CONFIG_FILE" | awk '{print $1}')" == "$user_config_before" ]] \
  || fail 'user-owned hyprsunset.conf changed after refused schedule write'

# Quick Settings must expose the saved schedule and route changes through the
# existing backend instead of directly editing files from QML.
contains "$BACKEND" 'night-light-schedule)' \
  'Quick Settings backend is missing the Night Light schedule action'
contains "$BACKEND" 'schedule_enabled:' \
  'Quick Settings status JSON does not expose Night Light schedule state'
contains "$QUICK_SETTINGS" 'property bool nightLightScheduleEditorOpen: false' \
  'Quick Settings is missing Night Light schedule editor state'
contains "$QUICK_SETTINGS" 'Set schedule:' \
  'Night Light card does not show its schedule'
contains "$QUICK_SETTINGS" 'function saveNightLightSchedule()' \
  'Night Light card cannot save a schedule'
contains "$QUICK_SETTINGS" '["night-light-schedule", "set"' \
  'Night Light schedule save does not use the Quick Settings backend'
contains "$QUICK_SETTINGS" '["night-light-schedule", "disable"]' \
  'Night Light schedule cannot be disabled from Quick Settings'
contains "$QUICK_SETTINGS" 'id: nightLightVibranceRow' \
  'Night Light and Vibrance are missing a shared row layout id'
contains "$QUICK_SETTINGS" 'readonly property real cardHeight: Math.max(nightContent.implicitHeight, vibranceContent.implicitHeight) + 16' \
  'Night Light and Vibrance do not derive one shared card height'
[[ "$(grep -Fc -- 'Layout.preferredHeight: nightLightVibranceRow.cardHeight' "$QUICK_SETTINGS")" -eq 2 ]] \
  || fail 'Night Light and Vibrance cards do not both use the shared row height'

# These are release-managed files. Keep every new stock state recognizable so
# later updates do not preserve Awtarchy's own previous version as a user edit.
missing_history=0
for rel in \
  .config/hypr/scripts/hyprsunset_ctl.sh \
  .config/hypr/scripts/hypr_quicksettings.sh \
  .config/quickshell/awtarchy/QuickSettings.qml
do
  case "$rel" in
    .config/hypr/scripts/hyprsunset_ctl.sh) source_file="$SCRIPT" ;;
    .config/hypr/scripts/hypr_quicksettings.sh) source_file="$BACKEND" ;;
    .config/quickshell/awtarchy/QuickSettings.qml) source_file="$QUICK_SETTINGS" ;;
  esac
  digest="$(sha256sum "$source_file" | awk '{print $1}')"
  if ! grep -Fq -- "$digest"$'\t'"$rel" "$HISTORY"; then
    printf 'MISSING_MANAGED_HASH %s\t%s\n' "$digest" "$rel" >&2
    missing_history=1
  fi
done
(( missing_history == 0 )) || fail 'managed history is missing current Night Light schedule stock hashes'

printf '%s\n' 'PASS: Night Light supports safe daily scheduling and authoritative manual toggles.'
