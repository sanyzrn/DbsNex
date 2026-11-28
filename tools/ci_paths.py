#!/usr/bin/env python3
"""Select CI work from the recorded PR base; unknown diffs always run all."""
import argparse
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

FLAGS = (
    'dart', 'client', 'backend', 'desktop', 'android',
    'retrieval', 'sync', 'ai_delete', 'content', 'guards', 'format',
)

# Files the client suite reads as content instead of compiling: the root and
# bundled changelogs, the archived history `whats_new_test` compares against,
# and the guide pages `app_guide_test` parses. They are deliberately not
# "documentation" — those tests exist because the copy can be wrong — and they
# are deliberately not "client": a changelog line must not cost a Flutter
# suite, an analyze pass and two Android builds.
CONTENT = (
    r'^CHANGELOG(\.fa)?\.md$',
    r'^docs/development/CHANGELOG[^/]*\.md$',
    r'^apps/client/assets/CHANGELOG(\.fa)?\.md$',
    r'^apps/client/assets/guide/',
)

# Prose and repository metadata: no product code can depend on them. Matched
# after CONTENT, so a changelog is a content change rather than a doc one.
DOCUMENTATION = (
    r'^docs/',
    r'\.md$',
    r'^LICENSE$',
    r'^\.gitattributes$',
    r'^\.gitignore$',
    # CODEOWNERS, SECURITY.md, the issue and PR templates, dependabot.yml: a
    # workflow that reads them is not a workflow whose result changes.
    r'^\.github/(?!workflows/)',
)

# The version, stated twice on purpose — `version_test.dart` holds the two
# together. A bump of only these lines is a release-prep edit, not a code
# change, and pays for the three content tests rather than the whole matrix.
VERSION_FILES = (
    r'^apps/client/pubspec\.yaml$',
    r'^apps/client/lib/app_version\.dart$',
)
VERSION_LINE = re.compile(r'^[+-](version:|const nexAppVersion = )')

# Changes that can move an Android artifact: the build config, every pubspec
# (plugins are resolved through them), the pinned SDK, and the guard scripts
# that read the built APK. A change to, say, tools/generate_app_icons.py is
# not one of them.
ANDROID = (
    r'^apps/client/android/',
    r'(^|/)pubspec\.(yaml|lock)$',
    r'^\.fvmrc$',
    r'^tools/(install_android_ndk|check_sqlite_assets|check_store_permissions|check_16kb_alignment)',
)


def _matches(patterns, path):
    return any(re.search(pattern, path) for pattern in patterns)


def select(files, event='pull_request', active=(), version_only=False):
    if event != 'pull_request':
        # No base to diff against and the caller is a release: verify
        # everything. `format` is the one exception — it needs a PR base to be
        # meaningful (see changed-format in ci.yml).
        return dict.fromkeys(FLAGS, True) | {'module_dirs': 'all', 'format': False}
    if not files:
        return dict.fromkeys(FLAGS, True) | {'module_dirs': 'all'}
    # A workflow edit changes what every job does, so it pays for everything.
    if any(path.startswith('.github/workflows/') for path in files):
        return dict.fromkeys(FLAGS, True) | {'module_dirs': 'all'}

    content = any(_matches(CONTENT, path) for path in files)
    code = [
        path for path in files
        if not _matches(DOCUMENTATION, path) and not _matches(CONTENT, path)
    ]
    if code and version_only and all(_matches(VERSION_FILES, path) for path in code):
        # A release-prep commit: the version and its changelog, nothing else.
        code = []
    if not code:
        flags = dict.fromkeys(FLAGS, False)
        flags['content'] = content
        flags['module_dirs'] = ''
        return flags

    dart = any(_matches((r'^(apps/client|packages|spec|contracts|tools)/', r'^\.fvmrc$'), path) for path in code)
    # Specs and contracts are consumed by the client too: a changed corpus can
    # fail its conformance tests without a line of Dart moving.
    client = any(_matches((r'^(apps/client|packages|spec|contracts)/', r'^\.fvmrc$'), path) for path in code)
    backend = any(_matches((r'^apps/(backend|feedback-worker)/', r'^(spec|contracts|tools)/'), path) for path in code)
    android = any(_matches(ANDROID, path) for path in code)
    retrieval = any(_matches((r'^packages/(core|data)/', r'(^|/)pubspec\.(yaml|lock)$', r'^\.fvmrc$'), path) for path in code)
    sync = any(_matches((r'^packages/(core|data)/', r'^apps/backend/', r'^(spec|contracts|tools)/',
                         r'(^|/)pubspec\.(yaml|lock)$', r'^\.fvmrc$'), path) for path in code)
    # The deletion proof only proves that `packages/ai` still analyzes without
    # its on-device half. Every other consumer of that package is covered by
    # flutter-ai-package, so a core or client edit no longer buys a full
    # re-analysis of the graph.
    ai_delete = any(_matches((r'^packages/ai/', r'^apps/client/lib/main_ai\.dart$',
                              r'^packages/ai/pubspec\.(yaml|lock)$', r'^apps/client/pubspec\.(yaml|lock)$',
                              r'^\.fvmrc$', r'^tools/'), path) for path in code)
    # Shared module helpers/platform/UI/data can reach Soon modules too. Unknown
    # files directly under modules/ are shared, never guessed to be isolated.
    shared = any(_matches((r'^packages/',
                           r'^apps/client/(lib/(widgets|platform|l10n)/|test/(support|helpers)/|pubspec\.|dart_test\.yaml)',
                           r'^\.fvmrc$'), path) for path in code)
    shared |= any(re.search(r'^apps/client/(lib|test)/modules/[^/]+\.dart$', path) for path in code)
    changed = {m[1] for p in code if (m := re.match(r'^apps/client/(?:lib|test)/modules/([^/]+)/', p))}
    # A common directory or a newly introduced helper must not be classified as
    # an isolated module by its name. Only known module test folders qualify.
    known = {p.name for p in (ROOT / 'apps/client/test/modules').glob('*') if p.is_dir()}
    shared |= bool(changed - known)
    dirs = 'all' if shared else ' '.join(sorted(set(active) | changed))
    return {
        'dart': dart,
        'client': client,
        'backend': backend,
        'desktop': dart or any(path.startswith('apps/client/windows') or path.startswith('apps/client/ios')
                               or path.startswith('apps/client/macos') for path in code),
        'android': android,
        'retrieval': retrieval,
        'sync': sync,
        'ai_delete': ai_delete,
        'content': content,
        'guards': any(_matches((r'^(apps/client|packages|tools)/',), path) for path in code),
        'format': dart,
        'module_dirs': dirs,
    }


