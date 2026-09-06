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
    match = re.search(
        rf"(?ms)^{re.escape(name)}\(\)\s*\{{\n(.*?)^\}}\n",
        text,
    )
    if not match:
        raise SystemExit(f"missing installer function: {name}()")
    return match.group(1)


for required in (
    "ensure_yay",
    "ensure_aur_scanner",
    "install_aur_with_scanner",
    "install_aur_repo_apps_stage",
    "install_obs_pipewire_audio_capture_package",
    "aur_install",
):
    function_body(required)

if "run_aur_guard_as_target()" in text:
    raise SystemExit("installer still embeds the Awtarchy AurGuard execution bridge")
if "run_aur_guard_as_target aurinstall" in text:
    raise SystemExit("installer still delegates an AUR package write to aurinstall")

ensure_yay = function_body("ensure_yay")
if "aurinstall" in ensure_yay or "AUR Guard" in ensure_yay:
    raise SystemExit("yay bootstrap still depends on AurGuard")

ensure_scanner = function_body("ensure_aur_scanner")
if "aur-scanner" not in ensure_scanner or "/usr/bin/aur-scan" not in ensure_scanner:
    raise SystemExit("installer does not bootstrap and verify the stable aur-scanner CLI")
if "--pgpfetch" not in ensure_scanner:
    raise SystemExit("fresh aur-scanner bootstrap does not request upstream validpgpkeys import through yay")

scanner_install = function_body("install_aur_with_scanner")
if "/usr/bin/aur-scan" not in scanner_install or " install " not in scanner_install:
    raise SystemExit("installer AUR install helper does not delegate to aur-scan install")
if "yay -S" in scanner_install or "paru -S" in scanner_install:
    raise SystemExit("normal installer AUR writes still use an AUR helper")

stage = function_body("install_aur_repo_apps_stage")
for required in ("ensure_yay", "ensure_aur_scanner", "install_aur_with_scanner"):
    if required not in stage:
        raise SystemExit(f"installer AUR stage is missing {required}")
if "AUR Guard" in stage or "aurinstall" in stage:
    raise SystemExit("installer AUR stage still advertises or invokes AurGuard")
if 'if ! install_aur_with_scanner "$pkg"; then' not in stage:
    raise SystemExit("selected AUR package failures are not isolated before continuing")
if 'install_aur_with_scanner tlpui' in stage:
    raise SystemExit("official tlpui package is still routed through aur-scanner")

obs = function_body("install_obs_pipewire_audio_capture_package")
if 'install_aur_with_scanner "$pkg"' not in obs:
    raise SystemExit("OBS AUR package attempt still bypasses aur-scanner")
if "AUR Guard" in obs or "aurinstall" in obs:
    raise SystemExit("OBS installer fallback still depends on AurGuard")

gpu_aur = function_body("aur_install")
if 'install_aur_with_scanner "$@"' not in gpu_aur:
    raise SystemExit("GPU legacy AUR installs do not share the aur-scan install helper")
if re.search(r"\b(?:yay|paru)\s+-S\b", gpu_aur):
    raise SystemExit("GPU legacy AUR install helper still writes packages through yay/paru")

for retained in ("build_aur_picker_arrays()", "aur_search_results()", "AUR_SELECTED=()"):
    if retained not in text:
        raise SystemExit(f"installer AUR picker/search behavior was removed: {retained}")

installed_check = function_body("aur_selected_package_installed")
for variant in ("hyprmoncfg", "hyprmoncfg-bin", "hyprmoncfg-git"):
    if variant not in installed_check:
        raise SystemExit(f"installer AUR equivalence check does not recognize {variant}")

catalog = re.search(r"(?ms)^declare -a PACKAGES_AUR=\(\n(.*?)^\)", text)
if not catalog:
    raise SystemExit("missing PACKAGES_AUR catalog")
if "hyprmoncfg-bin" not in catalog.group(1).split():
    raise SystemExit("hyprmoncfg-bin is missing from the shared installer/reconciler AUR catalog")
PY

printf '%s\n' 'PASS: installer delegates AUR package writes to upstream aur-scan install while retaining yay and the existing AUR picker.'
