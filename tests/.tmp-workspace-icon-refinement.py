from pathlib import Path
import hashlib


def repl(path, old, new):
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"missing expected block: {path}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


# Curated workspace packs and compatibility aliases.
p = Path("config/quickshell/awtarchy/BarState.qml")
text = p.read_text(encoding="utf-8")
start = text.index("    readonly property var workspaceIconStylePresets:")
end = text.index("\n\n\n    property int revision:", start)
catalog = '''    readonly property var workspaceIconStylePresets: [
        { key: "off", label: "Off", symbols: [], glyphSize: 18, glyphYOffset: 0 },
        {
            key: "awtarchy",
            label: "Awtarchy",
            symbols: ["󰞷", "", "", "", "", "", "", "", "", ""],
            glyphSize: 20,
            glyphYOffset: 0
        },
        {
            key: "workflow",
            label: "Workflow",
            symbols: ["", "", "", "", "", "", "", "", "", ""],
            glyphSize: 20,
            glyphYOffset: -1
        },
        {
            key: "phases",
            label: "Phases",
            symbols: ["◐", "◑", "◒", "◓", "◔", "◕", "○", "●", "◉", "◎"],
            glyphSize: 22,
            glyphYOffset: -2
        },
        { key: "custom-symbol", label: "Custom", symbols: [], glyphSize: 18, glyphYOffset: 0 }
    ];
    readonly property var workspaceStylePresets: [
        { key: "awtarchy", label: "Awtarchy", sample: "1󰞷" },
        { key: "numbers", label: "Numbers", sample: "1" },
        { key: "icons", label: "Icons", sample: "󰞷" },
        { key: "workflow", label: "Workflow", sample: "" },
        { key: "phases", label: "Phases", sample: "◐◑" },
        { key: "custom-symbol", label: "Custom", sample: "…" }
    ]
    readonly property var launcherIconPresets: [
        { label: "Awtarchy", value: "" },
        { label: "Menu", value: "☰" },
        { label: "Tux", value: "" },
        { label: "Arch", value: "" },
        { label: "Diamond", value: "◆" },
        { label: "Circle", value: "●" }
    ]
    readonly property var workspaceLegacyStyleAliases: ({
        "filled-dot": "workflow",
        "filled-diamond": "workflow",
        "center-diamond": "workflow",
        "filled-square": "workflow",
        "small-square": "workflow",
        "filled-triangle": "workflow",
        "spark": "workflow",
        "minimal-bar": "workflow",
        "dots": "workflow",
        "diamonds": "workflow",
        "squares": "workflow",
        "triangles": "workflow",
        "minimal": "workflow"
    })'''
p.write_text(text[:start] + catalog + text[end:], encoding="utf-8")

repl(
    str(p),
    '''    function workspaceIconPixelSize() {
        const pack = workspaceIconPackFor(workspaceIconStyle());
        const size = pack ? Number(pack.glyphSize) : 18;
        return Number.isFinite(size) ? Math.max(8, Math.round(size)) : 18;
    }

    function workspaceIconFor(id) {''',
    '''    function workspaceIconPixelSize() {
        const pack = workspaceIconPackFor(workspaceIconStyle());
        const size = pack ? Number(pack.glyphSize) : 18;
        return Number.isFinite(size) ? Math.max(8, Math.round(size)) : 18;
    }

    function workspaceIconYOffset() {
        const pack = workspaceIconPackFor(workspaceIconStyle());
        const offset = pack ? Number(pack.glyphYOffset) : 0;
        return Number.isFinite(offset)
            ? Math.max(-4, Math.min(4, Math.round(offset))) : 0;
    }

    function workspaceIconFor(id) {'''
)

repl(
    "config/hypr/scripts/quickshell_application_state.sh",
    '''WORKSPACE_STYLES_JSON='["awtarchy","numbers","icons","phases","dots","diamonds","custom-symbol"]'
WORKSPACE_ICON_STYLES_JSON='["off","awtarchy","phases","dots","diamonds","custom-symbol"]' ''',
    '''WORKSPACE_STYLES_JSON='["awtarchy","numbers","icons","workflow","phases","custom-symbol"]'
WORKSPACE_ICON_STYLES_JSON='["off","awtarchy","workflow","phases","custom-symbol"]' '''
)

# Completion-aware, serialized clipboard writes.
p = Path("config/quickshell/awtarchy/BarIconSettings.qml")
text = p.read_text(encoding="utf-8")
repl_old = '''    property var identityCommandQueue: []
    property string identityError: ""'''
repl_new = '''    property var identityCommandQueue: []
    property var clipboardQueue: []
    property var activeClipboardCopy: null
    property string identityError: ""'''
if repl_old not in text:
    raise SystemExit("missing BarIconSettings property block")
text = text.replace(repl_old, repl_new, 1)

