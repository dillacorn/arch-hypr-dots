from pathlib import Path


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match in {path}, found {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


detector = "config/hypr/scripts/quickshell_battery_care.sh"
replace_once(
    detector,
    'tlp_output=""\ntlp_available=false\n',
    '''tlp_output=""\ntlp_available=false\n\nbattery_plugin_writable() {\n    case "$1" in\n        asus|cros-ec|dell|huawei|thinkpad|thinkpad-legacy|lenovo|lenovo-legacy|lg|macbook|msi|samsung|sony|system76|toshiba|tuxedo|wilco-ec) return 0 ;;\n        *) return 1 ;;\n    esac\n}\n''',
    "detector writable policy",
)
replace_once(
    detector,
    'mode="unsupported"\nbackend="none"\nsupported=false\nstart_min=null\n',
    'mode="unsupported"\nbackend="none"\nsupported=false\nwritable=false\ncompatibility="unsupported"\nstart_min=null\n',
    "detector compatibility state",
)
replace_once(
    detector,
    '''if [[ "$tlp_supported" == true ]]; then\n    supported=true\n    backend="tlp"\n\n    case "$plugin_lower" in\n''',
    '''if [[ "$tlp_supported" == true ]]; then\n    supported=true\n    backend="tlp"\n    if battery_plugin_writable "$plugin_lower"; then\n        writable=true\n        compatibility="validated"\n    else\n        compatibility="unvalidated"\n    fi\n\n    case "$plugin_lower" in\n''',
    "detector TLP classification",
)
replace_once(
    detector,
    '''elif [[ "$sysfs_supported" == true ]]; then\n    supported=true\n    backend="sysfs"\n    mode="sysfs"\nfi\n''',
    '''elif [[ "$sysfs_supported" == true && "$plugin_lower" != "generic" ]]; then\n    supported=true\n    writable=false\n    compatibility="unvalidated"\n    backend="sysfs"\n    mode="sysfs"\nfi\n''',
    "detector sysfs classification",
)
replace_once(
    detector,
    '''fi\n\njq -cn \\\n    --argjson supported "$supported" \\\n    --arg backend "$backend" \\\n''',
    '''fi\n\nif [[ "$compatibility" == "unvalidated" && "$backend" == "tlp" ]]; then\n    summary="Battery Care detected but not validated by Awtarchy"\n    detail="Write controls are disabled for this backend."\nfi\n\njq -cn \\\n    --argjson supported "$supported" \\\n    --argjson writable "$writable" \\\n    --arg compatibility "$compatibility" \\\n    --arg backend "$backend" \\\n''',
    "detector JSON arguments",
)
replace_once(
    detector,
    '''    {\n        supported:$supported,\n        backend:$backend,\n''',
    '''    {\n        supported:$supported,\n        writable:$writable,\n        compatibility:$compatibility,\n        backend:$backend,\n''',
    "detector JSON object",
)

card = "config/quickshell/awtarchy/BatteryCareCard.qml"
replace_once(
    card,
    '''    readonly property bool controlsAvailable: Boolean(statusData.supported)\n        && String(statusData.backend || "") === "tlp"\n''',
    '''    readonly property bool controlsAvailable: Boolean(statusData.supported)\n        && Boolean(statusData.writable)\n        && String(statusData.backend || "") === "tlp"\n''',
    "QML write gate",
)
replace_once(
    card,
    '''        return ({\n            supported: false,\n            backend: "none",\n''',
    '''        return ({\n            supported: false,\n            writable: false,\n            compatibility: "unsupported",\n            backend: "none",\n''',
    "QML empty compatibility state",
)

helper = "local/libexec/awtarchy/power-profile-helper"
replace_once(
    helper,
    '''battery_plugin_allowed() {\n  case "$1" in\n    macbook|asus|cros-ec|dell|huawei|thinkpad|thinkpad-legacy|lenovo|lenovo-legacy|lg|lg-legacy|msi|samsung|sony|system76|toshiba|tuxedo|wilco-ec) return 0 ;;\n    *) return 1 ;;\n  esac\n}\n''',
    '''battery_plugin_writable() {\n  case "$1" in\n    macbook|asus|cros-ec|dell|huawei|thinkpad|thinkpad-legacy|lenovo|lenovo-legacy|lg|msi|samsung|sony|system76|toshiba|tuxedo|wilco-ec) return 0 ;;\n    *) return 1 ;;\n  esac\n}\n''',
    "helper writable policy",
)
replace_once(
    helper,
    '  battery_plugin_allowed "$plugin" || fail "unsupported TLP battery-care plugin: $plugin"\n',
    '  battery_plugin_writable "$plugin" || fail "unsupported TLP battery-care plugin: $plugin"\n',
    "helper capability gate",
)
replace_once(
    helper,
    '''battery_dual_config_plugin() {\n  case "$1" in\n    asus|cros-ec|dell|thinkpad|thinkpad-legacy|msi|toshiba) return 0 ;;\n    *) return 1 ;;\n  esac\n}\n''',
    '''battery_dual_config_plugin() {\n  case "$1" in\n    asus|cros-ec|dell|thinkpad|thinkpad-legacy|msi|toshiba|lenovo|tuxedo) return 0 ;;\n    *) return 1 ;;\n  esac\n}\n''',
    "helper dual config policy",
)
replace_once(
    helper,
    '''    lg|lg-legacy)\n      [[ "$target" == 80 ]] || fail 'LG battery care mode only supports an 80% health target'\n      start_value=0\n      stop_value=1\n      ;;\n''',
    '''    lg)\n      [[ "$target" == 80 ]] || fail 'LG battery care mode only supports an 80% health target'\n      start_value=0\n      stop_value=80\n      ;;\n''',
    "current LG semantics",
)

control = "tests/test-battery-care-control.sh"
replace_once(
    control,
    '''        lg)\n          target=$([[ "$stop" == 1 ]] && printf 80 || printf 100)\n          enabled=$([[ "$target" -lt 100 ]] && printf 1 || printf 0)\n          ;;\n''',
    '''        lg)\n          target="$stop"\n          enabled=$([[ "$target" -lt 100 ]] && printf 1 || printf 0)\n          ;;\n''',
    "control LG fake",
)
replace_once(
    control,
    '''grep -Fxq 'START_CHARGE_THRESH_BAT0=70' "$MANAGED" || fail 'Tuxedo supported start threshold was not selected'\ngrep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$MANAGED" || fail 'Tuxedo stop preset was not persisted'\n''',
    '''grep -Fxq 'START_CHARGE_THRESH_BAT0=70' "$MANAGED" || fail 'Tuxedo supported start threshold was not selected'\ngrep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$MANAGED" || fail 'Tuxedo stop preset was not persisted'\ngrep -Fxq 'START_CHARGE_THRESH_BAT1=70' "$MANAGED" || fail 'Tuxedo BAT1 supported start threshold was not selected'\ngrep -Fxq 'STOP_CHARGE_THRESH_BAT1=80' "$MANAGED" || fail 'Tuxedo BAT1 stop preset was not persisted'\n''',
    "control Tuxedo BAT1",
)
replace_once(
    control,
    '''grep -Fxq 'START_CHARGE_THRESH_BAT0=0' "$MANAGED" || fail 'Lenovo dummy start threshold missing'\ngrep -Fxq 'STOP_CHARGE_THRESH_BAT0=1' "$MANAGED" || fail 'Lenovo Long_Life selector was not persisted'\ngrep -Fq 'enabled=1' "$STATE" || fail 'Lenovo fixed mode was not read back as enabled'\n''',
    '''grep -Fxq 'START_CHARGE_THRESH_BAT0=0' "$MANAGED" || fail 'Lenovo dummy start threshold missing'\ngrep -Fxq 'STOP_CHARGE_THRESH_BAT0=1' "$MANAGED" || fail 'Lenovo Long_Life selector was not persisted'\ngrep -Fxq 'START_CHARGE_THRESH_BAT1=0' "$MANAGED" || fail 'Lenovo BAT1 dummy start threshold missing'\ngrep -Fxq 'STOP_CHARGE_THRESH_BAT1=1' "$MANAGED" || fail 'Lenovo BAT1 Long_Life selector was not persisted'\ngrep -Fq 'enabled=1' "$STATE" || fail 'Lenovo fixed mode was not read back as enabled'\n''',
    "control Lenovo BAT1",
)
replace_once(
    control,
    '''grep -Fxq 'START_CHARGE_THRESH_BAT0=0' "$MANAGED" || fail 'LG dummy start threshold missing'\ngrep -Fxq 'STOP_CHARGE_THRESH_BAT0=1' "$MANAGED" || fail 'LG 80% target was not translated to battery-care selector 1'\ngrep -Fq 'target=80' "$STATE" || fail 'LG 80% state was not verified'\n''',
    '''grep -Fxq 'START_CHARGE_THRESH_BAT0=0' "$MANAGED" || fail 'LG dummy start threshold missing'\ngrep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$MANAGED" || fail 'LG 80% target was not persisted literally'\ngrep -Fq 'target=80' "$STATE" || fail 'LG 80% state was not verified'\n''',
    "control LG assertion",
)
replace_once(
    control,
    '''repair_v354_sony_battery_disable_repo "$V354_REPO" v3.5.4\ncmp -s -- "$HELPER" "$V354_REPO/local/libexec/awtarchy/power-profile-helper" \\\n  || fail 'v3.5.4 post-release repair did not reconstruct the tested Sony helper'\nbash -n "$V354_REPO/local/libexec/awtarchy/power-profile-helper" \\\n''',
    '''repair_v354_sony_battery_disable_repo "$V354_REPO" v3.5.4\nV354_EXPECTED="$TMP/v354-expected-power-profile-helper"\ncp -- "$V354_FIXTURE" "$V354_EXPECTED"\npython3 - "$V354_EXPECTED" <<'PY_V354_EXPECTED'\nfrom pathlib import Path\nimport sys\npath = Path(sys.argv[1])\ntext = path.read_text(encoding="utf-8")\nold = """    huawei)\n      /usr/bin/grep -Eq 'charge_control_thresholds[^=]*=[[:space:]]*[0-9]+[[:space:]]+100([^0-9]|$)' <<<"$report"\n      ;;\n    *)\n"""\nnew = """    huawei)\n      /usr/bin/grep -Eq 'charge_control_thresholds[^=]*=[[:space:]]*[0-9]+[[:space:]]+100([^0-9]|$)' <<<"$report"\n      ;;\n    sony)\n      /usr/bin/grep -Eq 'battery_care_limiter[^=]*=[[:space:]]*0([^0-9]|$)' <<<"$report"\n      ;;\n    *)\n"""\nif text.count(old) != 1:\n    raise SystemExit("v3.5.4 fixture did not contain the expected pre-repair helper source")\npath.write_text(text.replace(old, new, 1), encoding="utf-8")\nPY_V354_EXPECTED\ncmp -s -- "$V354_EXPECTED" "$V354_REPO/local/libexec/awtarchy/power-profile-helper" \\\n  || fail 'v3.5.4 post-release repair changed more than the Sony disable verifier'\nbash -n "$V354_REPO/local/libexec/awtarchy/power-profile-helper" \\\n''',
    "stable Sony repair expectation",
)
