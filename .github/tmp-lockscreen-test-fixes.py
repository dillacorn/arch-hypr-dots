from pathlib import Path


def replace_once(path, old, new):
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one exact match, found {count}: {old[:120]!r}")
    file.write_text(text.replace(old, new, 1))


path = "tests/test-quickshell-lockscreen-interactive-effects.sh"
replace_once(
    path,
    '''require_text "$SCENE_QML" 'root.showWeather && root.weatherText.length > 0' \\
    'weather metadata does not fail closed when the local cache is empty'
''',
    '''require_text "$SCENE_QML" 'root.presentationVisible("weather", root.showWeather) && root.weatherText.length > 0' \\
    'weather metadata does not fail closed when the local cache is empty'
'''
)
