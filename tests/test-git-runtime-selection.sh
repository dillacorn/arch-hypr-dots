#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
LAUNCHER="${ROOT}/local/bin/awtarchy"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

bash -n "$LAUNCHER"

python3 - "$LAUNCHER" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")


def function_body(name: str) -> str:
    marker = f"{name}() {{\n"
    start = text.find(marker)
    if start < 0:
        raise SystemExit(f"FAIL: launcher is missing {name}()")
    body_start = start + len(marker)
    end = text.find("\n}\n", body_start)
    if end < 0:
        raise SystemExit(f"FAIL: launcher function {name}() is unterminated")
    return text[body_start:end]

runtime_body = function_body("run_git_revision_runtime")
for required in (
    'archive_topdir "$archive"',
    '[[ $top == "${REPO_NAME}-${revision}" ]]',
    'testing_runtime="${repo_dir}/local/share/awtarchy/awtarchy-runtime.sh"',
    '[[ -f $testing_runtime && ! -L $testing_runtime ]]',
    'bash -n "$testing_runtime"',
    'bash "$testing_runtime" "$@"',
):
    if required not in runtime_body:
        raise SystemExit(f"FAIL: exact Git runtime loader is missing: {required}")

operation_body = function_body("run_git_operation")
expected = 'run_git_revision_runtime "$branch" "$revision" "${runtime_args[@]}"'
if expected not in operation_body:
    raise SystemExit("FAIL: awtarchy git does not execute the exact selected commit runtime")
if 'run_runtime "${runtime_args[@]}"' in operation_body:
    raise SystemExit("FAIL: awtarchy git still executes the installed main runtime")

stable_body = function_body("run_runtime")
if 'bash "$RUNTIME" "$@"' not in stable_body:
    raise SystemExit("FAIL: stable runtime dispatch changed unexpectedly")
PY

printf 'PASS: Git testing executes the exact selected runtime\n'
