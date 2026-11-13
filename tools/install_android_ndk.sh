#!/usr/bin/env bash
# Installs the NDK and the SDK platform pinned in
# apps/client/android/app/build.gradle.kts before Gradle asks for them, and
# retries a bad download.
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

platform="$(sed -n 's/^[[:space:]]*compileSdk = \([0-9][0-9]*\).*/\1/p' "$gradle" | head -n 1)"
if [ -z "$platform" ]; then
  echo "::error::no numeric compileSdk found in $gradle"
  exit 1
fi

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$sdk" ]; then
  echo "::error::ANDROID_HOME is not set"
  exit 1
fi
sdkmanager="$sdk/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$sdkmanager" ]; then
  sdkmanager="$(command -v sdkmanager || true)"
fi
if [ -z "$sdkmanager" ]; then
  echo "::error::sdkmanager not found under $sdk"
  exit 1
fi

# install <sdkmanager package> <directory it unpacks to> <file proving it is whole>
install() {
  package="$1"
  target="$2"
  marker="$3"
  if [ -f "$target/$marker" ]; then
    echo "$package is already installed"
    return 0
  fi
  for attempt in 1 2 3; do
    # A half-unpacked package or a corrupt archive from the last try would be
    # found and used again; every attempt starts clean.
    rm -rf "$target" "$sdk/.temp"
    # No pipefail on purpose: `yes` ends on SIGPIPE when sdkmanager is done.
    if yes | "$sdkmanager" --install "$package" > /dev/null \
      && [ -f "$target/$marker" ]; then
      echo "$package installed on attempt $attempt"
      return 0
    fi
    echo "::warning::$package install attempt $attempt failed"
    if [ "$attempt" -lt 3 ]; then
      sleep $((attempt * 20))
    fi
  done
  echo "::error::$package could not be installed after 3 attempts"
  exit 1
}

install "ndk;$version" "$sdk/ndk/$version" source.properties
# From API 37 the SDK names platforms with a minor version: compileSdk 37 is
# the package `platforms;android-37.0`, and `platforms;android-37` does not
# exist ("Failed to find package", the first CI run of 2.6.26). Earlier levels
# keep the bare name. Whichever directory holds an android.jar is the platform.
platform_dir=""
for name in "android-$platform" "android-$platform.0"; do
  if [ -f "$sdk/platforms/$name/android.jar" ]; then
    platform_dir="$name"
  fi
done
if [ -n "$platform_dir" ]; then
  echo "platforms;$platform_dir is already installed"
elif [ "$platform" -ge 37 ]; then
  install "platforms;android-$platform.0" "$sdk/platforms/android-$platform.0" android.jar
else
  install "platforms;android-$platform" "$sdk/platforms/android-$platform" android.jar
fi
