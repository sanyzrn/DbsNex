#!/usr/bin/env bash
# Installs the NDK pinned in apps/client/android/app/build.gradle.kts before
# Gradle asks for it, and retries a bad download.
#
# Left to Gradle, a missing NDK is installed in the middle of the build and
# tried once. On a runner that download came back truncated — "Archive is not
# a ZIP archive" — and the debug build failed ten minutes in, before anything
# had been compiled (2.1.6, PR #364). Installing it first turns a bad download
# into another attempt instead of a red build.
#
# Usage: bash tools/install_android_ndk.sh   (needs ANDROID_HOME)
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
gradle="$root/apps/client/android/app/build.gradle.kts"
version="$(sed -n 's/^[[:space:]]*ndkVersion = "\([^"]*\)".*/\1/p' "$gradle" | head -n 1)"
if [ -z "$version" ]; then
  echo "::error::no ndkVersion found in $gradle"
  exit 1
fi

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$sdk" ]; then
  echo "::error::ANDROID_HOME is not set"
  exit 1
fi
target="$sdk/ndk/$version"
if [ -f "$target/source.properties" ]; then
  echo "NDK $version is already installed"
  exit 0
fi

sdkmanager="$sdk/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$sdkmanager" ]; then
  sdkmanager="$(command -v sdkmanager || true)"
fi
if [ -z "$sdkmanager" ]; then
  echo "::error::sdkmanager not found under $sdk"
  exit 1
fi

for attempt in 1 2 3; do
  # A half-unpacked NDK or a corrupt archive from the last try would be found
  # and used again; every attempt starts clean.
  rm -rf "$target" "$sdk/.temp"
  # No pipefail on purpose: `yes` ends on SIGPIPE when sdkmanager is done.
  if yes | "$sdkmanager" --install "ndk;$version" > /dev/null \
    && [ -f "$target/source.properties" ]; then
    echo "NDK $version installed on attempt $attempt"
    exit 0
  fi
  echo "::warning::NDK $version install attempt $attempt failed"
  if [ "$attempt" -lt 3 ]; then
    sleep $((attempt * 20))
  fi
done
echo "::error::NDK $version could not be installed after 3 attempts"
exit 1
