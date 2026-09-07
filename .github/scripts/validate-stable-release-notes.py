#!/usr/bin/env python3
"""Validate Awtarchy stable release notes before publication."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REQUIRED_HEADINGS = (
    "## Install and update",
    "## Validation",
    "## Post-release updates",
)

INSTALL_GUIDE_URL = "https://github.com/dillacorn/awtarchy/blob/main/INSTALL.md"
UPDATING_GUIDE_URL = "https://github.com/dillacorn/awtarchy/blob/main/UPDATING.md"


def fail(message: str) -> None:
    print(f"release-notes validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def section(body: str, heading: str) -> str:
    marker = f"{heading}\n"
    if body.count(marker) != 1:
        fail(f"expected exactly one {heading!r} heading")
    start = body.index(marker) + len(marker)
    next_heading = re.search(r"(?m)^## ", body[start:])
    end = start + next_heading.start() if next_heading else len(body)
    return body[start:end].strip()


def require_text(haystack: str, needle: str, context: str) -> None:
    if needle not in haystack:
        fail(f"{context} is missing required text: {needle}")


def validate(version: str, notes_path: Path, previous_path: Path | None) -> None:
    if not re.fullmatch(r"v\d+\.\d+\.\d+", version):
        fail(f"invalid stable version {version!r}; expected vX.Y.Z")

    body = notes_path.read_text(encoding="utf-8")
    expected_title = f"# Awtarchy {version} Quickshell"
    if not body.startswith(expected_title + "\n"):
        fail(f"release must start with {expected_title!r}")

    title_end = len(expected_title) + 1
    install_update_pos = body.find("## Install and update")
    if install_update_pos < 0 or not body[title_end:install_update_pos].strip():
        fail("release overview is missing before Install and update")

    positions: list[int] = []
    for heading in REQUIRED_HEADINGS:
        marker = f"{heading}\n"
        if body.count(marker) != 1:
            fail(f"expected exactly one {heading!r} heading")
        positions.append(body.index(marker))
    if positions != sorted(positions):
        fail("required stable release sections are out of order")

    install_update = section(body, "## Install and update")
    require_text(install_update, INSTALL_GUIDE_URL, "Install and update")
    require_text(install_update, UPDATING_GUIDE_URL, "Install and update")

    validation = section(body, "## Validation")
    if not validation:
        fail("Validation section is empty")

    post_release = section(body, "## Post-release updates")
    expected_placeholder = (
        f"_Placeholder for possible tested post-release patches to {version}._"
    )
    require_text(post_release, expected_placeholder, "Post-release updates")

    if previous_path is not None:
        previous = previous_path.read_text(encoding="utf-8")
        for heading in REQUIRED_HEADINGS:
            if heading in previous and heading not in body:
                fail(f"protected section from previous stable release disappeared: {heading}")

    print(f"PASS: stable release notes satisfy the {version} release contract")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--notes", required=True, type=Path)
    parser.add_argument("--previous", type=Path)
    args = parser.parse_args()
    validate(args.version, args.notes, args.previous)


if __name__ == "__main__":
    main()
