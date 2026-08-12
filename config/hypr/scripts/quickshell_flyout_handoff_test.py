#!/usr/bin/env python3
"""Install or roll back the mapped-window flyout handoff test safely."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from datetime import datetime


BRANCH = "quickshell-conversion-testing"
BACKUP_ROOT = Path.home() / ".local/state/awtarchy"
LOG_PATH = Path.home() / ".cache/awtarchy/quickshell.log"

REPOSITORY_PATHS = (
    "config/hypr/scripts/quickshell_runtime_rules.sh",
    "config/quickshell/awtarchy/Launcher.qml",
    "config/quickshell/awtarchy/QuickSettings.qml",
    "config/quickshell/awtarchy/ClipboardMenu.qml",
    "config/quickshell/awtarchy/Notifications.qml",
    "config/quickshell/awtarchy/NetworkMenu.qml",
    "config/quickshell/awtarchy/BluetoothMenu.qml",
)
TEST_SCRIPT_REPOSITORY_PATH = "config/hypr/scripts/quickshell_flyout_handoff_test.py"

# Exact live state collected on 2026-08-11 before this test. Refuse to replace
# anything else so new or unrelated user changes are never silently lost.
COLLECTED_LIVE_SHA256 = {
    "config/hypr/scripts/quickshell_runtime_rules.sh":
        "9f80fc5645aed92b1ad210bb9231f1de922793b9d604816f5ca342aa36ba1793",
    "config/quickshell/awtarchy/Launcher.qml":
        "42c1d06ae7e67a01b8b2d41054edaf227654652823cc754a776e5b3454c49588",
    "config/quickshell/awtarchy/QuickSettings.qml":
        "1c3f50a45cb6e6c8aa29e3dc13a86beac4203ba710e8206c3ae845da8ab2e8bb",
    "config/quickshell/awtarchy/ClipboardMenu.qml":
        "d4b1d814b3a77ecb5e1abf7b551a30af9cf4ab1afc37351bd29001528ab73b41",
    "config/quickshell/awtarchy/Notifications.qml":
        "a50273e02ea23e579a9c0300ede7b606fc78e16a2325c6e0bd56c14fafebea96",
    "config/quickshell/awtarchy/NetworkMenu.qml":
        "74bda3c2714a721a5062aa11901cadd558bb75ee6976432e7745671534cb9f2c",
    "config/quickshell/awtarchy/BluetoothMenu.qml":
        "fbdb1201fad87c12703a328e61e263683ddb61978b91a7a19b44997a0e59ced9",
}

LOG_ERROR = re.compile(
    r"TypeError|ReferenceError|Cannot assign|configuration failed|"
    r"failed to load|failed to create|QQmlApplicationEngine failed",
    re.IGNORECASE,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Safely install or roll back the flyout handoff test."
    )
    subparsers = parser.add_subparsers(dest="action", required=True)

    install = subparsers.add_parser("install")
    install.add_argument("--expected-sha", required=True)

    rollback = subparsers.add_parser("rollback")
    rollback.add_argument("backup", type=Path)

    return parser.parse_args()


def run(
    command: tuple[str, ...] | list[str],
    *,
    cwd: Path | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def repository_root() -> Path:
    root = Path(__file__).resolve().parents[3]
    if not (root / ".git").exists():
        raise RuntimeError(f"not running from an Awtarchy Git checkout: {root}")
    return root


def live_path(config_home: Path, repository_path: str) -> Path:
    relative = Path(repository_path)
    if relative.parts[:3] == ("config", "hypr", "scripts"):
        return config_home / "hypr/scripts" / relative.name
    if relative.parts[:3] == ("config", "quickshell", "awtarchy"):
        return config_home / "quickshell/awtarchy" / relative.name
    raise ValueError(f"unsupported repository path: {repository_path}")


def verify_checkout(repo: Path, expected_sha: str) -> str:
    branch = run(("git", "rev-parse", "--abbrev-ref", "HEAD"), cwd=repo).stdout.strip()
    if branch != BRANCH:
        raise RuntimeError(f"checkout is on {branch}, expected {BRANCH}")

    head = run(("git", "rev-parse", "HEAD"), cwd=repo).stdout.strip()
    if head != expected_sha:
        raise RuntimeError(f"checkout is {head}, expected {expected_sha}")

    dirty = run(
        (
            "git", "status", "--porcelain=v1", "--",
            *REPOSITORY_PATHS, TEST_SCRIPT_REPOSITORY_PATH,
        ),
        cwd=repo,
    ).stdout.strip()
    if dirty:
        raise RuntimeError(f"test source files have local changes:\n{dirty}")

    runtime = repo / REPOSITORY_PATHS[0]
    syntax = run(("bash", "-n", str(runtime)), check=False)
    if syntax.returncode != 0:
        raise RuntimeError(f"runtime source failed bash -n:\n{syntax.stdout}")

    return head


def cursor_state() -> tuple[bool, bool, int]:
    values: list[bool | int] = []
    for option, field in (
        ("cursor:no_warps", "bool"),
        ("cursor:persistent_warps", "bool"),
        ("cursor:warp_on_change_workspace", "int"),
    ):
        result = run(("hyprctl", "-j", "getoption", option))
        data = json.loads(result.stdout)
        values.append(data[field])
    return bool(values[0]), bool(values[1]), int(values[2])


def copy_atomic(source: Path, destination: Path) -> None:
    temporary = destination.parent / f".{destination.name}.handoff-{os.getpid()}"
    try:
        shutil.copy2(source, temporary)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def log_offset() -> int:
    return LOG_PATH.stat().st_size if LOG_PATH.is_file() else 0


def new_log_text(offset: int) -> str:
    if not LOG_PATH.is_file():
        return ""
    with LOG_PATH.open("rb") as stream:
        if LOG_PATH.stat().st_size >= offset:
            stream.seek(offset)
        return stream.read().decode("utf-8", errors="replace")


def apply_and_validate(config_home: Path, expected_cursor: tuple[bool, bool, int]) -> None:
    runtime = live_path(config_home, REPOSITORY_PATHS[0])
    manager = config_home / "hypr/scripts/quickshell.sh"
    if not manager.is_file():
        raise RuntimeError(f"missing live Quickshell manager: {manager}")

    syntax = run(("bash", "-n", str(runtime)), check=False)
    if syntax.returncode != 0:
        raise RuntimeError(f"live runtime failed bash -n:\n{syntax.stdout}")

    applied = run(("bash", str(runtime)), check=False)
    if applied.returncode != 0:
        raise RuntimeError(
            f"runtime-rule apply failed with exit {applied.returncode}:\n"
            f"{applied.stdout}"
        )

    offset = log_offset()
    restarted = run((str(manager), "restart"), check=False)
    if restarted.returncode != 0:
        raise RuntimeError(
            f"Quickshell restart failed with exit {restarted.returncode}:\n"
            f"{restarted.stdout}"
        )

    status = run((str(manager), "status"), check=False)
    if status.returncode != 0 or status.stdout.strip() != "running":
        raise RuntimeError(f"Quickshell status check failed:\n{status.stdout}")

    ping = run(
        ("qs", "-c", "awtarchy", "ipc", "call", "control", "ping"),
        check=False,
    )
    if ping.returncode != 0:
        raise RuntimeError(f"Quickshell IPC ping failed:\n{ping.stdout}")

    config_errors = run(("hyprctl", "configerrors"), check=False)
    if config_errors.returncode != 0 or config_errors.stdout.strip():
        raise RuntimeError(f"Hyprland config errors:\n{config_errors.stdout}")

    errors = [line for line in new_log_text(offset).splitlines() if LOG_ERROR.search(line)]
    if errors:
        raise RuntimeError("new Quickshell log errors:\n" + "\n".join(errors[-40:]))

    current_cursor = cursor_state()
    if current_cursor != expected_cursor:
        raise RuntimeError(
            f"cursor settings changed from {expected_cursor} to {current_cursor}"
        )


def restore_backup(
    backup_dir: Path,
    manifest: dict[str, object],
    config_home: Path,
    *,
    enforce_installed_hash: bool,
) -> None:
    records = manifest.get("files")
    if not isinstance(records, list):
        raise RuntimeError("invalid backup manifest")

    for raw_record in records:
        if not isinstance(raw_record, dict):
            raise RuntimeError("invalid backup file record")
        repository_path = str(raw_record["repository_path"])
        target = live_path(config_home, repository_path)
        backup = backup_dir / repository_path
        if not backup.is_file():
            raise RuntimeError(f"backup file is missing: {backup}")
        if enforce_installed_hash and sha256(target) != raw_record["installed_sha256"]:
            raise RuntimeError(f"live file changed after install; refusing rollback: {target}")

    for raw_record in records:
        repository_path = str(raw_record["repository_path"])
        copy_atomic(backup_dir / repository_path, live_path(config_home, repository_path))


def install(expected_sha: str) -> int:
    repo = repository_root()
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")).resolve()
    head = verify_checkout(repo, expected_sha)
    expected_cursor = cursor_state()
    if expected_cursor != (False, False, 0):
        raise RuntimeError(f"unexpected cursor settings before install: {expected_cursor}")

    source_hashes: dict[str, str] = {}
    for repository_path in REPOSITORY_PATHS:
        source = repo / repository_path
        target = live_path(config_home, repository_path)
        if not source.is_file():
            raise RuntimeError(f"missing test source: {source}")
        if not target.is_file():
            raise RuntimeError(f"missing live file: {target}")

        source_hash = sha256(source)
        live_hash = sha256(target)
        allowed = {COLLECTED_LIVE_SHA256[repository_path], source_hash}
        if live_hash not in allowed:
            raise RuntimeError(
                f"live file differs from both collected and test versions: {target}\n"
                f"live sha256: {live_hash}"
            )
        source_hashes[repository_path] = source_hash

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_dir = BACKUP_ROOT / f"quickshell-flyout-handoff-{stamp}"
    backup_dir.mkdir(parents=True, mode=0o700, exist_ok=False)

    records: list[dict[str, str]] = []
    for repository_path in REPOSITORY_PATHS:
        target = live_path(config_home, repository_path)
        backup = backup_dir / repository_path
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, backup)
        records.append(
            {
                "repository_path": repository_path,
                "before_sha256": sha256(target),
                "installed_sha256": source_hashes[repository_path],
            }
        )

    manifest: dict[str, object] = {
        "created": datetime.now().astimezone().isoformat(),
        "branch": BRANCH,
        "commit": head,
        "files": records,
    }
    (backup_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    try:
        for repository_path in REPOSITORY_PATHS:
            copy_atomic(repo / repository_path, live_path(config_home, repository_path))
        apply_and_validate(config_home, expected_cursor)
    except BaseException:
        restore_backup(
            backup_dir,
            manifest,
            config_home,
            enforce_installed_hash=False,
        )
        runtime = live_path(config_home, REPOSITORY_PATHS[0])
        manager = config_home / "hypr/scripts/quickshell.sh"
        run(("bash", str(runtime)), check=False)
        run((str(manager), "restart"), check=False)
        print(f"ROLLBACK: restored live files from {backup_dir}")
        raise

    print(f"PASS: installed mapped-window flyout handoff test from {head}")
    print(f"Backup: {backup_dir}")
    print("The failed v1/v2/v3 cursor-restoration timers are not active.")
    print("cursor:no_warps remains false.")
    return 0


def rollback(backup: Path) -> int:
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")).resolve()
    backup_dir = backup.expanduser().resolve()
    backup_root = BACKUP_ROOT.resolve()
    if backup_dir.parent != backup_root or not backup_dir.name.startswith(
        "quickshell-flyout-handoff-"
    ):
        raise RuntimeError(f"not an Awtarchy flyout handoff backup: {backup_dir}")

    manifest_path = backup_dir / "manifest.json"
    if not manifest_path.is_file():
        raise RuntimeError(f"missing backup manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    expected_cursor = cursor_state()
    restore_backup(
        backup_dir,
        manifest,
        config_home,
        enforce_installed_hash=True,
    )
    apply_and_validate(config_home, expected_cursor)
    print(f"PASS: restored live files from {backup_dir}")
    return 0


def main() -> int:
    args = parse_args()
    try:
        if args.action == "install":
            return install(args.expected_sha)
        return rollback(args.backup)
    except (OSError, RuntimeError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        raise SystemExit(f"ERROR: {error}") from error


if __name__ == "__main__":
    raise SystemExit(main())