def _diff_names(*args):
    output = subprocess.check_output(
        ['git', 'diff', '--name-only', '--no-renames', '-z', *args],
        stderr=subprocess.DEVNULL,
    )
    return [path for path in output.decode().split('\0') if path]


def changed_files(base):
    """Paths this branch changed, not paths that merely differ from `base`.

    Neither diff is enough on its own:

      * `base...HEAD` is the branch's own work against the merge base — but a
        conflict resolved by folding `main` in with `--squash` leaves the
        merge base behind, so every file the rest of `main` touched since is
        reported as if this branch had changed it. That is the bug that made
        a docs-only pull request run the backend suite and the Android builds.
      * `base..HEAD` compares the two trees — but on a branch that is merely
        behind `main` it reports every file `main` has added since as a
        deletion, so an out-of-date docs change would run those same suites.

    Their intersection is the paths that are both part of this branch's own
    diff and different from the base: the question the flags want answered.
    The pull-request merge ref already contains the base, so in the ordinary
    case this is just the branch's changes.
    """
    if not base:
        return []
    try:
        branch = _diff_names(f'{base}...HEAD')
        differing = set(_diff_names(base, 'HEAD'))
    except subprocess.CalledProcessError:
        return []
    return [path for path in branch if path in differing]


def version_only_change(base, files):
    """True when the only code touched is the version, stated twice."""
    if not base or not files:
        return False
    if not all(_matches(DOCUMENTATION + CONTENT + VERSION_FILES, path) for path in files):
        return False
    touched = [path for path in files if _matches(VERSION_FILES, path)]
    if not touched:
        return False
    try:
        diff = subprocess.check_output(
            ['git', 'diff', '-U0', base, 'HEAD', '--', *touched],
            text=True, stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        return False
    lines = [line for line in diff.splitlines()
             if line[:1] in '+-' and not line.startswith(('+++', '---'))]
    return bool(lines) and all(VERSION_LINE.match(line) for line in lines)


def summary(selected):
    rows = ['| Scope | Selected |', '| --- | --- |']
    rows += [f'| {key} | {"yes" if value is True else "no" if value is False else value} |'
             for key, value in selected.items()]
    return '\n'.join(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--event', default=os.environ.get('CI_EVENT', 'workflow_call'))
    parser.add_argument('--base', default=os.environ.get('BASE_SHA', ''))
    args = parser.parse_args()
    rollout = (ROOT / 'apps/client/lib/modules/module_rollout.dart').read_text()
    active = re.findall(r"'([^']+)'", re.search(r'nexAvailableModuleIds\s*=\s*\{([^}]+)\}', rollout)[1])
    files = changed_files(args.base)
    selected = select(files, args.event, active, version_only_change(args.base, files))
    output = '\n'.join(f'{key}={str(value).lower() if isinstance(value, bool) else value}' for key, value in selected.items()) + '\n'
    print(output, end='')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
            stream.write(output)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
            stream.write(f'### CI selection\n\n{len(files)} changed file(s) against `{args.base or "(no base)"}`.\n\n{summary(selected)}\n')


if __name__ == '__main__':
    main()
