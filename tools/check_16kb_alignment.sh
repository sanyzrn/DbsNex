#!/usr/bin/env bash
# Fails when a 64-bit native library in an APK or App Bundle is not aligned
# for 16 KB memory pages (REL-06).
#
# Android 15 devices may run with 16 KB pages, and Play requires apps that
# target API 35 to support them. A library whose ELF LOAD segments are
# aligned to 4 KB does not load on such a device at all: the app crashes at
# its first use of that library. The usual culprit is a prebuilt `.so`
# shipped inside a plugin, which nothing else in the build checks.
#
# Usage: tools/check_16kb_alignment.sh [--warn] <file.apk|file.aab>...
#
# With --warn a misaligned library is reported as a warning and the script
# succeeds: the release goes out, and the report is there to read (REL-05).
# The check was taken out of the release once at the owner's request, for
# blocking it; it is back as a report, which is what the review asked for.
set -euo pipefail

level=error
if [ "${1:-}" = "--warn" ]; then
  level=warning
  shift
fi

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <file.apk|file.aab>..." >&2
  exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

checked=0
failed=0
for archive in "$@"; do
  if [ ! -f "$archive" ]; then
    echo "::error::$archive does not exist"
    exit 1
  fi
  dest="$work/$(basename "$archive")"
  mkdir -p "$dest"
  # APKs keep libraries under lib/<abi>/, bundles under base/lib/<abi>/.
  # Only the 64-bit ABIs: 32-bit processes are not run with 16 KB pages.
  unzip -q -o "$archive" 'lib/arm64-v8a/*.so' 'lib/x86_64/*.so' \
    'base/lib/arm64-v8a/*.so' 'base/lib/x86_64/*.so' -d "$dest" 2>/dev/null || true
  while IFS= read -r -d '' so; do
    checked=$((checked + 1))
    # The last column of every LOAD row is its alignment, in hex.
    smallest=$(readelf -lW "$so" | awk '$1 == "LOAD" { print $NF }' |
      while read -r align; do printf '%d\n' "$align"; done | sort -n | head -1)
    name="${so#"$dest"/}"
    if [ -z "$smallest" ] || [ "$smallest" -lt 16384 ]; then
      echo "::$level::$(basename "$archive"): $name is aligned to ${smallest:-?} bytes, not 16 KB"
      failed=$((failed + 1))
    else
      echo "ok  $(basename "$archive"): $name ($smallest)"
    fi
  done < <(find "$dest" -name '*.so' -print0)
done

if [ "$checked" -eq 0 ]; then
  echo "::error::no 64-bit native libraries found — is this the right file?"
  exit 1
fi
if [ "$failed" -gt 0 ]; then
  echo "$failed of $checked native libraries are not 16 KB aligned."
  [ "$level" = warning ] && exit 0
  exit 1
fi
echo "All $checked 64-bit native libraries are 16 KB aligned."
