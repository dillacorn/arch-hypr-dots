#!/usr/bin/env python3
"""Collect the exact live and branch state involved in Quickshell flyouts.

This collector is intentionally read-only with respect to live configuration.
It writes one diagnostic directory and a matching tar.gz under Awtarchy state.
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
from datetime import datetime
from typing import Any


REPOSITORY_PATHS = (
    "config/hypr/scripts/quickshell_runtime_rules.sh",
    "config/hypr/scripts/quickshell_flyout_prepare.sh",
    "config/quickshell/awtarchy/FlyoutManager.qml",
    "config/quickshell/awtarchy/shell.qml",
    "config/quickshell/awtarchy/Launcher.qml",
    "config/quickshell/awtarchy/QuickSettings.qml",
    "config/quickshell/awtarchy/ClipboardMenu.qml",
    "config/quickshell/awtarchy/Notifications.qml",
    "config/quickshell/awtarchy/NetworkMenu.qml",
    "config/quickshell/awtarchy/BluetoothMenu.qml",
)

ROLLBACK_FILENAMES = (
    "quickshell_runtime_rules.sh",
    "quickshell_flyout_prepare.sh",
)

SYSTEM_COMMANDS = (
    ("hyprland-version.txt", ("hyprctl", "version")),
    ("hyprland-monitors.json", ("hyprctl", "-j", "monitors")),
    ("hyprland-cursor-position.json", ("hyprctl", "-j", "cursorpos")),
    ("hyprland-active-window.json", ("hyprctl", "-j", "activewindow")),
    ("hyprland-clients.json", ("hyprctl", "-j", "clients")),
    ("hyprland-layers.json", ("hyprctl", "-j", "layers")),
    ("hyprland-config-errors.txt", ("hyprctl", "configerrors")),
    ("cursor-no-warps.json", ("hyprctl", "-j", "getoption", "cursor:no_warps")),
    (
        "cursor-persistent-warps.json",
        ("hyprctl", "-j", "getoption", "cursor:persistent_warps"),
    ),
    (
        "cursor-workspace-warps.json",
        ("hyprctl", "-j", "getoption", "cursor:warp_on_change_workspace"),
    ),
    (
        "misc-focus-on-activate.json",
        ("hyprctl", "-j", "getoption", "misc:focus_on_activate"),
    ),
    (
        "input-follow-mouse.json",
        ("hyprctl", "-j", "getoption", "input:follow_mouse"),
    ),
    ("package-versions.txt", ("pacman", "-Q", "hyprland", "quickshell")),
    ("quickshell-version.txt", ("qs", "--version")),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect live Quickshell flyout files and compare them with a Git ref."
    )
    parser.add_argument(
        "--repo",
        type=Path,
        default=Path.home() / "awtarchy",
        help="Awtarchy Git checkout used only for git object access",
    )
    parser.add_argument(
        "--ref",
        default="origin/quickshell-conversion-testing",
        help="Git ref to use as the branch source of truth",
    )
    parser.add_argument(
        "--expected-sha",
        default="",
        help="Require --ref to resolve to this exact commit",
    )
    parser.add_argument(
        "--config-home",
        type=Path,
        default=Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")),
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--state-root",
        type=Path,
        default=Path.home() / ".local/state/awtarchy",
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--skip-system-commands",
        action="store_true",
        help=argparse.SUPPRESS,
    )
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


def git_output(repo: Path, *arguments: str) -> str:
    return run(("git", "-C", str(repo), *arguments)).stdout


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def live_path(config_home: Path, repository_path: str) -> Path:
    relative = Path(repository_path)
    if relative.parts[:3] == ("config", "hypr", "scripts"):
        return config_home / "hypr/scripts" / relative.name
    if relative.parts[:3] == ("config", "quickshell", "awtarchy"):
        return config_home / "quickshell/awtarchy" / relative.name
    raise ValueError(f"unsupported repository path: {repository_path}")


def write_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def copy_if_present(source: Path, destination: Path) -> dict[str, Any]:
    record: dict[str, Any] = {
        "source": str(source),
        "present": source.is_file(),
    }
    if not source.is_file():
        return record

    data = source.read_bytes()
    write_bytes(destination, data)
    record.update(
        {
            "size": len(data),
            "sha256": sha256(data),
            "mode": oct(source.stat().st_mode & 0o777),
        }
    )
    return record


def unified_diff(
    live_data: bytes | None,
    branch_data: bytes,
    repository_path: str,
) -> str:
    if live_data is None:
        return f"MISSING LIVE FILE: {repository_path}\n"

    live_text = live_data.decode("utf-8", errors="replace").splitlines(keepends=True)
    branch_text = branch_data.decode("utf-8", errors="replace").splitlines(keepends=True)
    return "".join(
        difflib.unified_diff(
            branch_text,
            live_text,
            fromfile=f"branch/{repository_path}",
            tofile=f"live/{repository_path}",
        )
    )


def collect_system_state(output_dir: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    command_dir = output_dir / "system"
    command_dir.mkdir(parents=True, exist_ok=True)

    for filename, command in SYSTEM_COMMANDS:
        destination = command_dir / filename
        if shutil.which(command[0]) is None:
            output = f"UNAVAILABLE: {command[0]}\n"
            returncode = 127
        else:
            result = run(command, check=False)
            output = result.stdout
            returncode = result.returncode

        destination.write_text(output, encoding="utf-8")
        records.append(
            {
                "command": list(command),
                "file": str(destination.relative_to(output_dir)),
                "returncode": returncode,
            }
        )

    return records


def collect_rollbacks(state_root: Path, output_dir: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    rollback_diffs: list[str] = []
    candidates: list[Path] = []
    exact = state_root / "quickshell-warp-guard-v3-20260811-232214"
    if exact.is_dir():
        candidates.append(exact)

    for candidate in sorted(state_root.glob("quickshell-warp-guard-v3-*")):
        if candidate.is_dir() and candidate not in candidates:
            candidates.append(candidate)

    for candidate in candidates:
        for filename in ROLLBACK_FILENAMES:
            source = candidate / filename
            destination = output_dir / "rollback" / candidate.name / filename
            record = copy_if_present(source, destination)
            record["backup"] = candidate.name
            record["filename"] = filename
            records.append(record)

            live_source = output_dir / "live/config/hypr/scripts" / filename
            if source.is_file() and live_source.is_file():
                rollback_text = source.read_text(
                    encoding="utf-8", errors="replace"
                ).splitlines(keepends=True)
                live_text = live_source.read_text(
                    encoding="utf-8", errors="replace"
                ).splitlines(keepends=True)
                diff = "".join(
                    difflib.unified_diff(
                        rollback_text,
                        live_text,
                        fromfile=f"rollback/{candidate.name}/{filename}",
                        tofile=f"live/config/hypr/scripts/{filename}",
                    )
                )
                if diff:
                    rollback_diffs.append(diff)

    (output_dir / "live-vs-rollback.diff").write_text(
        "\n".join(rollback_diffs), encoding="utf-8"
    )

    return records


def main() -> int:
    args = parse_args()
    repo = args.repo.expanduser().resolve()
    config_home = args.config_home.expanduser().resolve()
    state_root = args.state_root.expanduser().resolve()

    if not (repo / ".git").exists():
        raise SystemExit(f"ERROR: not a Git checkout: {repo}")

    ref_sha = git_output(repo, "rev-parse", "--verify", f"{args.ref}^{{commit}}").strip()
    if args.expected_sha and ref_sha != args.expected_sha:
        raise SystemExit(
            f"ERROR: {args.ref} is {ref_sha}, expected {args.expected_sha}"
        )

    subject = git_output(repo, "show", "-s", "--format=%s", ref_sha).strip()
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    state_root.mkdir(parents=True, exist_ok=True)
    output_dir = state_root / f"quickshell-flyout-state-{stamp}"
    output_dir.mkdir(mode=0o700)

    manifest: dict[str, Any] = {
        "created": datetime.now().astimezone().isoformat(),
        "repository": str(repo),
        "ref": args.ref,
        "ref_sha": ref_sha,
        "ref_subject": subject,
        "config_home": str(config_home),
        "files": [],
        "rollbacks": [],
        "commands": [],
    }
    repository_dir = output_dir / "repository"
    repository_dir.mkdir(parents=True, exist_ok=True)
    (repository_dir / "status.txt").write_text(
        git_output(repo, "status", "--short", "--branch"), encoding="utf-8"
    )
    combined_diff: list[str] = []

    for repository_path in REPOSITORY_PATHS:
        branch_data = git_output(
            repo, "show", f"{ref_sha}:{repository_path}"
        ).encode("utf-8")
        branch_destination = output_dir / "branch" / repository_path
        write_bytes(branch_destination, branch_data)

        source = live_path(config_home, repository_path)
        live_destination = output_dir / "live" / repository_path
        live_record = copy_if_present(source, live_destination)
        live_data = source.read_bytes() if source.is_file() else None

        manifest["files"].append(
            {
                "repository_path": repository_path,
                "branch_sha256": sha256(branch_data),
                "live": live_record,
            }
        )
        diff = unified_diff(live_data, branch_data, repository_path)
        if diff:
            combined_diff.append(diff)

    (output_dir / "live-vs-branch.diff").write_text(
        "\n".join(combined_diff), encoding="utf-8"
    )

    manifest["rollbacks"] = collect_rollbacks(state_root, output_dir)
    if not args.skip_system_commands:
        manifest["commands"] = collect_system_state(output_dir)

    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    archive = output_dir.with_suffix(".tar.gz")
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(output_dir, arcname=output_dir.name)
    archive.chmod(0o600)

    missing = [
        record["repository_path"]
        for record in manifest["files"]
        if not record["live"]["present"]
    ]

    print(f"PASS: collected flyout state against {ref_sha}")
    print(f"Archive: {archive}")
    print("Live configuration was not modified.")
    if missing:
        print("WARNING: missing live files:")
        for path in missing:
            print(f"  {path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
