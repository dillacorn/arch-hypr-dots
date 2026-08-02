#!/usr/bin/env python3
from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[1]
runpy.run_path(str(ROOT / "tools/apply-updater-hotfix-v2.py"), run_name="__main__")

replacements = {
    ROOT / "tests/test-awtarchy-command.sh": (
        "grep -Fq '\"${bin_dir}/awtarchy\" self-update' \"$RUNTIME_SOURCE\" \\\n",
        "# shellcheck disable=SC2016\n"
        "grep -Fq '\"${bin_dir}/awtarchy\" self-update' \"$RUNTIME_SOURCE\" \\\n",
    ),
    ROOT / "tests/test-lua-validation.sh": (
        "grep -Fq 'AWTARCHY_LUA_VALIDATE_FILE=\"$file\" lua -e' \"$TMP/validate_candidate.sh\" \\\n",
        "# shellcheck disable=SC2016\n"
        "grep -Fq 'AWTARCHY_LUA_VALIDATE_FILE=\"$file\" lua -e' \"$TMP/validate_candidate.sh\" \\\n",
    ),
}

for path, (old, new) in replacements.items():
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise SystemExit(f"expected one ShellCheck target in {path}, found {text.count(old)}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
