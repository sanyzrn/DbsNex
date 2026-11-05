#!/usr/bin/env python3
"""Run a dedicated integration suite and reject empty or skipped-only success."""
import argparse
import json
import re
import subprocess
import sys


def ran_tests(output, kind):
    if kind == 'tap':
        counts = {key: int(value) for key, value in re.findall(r'^# (tests|pass|fail|cancelled|skipped) (\d+)\s*$', output, re.M)}
        return counts.get('pass', 0) > 0 and counts.get('fail') == 0 and counts.get('cancelled') == 0
    done = False
    passed = 0
    for line in output.splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get('type') == 'done':
            done = event.get('success') is True
        if event.get('type') == 'testDone' and not event.get('hidden') and not event.get('skipped') and event.get('result') == 'success':
            passed += 1
    return done and passed > 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--format', choices=['tap', 'dart'], required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(result.stdout, end='')
    if result.returncode:
        return result.returncode
    if not ran_tests(result.stdout, args.format):
        print('::error::The dedicated suite did not report any executed, passing tests.')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
