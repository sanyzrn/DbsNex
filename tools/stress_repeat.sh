#!/usr/bin/env bash
# Runs a test command N times and stops at the first failure, saying which run
# failed. Used by .github/workflows/stress.yml (W6.4); handy locally too:
#
#   tools/stress_repeat.sh 20 dart test test/write_contention_test.dart
#
# A failure here is a race with a reproduction. It is never fixed by
# retrying: see docs/06-development.md § Flaky tests.
set -uo pipefail

runs="${1:?usage: stress_repeat.sh RUNS COMMAND...}"
shift
if ! [[ "$runs" =~ ^[0-9]+$ ]] || [ "$runs" -lt 1 ]; then
  echo "RUNS must be a positive number, got '$runs'" >&2
  exit 2
fi

for ((i = 1; i <= runs; i++)); do
  echo "::group::run $i of $runs: $*"
  if ! "$@"; then
    echo "::endgroup::"
    echo "::error::failed on run $i of $runs: $*"
    exit 1
  fi
  echo "::endgroup::"
done
echo "all $runs runs passed: $*"
