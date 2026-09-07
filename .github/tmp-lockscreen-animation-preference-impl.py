from hashlib import sha256
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{path}: expected exactly one match, found {count}: {old[:80]!r}"
        )
    p.write_text(text.replace(old, new, 1))


app = "config/hypr/scripts/quickshell_application_state.sh"
replace_once(
    app,
    "QUICK_SETTINGS_LAYOUT_SAVE_VERSION=1\nQUICK_SETTINGS_SECTIONS_JSON=",
    "QUICK_SETTINGS_LAYOUT_SAVE_VERSION=1\n"
    "LOCKSCREEN_ANIMATIONS_JSON='[\"random\",\"swarm\",\"edges\",\"center\",\"split\",\"off\"]'\n"
    "QUICK_SETTINGS_SECTIONS_JSON=",
)
replace_once(
    app,
    "\nvalidate_workspace_style() {",
    """
validate_lockscreen_animation() {
    local value="$1"
    if ! jq -e -n \\
        --arg value "$value" \\
        --argjson allowed "$LOCKSCREEN_ANIMATIONS_JSON" \\
        '$allowed | index($value) != null' >/dev/null 2>&1; then
        printf 'invalid lockscreen animation: %s\\n' "$value" >&2
        exit 2
    fi
}

validate_workspace_style() {""",
)
replace_once(
    app,
    "\nset_workspace_numbers() {",
    """
set_lockscreen_animation() {
    local value="$1"
    validate_lockscreen_animation "$value"
    new_tmp
    jq --arg value "$value" '.lockscreen_animation = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_workspace_numbers() {""",
)
replace_once(
    app,
    'case "$cmd" in\n    set-workspace-numbers)',
    '''case "$cmd" in
    set-lockscreen-animation)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_animation "$2"
        ;;
    set-workspace-numbers)''',
)
replace_once(
    app,
    "usage: %s {set-workspace-numbers",
    "usage: %s {set-lockscreen-animation <random|swarm|edges|center|split|off>|set-workspace-numbers",
)

bar = "config/quickshell/awtarchy/BarState.qml"
replace_once(
    bar,
    "    readonly property var workspaceLegacyStyleAliases: ({",
    '''    readonly property var lockscreenAnimationPresets: [
        { key: "random", label: "Random" },
        { key: "swarm", label: "Swarm" },
        { key: "edges", label: "Edges" },
        { key: "center", label: "Center" },
        { key: "split", label: "Split" },
        { key: "off", label: "Off" }
    ]
    readonly property var workspaceLegacyStyleAliases: ({''',
)
replace_once(
    bar,
    "            update_notifications_enabled: true,\n            monitors: {},",
    "            update_notifications_enabled: true,\n"
    '            lockscreen_animation: "random",\n'
    "            monitors: {},",
)
replace_once(
    bar,
    '''    function updateNotificationsEnabled() {
        return data().update_notifications_enabled !== false;
    }
''',
    '''    function lockscreenAnimationPreference() {
        const value = String(data().lockscreen_animation || "random");
        for (const preset of lockscreenAnimationPresets) {
            if (preset.key === value)
                return value;
        }
        return "random";
    }

    function updateNotificationsEnabled() {
        return data().update_notifications_enabled !== false;
    }
''',
)

quick = "config/quickshell/awtarchy/QuickSettings.qml"
manual = '''                                Text {
                                    Layout.fillWidth: true
                                    text: "Built-in manual for keybinds, Quickshell, display, gaming, packages, maintenance, networking, troubleshooting, and Extra Notes."
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(8)
                                    wrapMode: Text.Wrap
                                }
'''
controls = manual + '''
                                Text {
                                    Layout.fillWidth: true
                                    text: "Lockscreen Animation"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(9)
                                    font.bold: true
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: childrenRect.height
                                    spacing: 5

                                    Repeater {
                                        model: BarState.lockscreenAnimationPresets

                                        SettingsButton {
                                            required property var modelData
                                            label: String(modelData.label)
                                            active: BarState.lockscreenAnimationPreference()
                                                === String(modelData.key)
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueStateCommand([
                                                "set-lockscreen-animation", String(modelData.key)
                                            ])
                                        }
                                    }
                                }
'''
replace_once(quick, manual, controls)

