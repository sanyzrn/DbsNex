#!/usr/bin/env python3
"""Select CI work from the recorded PR base; unknown diffs always run all."""
import argparse
import os
import re
import subprocess
from pathlib import Path

FLAGS = ('dart', 'backend', 'desktop', 'android', 'modules', 'retrieval', 'sync', 'ai_delete')


def select(files, event='pull_request', active=()):
    if event != 'pull_request' or not files or any(p.startswith('.github/') for p in files):
        return dict.fromkeys(FLAGS, True) | {'module_dirs': 'all'}
    def match(pattern):
        return any(re.search(pattern, p) for p in files)
    dart = match(r'^(apps/client|packages|spec|contracts|tools)/|^\.fvmrc$|^CHANGELOG(\.fa)?\.md$')
    # Shared module helpers/platform/UI/data can reach Soon modules too. Unknown
    # files directly under modules/ are shared, never guessed to be isolated.
    shared = match(r'^packages/|^apps/client/(lib/(widgets|platform|l10n)/|test/(support|helpers)/|pubspec\.|dart_test\.yaml)|^\.fvmrc$')
    shared |= match(r'^apps/client/(lib|test)/modules/[^/]+\.dart$')
    changed = {m[1] for p in files if (m := re.match(r'^apps/client/(?:lib|test)/modules/([^/]+)/', p))}
    # A common directory or a newly introduced helper must not be classified as
    # an isolated module by its name. Only known module test folders qualify.
    known = {p.name for p in Path('apps/client/test/modules').glob('*') if p.is_dir()}
    shared |= bool(changed - known)
    dirs = 'all' if shared else ' '.join(sorted(set(active) | changed))
    return {
        'dart': dart,
        'backend': match(r'^apps/(backend|feedback-worker)/|^(spec|contracts|tools)/'),
        'desktop': dart or match(r'^apps/client/(windows|ios|macos)/'),
        'android': match(r'^apps/client/android/|(^|/)pubspec\.(yaml|lock)$|^\.fvmrc$|^tools/'),
        'modules': dart,
        'module_dirs': dirs,
        'retrieval': match(r'^packages/(core|data)/|(^|/)pubspec\.(yaml|lock)$|^\.fvmrc$|^tools/'),
        'sync': match(r'^packages/(core|data)/|^apps/backend/|^(spec|contracts|tools)/|(^|/)pubspec\.(yaml|lock)$|^\.fvmrc$'),
        # Changes to consumers can break the deletion analysis too; boundary
        # checks alone cannot prove the remaining source still compiles.
        'ai_delete': match(r'^packages/|^apps/client/lib/main(_ai)?\.dart$|(^|/)pubspec\.(yaml|lock)$|^\.fvmrc$|^tools/'),
    }


def changed_files(base):
    if not base:
        return []
    try:
        return [p for p in subprocess.check_output(['git', 'diff', '--name-only', '-z', f'{base}...HEAD']).decode().split('\0') if p]
    except subprocess.CalledProcessError:
        return []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--event', default=os.environ.get('CI_EVENT', 'workflow_call'))
    parser.add_argument('--base', default=os.environ.get('BASE_SHA', ''))
    args = parser.parse_args()
    rollout = Path('apps/client/lib/modules/module_rollout.dart').read_text()
    active = re.findall(r"'([^']+)'", re.search(r'nexAvailableModuleIds\s*=\s*\{([^}]+)\}', rollout)[1])
    selected = select(changed_files(args.base), args.event, active)
    output = '\n'.join(f'{key}={str(value).lower() if isinstance(value, bool) else value}' for key, value in selected.items()) + '\n'
    print(output, end='')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
            stream.write(output)


if __name__ == '__main__':
    main()