start = text.index("    function copyText(text) {")
end = text.index("    function enqueueIdentity(args, statusMessage) {", start)
clipboard_functions = '''    function enqueueClipboardCopy(text, kind, key, successText) {
        const value = String(text || "");
        if (value.length === 0)
            return;
        const queue = clipboardQueue.slice();
        queue.push({
            text: value,
            kind: String(kind || ""),
            key: String(key || ""),
            successText: String(successText || "Copied")
        });
        clipboardQueue = queue;
        runNextClipboardCopy();
    }

    function runNextClipboardCopy() {
        if (clipboardWriter.running || activeClipboardCopy !== null
                || clipboardQueue.length === 0)
            return;
        const next = clipboardQueue[0];
        clipboardQueue = clipboardQueue.slice(1);
        activeClipboardCopy = next;
        clipboardWriter.exec(["wl-copy", "--type", "text/plain", "--", next.text]);
    }

    function completeClipboardCopy(next) {
        if (next.kind === "workspace-symbol") {
            copiedWorkspaceKey = next.key;
            copiedWorkspacePack = "";
            workspaceCopyFeedback = next.successText;
            workspaceCopyFeedbackTimer.restart();
        } else if (next.kind === "workspace-pack") {
            copiedWorkspaceKey = "";
            copiedWorkspacePack = next.key;
            workspaceCopyFeedback = next.successText;
            workspaceCopyFeedbackTimer.restart();
        } else if (next.kind === "launcher") {
            copiedLauncherValue = next.key;
            launcherCopyFeedback = next.successText;
            launcherCopyFeedbackTimer.restart();
        }
    }

    function failClipboardCopy(next) {
        if (!next)
            return;
        if (next.kind === "launcher") {
            copiedLauncherValue = "";
            launcherCopyFeedback = "Copy failed";
            launcherCopyFeedbackTimer.restart();
        } else {
            copiedWorkspaceKey = "";
            copiedWorkspacePack = "";
            workspaceCopyFeedback = "Copy failed";
            workspaceCopyFeedbackTimer.restart();
        }
    }

    function copyWorkspaceSymbol(text, key) {
        const value = String(text || "");
        enqueueClipboardCopy(value, "workspace-symbol", key, "Copied · " + value);
    }

    function copyWorkspacePack(styleKey, text) {
        enqueueClipboardCopy(String(text || ""), "workspace-pack", styleKey, "Copied all");
    }

    function copyLauncherIcon(value) {
        const text = String(value || "");
        enqueueClipboardCopy(text, "launcher", text, "Copied · " + text);
    }

'''
text = text[:start] + clipboard_functions + text[end:]

marker = '''    Process {
        id: identityWriter
'''
clipboard_process = '''    Process {
        id: clipboardWriter
        onExited: (exitCode, exitStatus) => {
            const next = root.activeClipboardCopy;
            root.activeClipboardCopy = null;
            if (next !== null) {
                if (exitCode === 0)
                    root.completeClipboardCopy(next);
                else
                    root.failClipboardCopy(next);
            }
            root.runNextClipboardCopy();
        }
    }

'''
if marker not in text:
    raise SystemExit("missing identity Process marker")
text = text.replace(marker, clipboard_process + marker, 1)

old = '''                        onClicked: root.copyWorkspacePack(packRow.modelData)
'''
new = '''                        onClicked: root.copyWorkspacePack(
                            String(packRow.modelData.key),
                            packRow.modelData.symbols.join(" "))
'''
if old not in text:
    raise SystemExit("missing Copy all action")
text = text.replace(old, new, 1)

old = '''                SettingsButton {
                    label: " Copy"
                    textSize: 8
                    horizontalPadding: 6
                    active: root.copiedLauncherValue === launcherPreset.modelData.value
                    onClicked: root.copyLauncherIcon(launcherPreset.modelData.value)
                }
'''
new = '''                SettingsButton {
                    Layout.preferredWidth: 30
                    label: root.copiedLauncherValue === launcherPreset.modelData.value
                        ? "✓" : ""
                    textSize: 9
                    horizontalPadding: 4
                    active: root.copiedLauncherValue === launcherPreset.modelData.value
                    onClicked: root.copyLauncherIcon(launcherPreset.modelData.value)
                }
'''
if old not in text:
    raise SystemExit("missing launcher Copy button")
text = text.replace(old, new, 1)
p.write_text(text, encoding="utf-8")

