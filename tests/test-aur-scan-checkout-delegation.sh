#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
BASHRC="${ROOT}/bashrc"

bash -n "$BASHRC"

python3 - "$BASHRC" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")

legacy_call = '_aur_guard_scan_package_files "$pkg" "$pkgdir"'
aur_scan_call = '_aur_guard_scan_checkout_with_aur_scan "$pkg" "$pkgdir"'
srcinfo_call = '_aur_guard_verify_srcinfo "$pkg" "$pkgdir"'

if legacy_call in text:
    raise SystemExit(
        "fetched AUR checkout still passes through the legacy regex blocker before aur-scan"
    )

try:
    aur_scan = text.index(aur_scan_call)
    srcinfo = text.index(srcinfo_call, aur_scan)
except ValueError as exc:
    raise SystemExit(f"missing expected AUR verification boundary: {exc}") from exc

if aur_scan >= srcinfo:
    raise SystemExit("aur-scan must gate the exact checkout before makepkg metadata evaluation")

if "_aur_guard_scan_source_tree()" not in text:
    raise SystemExit("later Awtarchy source-tree inspection was removed with the checkout gate")

if '_AUR_GUARD_SOURCE_HARD_BLOCK_RE=' not in text:
    raise SystemExit("later Awtarchy source-tree hard-block rules were removed with the checkout gate")
PY

printf '%s\n' 'PASS: fetched AUR checkouts delegate static analysis to aur-scan while later Awtarchy source inspection remains intact.'
