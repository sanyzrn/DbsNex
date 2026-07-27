#!/usr/bin/env python3
"""
apply_nex_fixes.py

Applies the 42-issue "nex" repository audit fix-set to a local checkout of
the DbsNex repo. Reads nex_fixes_data.json (must sit next to this script)
and writes / deletes files under the target repo root.

Usage:
    python3 apply_nex_fixes.py /path/to/DbsNex --dry-run
    python3 apply_nex_fixes.py /path/to/DbsNex
    python3 apply_nex_fixes.py            # uses current directory as repo root

What it does:
  1. Verifies the target looks like the right repo (looks for apps/backend
     and apps/client — warns, doesn't block, if they're missing).
  2. For every "new" or "modified" file in the fix set: backs up any
     existing file to .nex-fix-backups/<timestamp>/<path>, then writes
     the new content (creating directories as needed).
  3. For every entry in "deletions": removes the file if present (also
     backed up first).
  4. Prints a summary: files written, files deleted, and the list of
     issues that still need a manual step (these are NOT code changes
     and this script cannot do them for you).
  5. Never touches git — you review/commit the diff yourself.

Safe by default: run with --dry-run first to see exactly what would happen
without touching anything.
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path


def load_data(script_dir: Path) -> dict:
    data_path = script_dir / "nex_fixes_data.json"
    if not data_path.exists():
        sys.exit(
            f"ERROR: {data_path} not found.\n"
            "Keep nex_fixes_data.json in the same folder as this script."
        )
    with data_path.open("r", encoding="utf-8") as f:
        return json.load(f)


def sanity_check_repo(root: Path) -> None:
    markers = ["apps/backend", "apps/client"]
    missing = [m for m in markers if not (root / m).exists()]
    if missing:
        print(
            f"WARNING: {root} does not contain: {', '.join(missing)}.\n"
            "This doesn't look like the DbsNex repo root — double-check the path.\n"
        )
        answer = input("Continue anyway? [y/N] ").strip().lower()
        if answer != "y":
            sys.exit("Aborted.")


def backup_path(root: Path, rel_path: str, backup_root: Path) -> Path:
    return backup_root / rel_path


def write_files(data: dict, root: Path, backup_root: Path, dry_run: bool) -> tuple[int, int]:
    written = 0
    skipped_identical = 0
    for group in data["fileGroups"]:
        for file_entry in group["files"]:
            rel_path = file_entry["path"]
            content = file_entry["content"]
            target = root / rel_path

            if target.exists():
                existing = target.read_text(encoding="utf-8", errors="ignore")
                if existing == content:
                    skipped_identical += 1
                    continue

            action = "WRITE (new)" if not target.exists() else "OVERWRITE"
            resolves = ", ".join(file_entry.get("resolves", []))
            print(f"  [{action:11}] {rel_path}   ({resolves})")

            if dry_run:
                written += 1
                continue

            if target.exists():
                bpath = backup_path(root, rel_path, backup_root)
                bpath.parent.mkdir(parents=True, exist_ok=True)
                bpath.write_bytes(target.read_bytes())

            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
            written += 1

    return written, skipped_identical


def delete_files(data: dict, root: Path, backup_root: Path, dry_run: bool) -> int:
    deleted = 0
    for entry in data.get("deletions", []):
        rel_path = entry["path"]
        target = root / rel_path
        if not target.exists():
            continue
        print(f"  [DELETE     ] {rel_path}   ({entry.get('reason', '')})")
        if dry_run:
            deleted += 1
            continue
        bpath = backup_path(root, rel_path, backup_root)
        bpath.parent.mkdir(parents=True, exist_ok=True)
        bpath.write_bytes(target.read_bytes())
        target.unlink()
        deleted += 1
    return deleted


def print_manual_steps(data: dict) -> None:
    steps = data.get("manualSteps", [])
    if not steps:
        return
    print("\n" + "=" * 78)
    print(f"MANUAL STEPS STILL NEEDED ({len(steps)}) — this script did NOT do these:")
    print("=" * 78)
    for s in steps:
        print(f"\n[{s['id']}]")
        print(f"  {s['action']}")


def print_status_summary(data: dict) -> None:
    rows = data.get("statusRows", [])
    counts: dict[str, int] = {}
    for r in rows:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    print("\nIssue status breakdown:")
    for status, n in counts.items():
        print(f"  {status:22} {n}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Apply nex repo audit fixes.")
    parser.add_argument(
        "repo_root",
        nargs="?",
        default=".",
        help="Path to the DbsNex repo root (default: current directory)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would happen without writing or deleting anything.",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Skip the confirmation prompt before writing.",
    )
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    root = Path(args.repo_root).resolve()

    if not root.exists():
        sys.exit(f"ERROR: repo root {root} does not exist.")

    data = load_data(script_dir)
    sanity_check_repo(root)

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_root = root / ".nex-fix-backups" / timestamp

    total_files = sum(len(g["files"]) for g in data["fileGroups"])
    total_deletions = len(data.get("deletions", []))

    print(f"Repo root : {root}")
    print(f"Data file : {script_dir / 'nex_fixes_data.json'}")
    print(f"Files in fix set : {total_files} (new + modified)")
    print(f"Deletions in fix set : {total_deletions}")
    print(f"Mode : {'DRY RUN (nothing will be written)' if args.dry_run else 'APPLY'}")
    print()

    if not args.dry_run and not args.yes:
        print(f"Existing files that get overwritten will be backed up to:\n  {backup_root}\n")
        answer = input("Proceed and write files now? [y/N] ").strip().lower()
        if answer != "y":
            sys.exit("Aborted. Re-run with --dry-run to preview safely.")

    print("\nApplying file changes:")
    written, skipped = write_files(data, root, backup_root, args.dry_run)

    print("\nApplying deletions:")
    deleted = delete_files(data, root, backup_root, args.dry_run)

    print(f"\n{'Would write' if args.dry_run else 'Wrote'}: {written} file(s)")
    print(f"Already identical, skipped: {skipped} file(s)")
    print(f"{'Would delete' if args.dry_run else 'Deleted'}: {deleted} file(s)")
    if not args.dry_run and (written or deleted):
        print(f"Backups of anything overwritten/deleted: {backup_root}")

    print_status_summary(data)
    print_manual_steps(data)

    print("\nNext steps:")
    print("  1. git diff  — review every change before committing.")
    print("  2. Run the backend typecheck/tests and flutter analyze locally.")
    print("  3. Work through the manual steps listed above.")


if __name__ == "__main__":
    main()