# Optical vertical alignment for workspace glyphs only.
repl(
    "config/quickshell/awtarchy/BarButton.qml",
    '''    property int workspaceGlyphSize: 0
''',
    '''    property int workspaceGlyphSize: 0
    property int workspaceGlyphYOffset: 0
'''
)
repl(
    "config/quickshell/awtarchy/BarButton.qml",
    '''    function partFontFamily(part) {
        return Theme.fontFamily;
    }

''',
    '''    function partFontFamily(part) {
        return Theme.fontFamily;
    }

    function workspacePartYOffset(part) {
        return workspaceButton && !/^\\d+$/.test(String(part))
            ? workspaceGlyphYOffset : 0;
    }

'''
)
repl(
    "config/quickshell/awtarchy/BarButton.qml",
    '''            id: normalText
            anchors.centerIn: parent
''',
    '''            id: normalText
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.workspacePartYOffset(root.displayLabel)
'''
)
repl(
    "config/quickshell/awtarchy/BarButton.qml",
    '''                        id: tokenText
                        anchors.centerIn: parent
                        text: String(parent.modelData)
''',
    '''                        id: tokenText
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: root.workspacePartYOffset(String(parent.modelData))
                        text: String(parent.modelData)
'''
)

p = Path("config/quickshell/awtarchy/Bar.qml")
text = p.read_text(encoding="utf-8")
needle = '''                workspaceGlyphSize: BarState.workspaceIconPixelSize()
'''
if text.count(needle) != 2:
    raise SystemExit("workspace glyph binding count changed")
text = text.replace(
    needle,
    needle + '''                workspaceGlyphYOffset: BarState.workspaceIconYOffset()
'''
)
p.write_text(text, encoding="utf-8")

# Existing tests follow the curated catalog.
p = Path("tests/test-theme-picker-workspace-composition.sh")
text = p.read_text(encoding="utf-8")
text = text.replace("set-workspace-icon-style diamonds", "set-workspace-icon-style workflow", 1)
text = text.replace(
    '.bar_appearance.workspace_icon_style == "diamonds"',
    '.bar_appearance.workspace_icon_style == "workflow"',
    1,
)
p.write_text(text, encoding="utf-8")

p = Path("tests/test-bar-icon-customization.sh")
text = p.read_text(encoding="utf-8")
text = text.replace(
    "awtarchy numbers icons phases dots diamonds custom-symbol",
    "awtarchy numbers icons workflow phases custom-symbol",
    1,
)
text = text.replace(
    "squares triangles minimal\ndo",
    "dots diamonds squares triangles minimal\ndo",
    1,
)
for old, new in (
    ('"center-diamond": "diamonds"', '"center-diamond": "workflow"'),
    ('"spark": "dots"', '"spark": "workflow"'),
    ('"squares": "diamonds"', '"squares": "workflow"'),
    ('"triangles": "diamonds"', '"triangles": "workflow"'),
    ('"minimal": "dots"', '"minimal": "workflow"'),
):
    text = text.replace(old, new)
anchor = '''contains "$BAR_STATE" '"spark": "workflow"' \\
    'legacy Spark state does not migrate to a supported pack'
'''
extra = '''contains "$BAR_STATE" '"dots": "workflow"' \\
    'testing-branch Dots state does not migrate to Workflow'
contains "$BAR_STATE" '"diamonds": "workflow"' \\
    'testing-branch Diamonds state does not migrate to Workflow'
'''
if anchor not in text:
    raise SystemExit("missing legacy alias test anchor")
text = text.replace(anchor, anchor + extra, 1)
old = "for symbol in '◐' '◑' '◒' '◓' '◔' '◕' '○' '●' '◉' '◎' '◆'\ndo"
new = "for symbol in '◐' '◑' '◒' '◓' '◔' '◕' '○' '●' '◉' '◎' \\\n    '' '' '' '' '' '' '' '' '' ''\ndo"
if old not in text:
    raise SystemExit("missing old workspace symbol test")
text = text.replace(old, new, 1)
p.write_text(text, encoding="utf-8")

# Managed updater history for every changed installed file.
history = Path("local/share/awtarchy/quickshell-managed-history.sha256")
history_text = history.read_text(encoding="utf-8")
managed = {
    "config/hypr/scripts/quickshell_application_state.sh": ".config/hypr/scripts/quickshell_application_state.sh",
    "config/quickshell/awtarchy/Bar.qml": ".config/quickshell/awtarchy/Bar.qml",
    "config/quickshell/awtarchy/BarButton.qml": ".config/quickshell/awtarchy/BarButton.qml",
    "config/quickshell/awtarchy/BarIconSettings.qml": ".config/quickshell/awtarchy/BarIconSettings.qml",
    "config/quickshell/awtarchy/BarState.qml": ".config/quickshell/awtarchy/BarState.qml",
}
for repo_path, managed_path in managed.items():
    digest = hashlib.sha256(Path(repo_path).read_bytes()).hexdigest()
    line = f"{digest}\t{managed_path}"
    if line not in history_text:
        if not history_text.endswith("\n"):
            history_text += "\n"
        history_text += line + "\n"
history.write_text(history_text, encoding="utf-8")
