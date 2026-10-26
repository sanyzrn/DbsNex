#!/usr/bin/env bash
# Fails when a store build (--dart-define=NEX_STORE_BUILD=true) still asks for
# the installer permission (2.3.5). Cafe Bazaar and Myket refuse an app that
# updates itself from elsewhere, and they review the file they are given.
#
#   tools/check_store_permissions.sh path/to/app.apk
set -euo pipefail

apk="${1:?usage: check_store_permissions.sh <apk>}"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
aapt2="$(ls -d "$sdk"/build-tools/*/ 2>/dev/null | sort -V | tail -1)aapt2"
if [ ! -x "$aapt2" ]; then
  echo "::error::aapt2 not found under $sdk/build-tools" >&2
  exit 1
fi

permissions="$("$aapt2" dump permissions "$apk")"
echo "$permissions"
if grep -q 'REQUEST_INSTALL_PACKAGES' <<<"$permissions"; then
  echo "::error::$apk is a store build but still asks for REQUEST_INSTALL_PACKAGES" >&2
  exit 1
fi
# The rest of the app's permissions are still there: the overlay removed one
# line, not the manifest.
grep -q 'android.permission.CAMERA' <<<"$permissions"
grep -q 'android.permission.POST_NOTIFICATIONS' <<<"$permissions"
echo "Store build permissions OK."
