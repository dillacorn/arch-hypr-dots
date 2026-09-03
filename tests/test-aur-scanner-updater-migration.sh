#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"

bash -n "$RUNTIME"

python3 - "$RUNTIME" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")


def function_body(name: str) -> str:
    match = re.search(rf"(?ms)^{re.escape(name)}\(\)\s*\{{\n(.*?)^\}}\n", text)
    if not match:
        raise SystemExit(f"missing updater migration function: {name}()")
    return match.group(1)


migration_target = function_body("target_uses_direct_aur_scanner")
if ".bashrc" not in migration_target or "aur-scan" not in migration_target:
    raise SystemExit("updater does not identify the direct aur-scanner bashrc target")
if not any(name in migration_target for name in ("aurguard", "aurverify", "aurinstall")):
    raise SystemExit("direct-scanner target detection does not distinguish the old AurGuard shell")

ensure = function_body("ensure_update_aur_scanner")
for required in (
    "/usr/bin/aur-scan",
    "--version",
    "/usr/bin/yay",
    "--pgpfetch",
    "aur-scanner",
):
    if required not in ensure:
        raise SystemExit(f"updater scanner bootstrap is missing: {required}")
if "rebuild_aur_helper" in ensure or "aur.archlinux.org/yay.git" in ensure:
    raise SystemExit("updater scanner bootstrap grew a yay repair engine")

build_target = function_body("build_target_home")
if 'copy_target "${repo_dir}/bashrc" "${target_home}/.bashrc"' not in build_target:
    raise SystemExit("updater target no longer stages the release bashrc")

backup = function_body("make_persistent_backup")
if '${dest}.backup' not in backup or 'cp -a -- "$dest" "$backup"' not in backup:
    raise SystemExit("updater no longer preserves replaced managed shell files as sibling backups")

apply = function_body("apply_plan")
if 'rel" == ".config/hypr/hyprland.lua"' not in apply:
    raise SystemExit("expected preserve-mode special case is missing")
if 'rel" == ".bashrc"' in apply:
    raise SystemExit("bashrc was incorrectly added to preserve-mode skip behavior")
if apply.count('install_live_file "$rel" "$target_file" "$local_file" 1') < 3:
    raise SystemExit("modified managed files do not retain persistent backup behavior")

# An identical live file is omitted from the plan, so a second successful update
# does not create another migration-specific backup or rewrite.
if 'if ni is not None and li == ni:' not in text or 'continue' not in text[text.index('if ni is not None and li == ni:'):][:120]:
    raise SystemExit("updater no longer treats an already-current managed file as idempotent")

main = function_body("main")
review_boundary = 'if (( REVIEW_ONLY == 1 )); then'
migration_call = 'target_uses_direct_aur_scanner "$target_home"'
ensure_call = 'ensure_update_aur_scanner'
apply_call = 'apply_plan "$plan_file"'
for required in (review_boundary, migration_call, ensure_call, apply_call):
    if required not in main:
        raise SystemExit(f"updater main is missing migration boundary: {required}")

review_pos = main.index(review_boundary)
migration_pos = main.index(migration_call, review_pos)
ensure_pos = main.index(ensure_call, migration_pos)
apply_pos = main.index(apply_call, ensure_pos)
if not (review_pos < migration_pos <= ensure_pos < apply_pos):
    raise SystemExit("aur-scanner migration prerequisite is not enforced before live managed-file replacement")

if re.search(r"pacman\s+-R[^\n]*(?:yay|paru)", text):
    raise SystemExit("updater migration removes yay/paru instead of retaining them")
PY

printf '%s\n' 'PASS: updater safely gates the AurGuard-to-aur-scanner bashrc migration and retains normal backup/idempotence behavior.'
