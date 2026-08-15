#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "local/share/awtarchy/awtarchy-runtime.sh"

runtime = RUNTIME.read_text(encoding="utf-8")
start = runtime.index("build_plan() {")
block = runtime[start:]
marker = '''  python3 - "$HOME_DIR" "$target_home" "$BASELINE_HOME" "$MANIFEST_FILE" "$plan_file" <<'PY'\n'''
try:
    planner = block.split(marker, 1)[1].split("\nPY\n}", 1)[0]
except IndexError as exc:
    raise SystemExit("FAIL: could not extract build_plan Python implementation") from exc


def plan_class(rel: str, baseline_text: str, local_text: str, target_text: str):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        home = root / "home"
        target = root / "target"
        baseline = root / "baseline"
        manifest = root / "manifest.paths"
        output = root / "plan.tsv"
        planner_file = root / "planner.py"
        planner_file.write_text(planner, encoding="utf-8")
        for base, text in ((home, local_text), (target, target_text), (baseline, baseline_text)):
            path = base / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        manifest.write_text(rel + "\n", encoding="utf-8")
        subprocess.run(
            ["python3", str(planner_file), str(home), str(target), str(baseline), str(manifest), str(output)],
            check=True,
        )
        rows = [line.split("\t", 1)[0] for line in output.read_text(encoding="utf-8").splitlines() if line]
        if not rows:
            return None
        if len(rows) != 1:
            raise AssertionError(f"unexpected plan rows for {rel}: {rows}")
        return rows[0]


speed_base = r'''[General]
ConfigVersion=1200

[SpeedCrunch]
Display\DisplayFont="NotoSansM Nerd Font Mono,15,-1,5,50,0,0,0,0,0,Regular"
General\AutoCalc=true
Layout\State=@ByteArray(BASE-STATE)
Layout\ManualWindowGeometry=@ByteArray(BASE-MANUAL)
Layout\WindowGeometry=@ByteArray(BASE-GEOMETRY)
Layout\WindowOnFullScreen=false
'''
speed_noise = (
    speed_base.replace("BASE-STATE", "LIVE-STATE")
    .replace("BASE-MANUAL", "LIVE-MANUAL")
    .replace("BASE-GEOMETRY", "LIVE-GEOMETRY")
    .replace("Layout\\WindowOnFullScreen=false", "Layout\\WindowOnFullScreen=true")
)
assert plan_class(".config/SpeedCrunch/SpeedCrunch.ini", speed_base, speed_noise, speed_base) is None
speed_user = speed_noise.replace(",15,-1", ",12,-1")
assert plan_class(".config/SpeedCrunch/SpeedCrunch.ini", speed_base, speed_user, speed_base) == "USER"
speed_target = speed_base.replace("General\\AutoCalc=true", "General\\AutoCalc=false")
assert plan_class(".config/SpeedCrunch/SpeedCrunch.ini", speed_base, speed_noise, speed_target) == "OUTDATED"

pcman_base = r'''[Desktop]
Font="NotoSansM Nerd Font Mono,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
ShowHidden=false
WallpaperDialogSize=@Size(700 500)
WallpaperDialogSplitterPos=200

[FolderView]
CustomColumnWidths=@Invalid()
NoItemTooltip=false
ShowHidden=false
SortColumn=crtime

[Search]
ContentPatterns=@Invalid()
NamePatterns=@Invalid()
searchRecursive=false

[Window]
LastWindowHeight=1032
LastWindowMaximized=true
LastWindowWidth=1900
SidePaneVisible=true
SplitViewTabsNum=0
SplitterPos=245
TabPaths=@Invalid()
'''
pcman_noise = r'''[Desktop]
Font="NotoSansM Nerd Font Mono,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
NoItemTooltip=false
ScreenNames=@Invalid()
ShowHidden=false
WallpaperDialogSize=@Size(910 650)
WallpaperDialogSplitterPos=311

[FolderView]
CustomColumnWidths=@ByteArray(LIVE)
NoItemTooltip=false
ShowHidden=false
SortColumn=crtime

[Search]
ContentPatterns=*.txt
NamePatterns=notes*
searchRecursive=false

[Window]
LastWindowHeight=509
LastWindowMaximized=false
LastWindowWidth=943
SidePaneVisible=true
SplitViewTabsNum=3
SplitterPos=174
TabPaths=/tmp
'''
assert plan_class(".config/pcmanfm-qt/default/settings.conf", pcman_base, pcman_noise, pcman_base) is None
pcman_user = pcman_noise.replace("ShowHidden=false\nSortColumn=crtime", "ShowHidden=true\nSortColumn=mtime")
assert plan_class(".config/pcmanfm-qt/default/settings.conf", pcman_base, pcman_user, pcman_base) == "USER"
pcman_tooltip = pcman_noise.replace("NoItemTooltip=false\nScreenNames", "NoItemTooltip=true\nScreenNames", 1)
assert plan_class(".config/pcmanfm-qt/default/settings.conf", pcman_base, pcman_tooltip, pcman_base) == "USER"

micro_base = '''{\n  "Alt-/": "lua:comment.comment",\n  "MouseWheelUp": "CursorUp,CursorUp"\n}'''
micro_format = '''{\n    "MouseWheelUp": "CursorUp,CursorUp",\n    "Alt-/": "lua:comment.comment"\n}\n'''
assert plan_class(".config/micro/bindings.json", micro_base, micro_format, micro_base) is None
micro_user = micro_format.replace("CursorUp,CursorUp", "CursorUp,CursorUp,CursorUp")
assert plan_class(".config/micro/bindings.json", micro_base, micro_user, micro_base) == "USER"

qt_base = '''[Appearance]\nstyle=kvantum-dark\n\n[SettingsWindow]\ngeometry=@ByteArray(BASE)\n'''
qt_noise = qt_base.replace("BASE", "LIVE")
for rel in (".config/qt5ct/qt5ct.conf", ".config/qt6ct/qt6ct.conf"):
    assert plan_class(rel, qt_base, qt_noise, qt_base) is None
    assert plan_class(rel, qt_base, qt_noise.replace("style=kvantum-dark", "style=fusion"), qt_base) == "USER"

print("PASS: volatile application state is ignored without hiding meaningful config changes.")
