#!/usr/bin/env python3
"""Validate the checked-out release source and extract its bilingual notes."""

import argparse
import re
import sys
from pathlib import Path


def section(root: Path, name: str, tag: str, required: bool = True) -> str:
    path = root / name
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    heading = f"## {tag}"
    positions = [i for i, line in enumerate(lines) if line == heading]
    if not positions and not required:
        return ""
    if len(positions) != 1:
        raise ValueError(
            f"{name} must contain exactly one '{heading}' section in this checkout. "
            "Merge the release PR first, then start a NEW run from the updated main "
            "(or select the intended source branch for a draft rehearsal). "
            "Re-running an old run keeps its original commit."
        )
    start = positions[0] + 1
    end = next(
        (i for i in range(start, len(lines)) if lines[i].startswith("## ")),
        len(lines),
    )
    text = "\n".join(lines[start:end]).strip()
    if not re.sub(r"<!--.*?-->", "", text, flags=re.S).strip():
        raise ValueError(f"{name}'s '{heading}' section is empty.")
    return text + "\n"


def release_notes(root: Path, tag: str) -> tuple[str, list[str]]:
    tag = tag if tag.startswith("v") else f"v{tag}"
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", tag):
        raise ValueError(f"Invalid release tag: {tag!r}")
    english = section(root, "CHANGELOG.md", tag)
    persian = section(root, "CHANGELOG.fa.md", tag, required=False)
    warnings = []
    if not persian:
        warnings.append(f"CHANGELOG.fa.md has no '## {tag}' section; using English.")

    # The release still stamps the exact tag (including any pre-release suffix),
    # but it must not relabel another version's source as this release.
    base = tag[1:].split("-", 1)[0]
    for name, pattern in (
        ("apps/client/pubspec.yaml", r"(?m)^version:\s*([^\s]+)"),
        ("apps/client/lib/app_version.dart", r"const\s+nexAppVersion\s*=\s*['\"]([^'\"]+)"),
    ):
        match = re.search(pattern, (root / name).read_text(encoding="utf-8"))
        value = match[1].strip("'\"") if match else ""
        if value.split("+", 1)[0].split("-", 1)[0] != base:
            raise ValueError(
                f"{name} names {value!r}, but the requested release is {tag}. "
                "Select the commit containing this release before building."
            )

    for name in ("CHANGELOG.md", "CHANGELOG.fa.md"):
        source = root / name
        if not source.exists() and name == "CHANGELOG.fa.md":
            continue
        bundled = root / "apps/client/assets" / name
        if not bundled.exists() or source.read_bytes() != bundled.read_bytes():
            raise ValueError(f"{bundled.relative_to(root)} must match {name} exactly.")

    return english + ("\n<!-- nex:fa -->\n" + persian if persian else ""), warnings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        notes, warnings = release_notes(args.root, args.tag)
        if args.output:
            args.output.write_text(notes, encoding="utf-8")
    except (ValueError, OSError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    for warning in warnings:
        print(f"::warning::{warning}")
    print(f"Validated release source and notes for {args.tag}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
