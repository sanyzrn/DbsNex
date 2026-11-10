#!/usr/bin/env python3
"""Check tracked Dart files changed from an immutable base without editing them."""
import os
import subprocess
import sys

base = os.environ.get('BASE_SHA') or 'HEAD^'
files = subprocess.check_output(['git', 'diff', '--name-only', '-z', f'{base}...HEAD']).decode().split('\0')
paths = [p for p in files if p.endswith('.dart') and os.path.isfile(p) and not p.endswith(('.g.dart', '.freezed.dart')) and not p.startswith('apps/client/lib/l10n/app_localizations')]
if paths:
    result = subprocess.run(['dart', 'format', '--output=write', *paths])
    diff = subprocess.run(['git', 'diff', '--', *paths], capture_output=True, text=True)
    print(diff.stdout, flush=True)
    sys.exit(1 if diff.stdout else result.returncode)
print('No changed, maintained Dart files to format.')