shell = "config/quickshell/awtarchy-lock/shell.qml"
replace_once(
    shell,
    '''    property bool unlockRequested: false

    Component.onCompleted: Quickshell.watchFiles = false
''',
    '''    property bool unlockRequested: false
    readonly property string statePath: (Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")) + "/awtarchy/quickshell-state.json"
    property string lockAnimationPreference: "random"
    property int randomFormationMode: Math.floor(Math.random() * 4)
    readonly property var allowedAnimationPreferences: [
        "random", "swarm", "edges", "center", "split", "off"
    ]

    function normalizedAnimationPreference(value) {
        const key = String(value || "");
        return allowedAnimationPreferences.indexOf(key) >= 0 ? key : "random";
    }

    function loadAnimationPreference() {
        const text = stateFile.text();
        if (!text || text.length === 0) {
            lockAnimationPreference = "random";
            return;
        }

        try {
            const parsed = JSON.parse(text);
            lockAnimationPreference = normalizedAnimationPreference(
                parsed && typeof parsed === "object" ? parsed.lockscreen_animation : "random");
        } catch (error) {
            lockAnimationPreference = "random";
        }
    }

    Component.onCompleted: {
        Quickshell.watchFiles = false;
        root.loadAnimationPreference();
    }

    FileView {
        id: stateFile
        path: root.statePath
        blockLoading: true
        printErrors: false
        onLoaded: root.loadAnimationPreference()
    }
''',
)
replace_once(
    shell,
    "                unlocking: root.unlockRequested\n",
    "                unlocking: root.unlockRequested\n"
    "                animationPreference: root.lockAnimationPreference\n"
    "                randomFormationMode: root.randomFormationMode\n",
)

surface = "config/quickshell/awtarchy-lock/LockSurface.qml"
replace_once(
    surface,
    "    required property bool unlocking\n",
    "    required property bool unlocking\n"
    "    required property string animationPreference\n"
    "    required property int randomFormationMode\n",
)
replace_once(
    surface,
    "    readonly property int formationMode: Math.floor(Math.random() * 4)",
    '''    readonly property int formationMode: animationPreference === "swarm" ? 0
        : animationPreference === "edges" ? 1
        : animationPreference === "center" ? 2
        : animationPreference === "split" ? 3
        : randomFormationMode''',
)
replace_once(
    surface,
    "                                property real formationProgress: 0",
    '''                                property real formationProgress:
                                    root.animationPreference === "off" ? 1 : 0''',
)
replace_once(
    surface,
    '''                                    running: wordmarkCell.isFilledGlyph
                                        && root.entered && !root.unlocking
''',
    '''                                    running: wordmarkCell.isFilledGlyph
                                        && root.entered && !root.unlocking
                                        && root.animationPreference !== "off"
''',
)

history = Path("local/share/awtarchy/quickshell-managed-history.sha256")
history_text = history.read_text()
managed = [
    (
        "config/hypr/scripts/quickshell_application_state.sh",
        ".config/hypr/scripts/quickshell_application_state.sh",
    ),
    (
        "config/quickshell/awtarchy/BarState.qml",
        ".config/quickshell/awtarchy/BarState.qml",
    ),
    (
        "config/quickshell/awtarchy/QuickSettings.qml",
        ".config/quickshell/awtarchy/QuickSettings.qml",
    ),
]
additions = []
for source, target in managed:
    digest = sha256(Path(source).read_bytes()).hexdigest()
    line = f"{digest}\t{target}"
    if line not in history_text.splitlines():
        additions.append(line)
if additions:
    if not history_text.endswith("\n"):
        history_text += "\n"
    history.write_text(history_text + "\n".join(additions) + "\n")
