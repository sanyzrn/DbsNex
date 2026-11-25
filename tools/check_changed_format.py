#!/usr/bin/env python3
"""Check tracked Dart files changed from an immutable base without editing them."""
import os
import subprocess
import sys

base = os.environ.get('BASE_SHA') or 'HEAD^'
files = subprocess.check_output(['git', 'diff', '--name-only', '-z', f'{base}...HEAD']).decode().split('\0')
paths = [p for p in files if p.endswith('.dart') and os.path.isfile(p) and not p.endswith(('.g.dart', '.freezed.dart')) and not p.startswith('apps/client/lib/l10n/app_localizations')]
if paths:
    result = subprocess.run(['dart', 'format', '--output=none', '--set-exit-if-changed', *paths])
    if result.returncode:
        # Keep the same gate, but expose the exact formatter output for files
        # that fail so the correction never needs to be guessed from a path.
        for path in paths:
            check = subprocess.run(
                ['dart', 'format', '--output=show', '--set-exit-if-changed', path],
                capture_output=True, text=True,
            )
            if check.returncode:
                print(f'\n--- Expected Dart formatting: {path} ---', flush=True)
                print(check.stdout, end='', flush=True)
                print(check.stderr, end='', file=sys.stderr, flush=True)
    sys.exit(result.returncode)
print('No changed, maintained Dart files to format.')
