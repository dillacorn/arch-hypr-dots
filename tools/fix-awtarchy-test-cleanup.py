from pathlib import Path

root = Path.cwd()
test_file = root / "tests/test-awtarchy-command.sh"
text = test_file.read_text(encoding="utf-8")
old = '''cleanup() {
  if [[ -n ${TEST_USER:-} ]] && command -v sudo >/dev/null 2>&1; then
    sudo userdel "$TEST_USER" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$TMP"
}
'''
new = '''cleanup() {
  if [[ -n ${TEST_USER:-} ]] && command -v sudo >/dev/null 2>&1; then
    sudo userdel "$TEST_USER" >/dev/null 2>&1 || true
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo rm -rf -- "$TMP"
  else
    rm -rf -- "$TMP"
  fi
}
'''
if text.count(old) != 1:
    raise SystemExit("expected exactly one cleanup block")
test_file.write_text(text.replace(old, new, 1), encoding="utf-8")
Path(__file__).unlink()
