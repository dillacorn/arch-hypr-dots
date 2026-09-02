from pathlib import Path

path = Path('tests/test-aurguard-runtime-refresh.sh')
text = path.read_text(encoding='utf-8')
old = '''mv() {
  local destination="${@: -1}"
  if [[ "$destination" == "$META" ]]; then
    return 1
  fi
  command mv "$@"
}
'''
new = '''AWTARCHY_TEST_FAIL_META_MOVE=1
# ShellCheck cannot see that production code resolves this function indirectly.
# shellcheck disable=SC2317
mv() {
  local destination="${!#}"
  if [[ "$destination" == "$META" && $AWTARCHY_TEST_FAIL_META_MOVE == 1 ]]; then
    AWTARCHY_TEST_FAIL_META_MOVE=0
    return 1
  fi
  command mv "$@"
}
'''
if text.count(old) != 1:
    raise SystemExit(f'expected one mv shim, found {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
