#!/usr/bin/env python3
"""Verify bundled SQLite for every Flutter ABI in a real Android APK/AAB."""
import re
import sys
import zipfile

MACHINES = {"armeabi-v7a": 40, "arm64-v8a": 183, "x86": 3, "x86_64": 62}


def check(path):
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        flutter = [name for name in names if re.fullmatch(r"(?:base/)?lib/[^/]+/libflutter\.so", name)]
        if not flutter:
            raise ValueError(f"{path}: no Flutter ABI found")
        for engine in sorted(flutter):
            prefix, abi, _ = engine.rsplit("/", 2)
            sqlite = f"{prefix}/{abi}/libsqlite3.so"
            if sqlite not in names:
                raise ValueError(f"{path}: bundled SQLite missing for {abi}")
            with archive.open(sqlite) as library:
                header = library.read(20)
            if len(header) < 20 or header[:4] != b"\x7fELF" or header[5] not in (1, 2):
                raise ValueError(f"{path}: invalid SQLite ELF for {abi}")
            machine = int.from_bytes(header[18:20], "little" if header[5] == 1 else "big")
            if machine != MACHINES.get(abi):
                raise ValueError(f"{path}: SQLite architecture mismatch for {abi}")
            print(f"{path}: bundled SQLite verified for {abi}")


def main():
    if len(sys.argv) < 2:
        print("usage: check_sqlite_assets.py APK_OR_AAB...", file=sys.stderr)
        return 2
    try:
        for path in sys.argv[1:]:
            check(path)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
