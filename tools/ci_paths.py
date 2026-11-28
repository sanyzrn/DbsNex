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

# These are the files read by the three content tests. Other bundled files,
# including guide images and privacy text, are Android build inputs.
CONTENT = (
    r'^(?:apps/client/assets/|docs/development/)?CHANGELOG(?:\.fa)?\.md\Z',
    r'^apps/client/assets/guide/(?:en|fa)\.md\Z',
)

DOCUMENTATION = (
    r'^docs/.+\.md\Z',
    r'^docs/(?:brand|images)/.+\.(?:png|svg|webp|jpe?g)\Z',
    r'^docs/banner\.example\.json\Z',
    r'^(?:README\.md|CLAUDE\.md|LICENSE|\.gitignore|addons/README\.md)\Z',
    r'^(?:apps/(?:client|backend|feedback-worker)|packages/(?:ai|core|data|ui))/README\.md\Z',
    r'^\.github/(?:CODEOWNERS|SECURITY\.md|dependabot\.yml|pull_request_template\.md)\Z',
    r'^\.github/(?:ISSUE_TEMPLATE|PULL_REQUEST_TEMPLATE)/[^/]+\.(?:md|ya?ml)\Z',
)

VERSION = rb'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)'
VERSION_FILES = {
    'apps/client/pubspec.yaml': re.compile(rb'^version: (' + VERSION + rb')(?=\r?$)', re.M),
    'apps/client/lib/app_version.dart': re.compile(
        rb"^const nexAppVersion = '(" + VERSION + rb")';(?=\r?$)", re.M,
    ),
}

ANDROID_TOOLS = (
    r'^tools/(?:install_android_ndk\.sh|check_sqlite_assets\.py|check_store_permissions\.sh'
    r'|check_16kb_alignment\.sh|daily_nudge_native_test\.py)\Z',
)
ANDROID = ANDROID_TOOLS + (
    r'^apps/client/(?:android|app_icons|assets|lib|third_party|hook)/',
    r'^apps/client/l10n\.yaml\Z',
    r'^packages/(?:ai|core|data|ui)/(?:lib|hook|android|ios|linux|macos|windows)/',
    r'(^|/)pubspec\.(yaml|lock)\Z',
    r'^\.fvmrc\Z',
)

# Match build and test inputs by their role. A new sibling directory or
# configuration file has no established scope, so it takes the full path.
# The pipeline itself includes the scripts which decide which jobs can skip.
KNOWN_CODE = ANDROID_TOOLS + (
    r'^apps/client/(?:android|app_icons|assets|lib|third_party|hook|ios|windows|macos|linux|test)/',
    r'^apps/client/(?:\.gitignore|\.metadata|analysis_options\.yaml|dart_test\.yaml|l10n\.yaml|pubspec\.(?:yaml|lock))\Z',
    r'^apps/backend/(?:src/|\.(?:dockerignore|env\.example)\Z|Dockerfile\Z|eslint\.config\.js\Z'
    r'|package(?:-lock)?\.json\Z|tsconfig(?:\.build)?\.json\Z)',
    r'^apps/feedback-worker/(?:src/|\.dev\.vars\.example\Z|eslint\.config\.js\Z'
    r'|package(?:-lock)?\.json\Z|tsconfig\.json\Z|wrangler\.toml\Z)',
    r'^packages/(?:ai|core|data|ui)/(?:lib|test|benchmark|tool|hook|android|ios|linux|macos|windows)/',
    r'^packages/(?:ai|core|data|ui)/(?:analysis_options\.yaml|dart_test\.yaml|pubspec\.(?:yaml|lock))\Z',
    r'^(?:spec|contracts)/[^/]+\.json\Z',
    r'^tools/(?:check_changed_format\.py|check_sqlite_assets_test\.py|check_widget_layouts(?:_test)?\.py'
    r'|generate_(?:app_icons|brand_assets)\.py|release_notes(?:_test)?\.py|release_pipeline_test\.py'
    r'|require_tests(?:_test)?\.py|stress_repeat\.sh|verify_apk_updates(?:_test)?\.py)\Z',
    r'^tools/theme_atelier/(?:emit_dart|palette_checker|palettes)\.py\Z',
    r'^\.fvmrc\Z',
)

MODULE_ID = re.compile(r'[a-z][a-z0-9_]*')


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
    content = False
    code = []
    for path in files:
        if _matches(CONTENT, path):
            content = True
        elif _matches(KNOWN_CODE, path):
            code.append(path)
        elif not _matches(DOCUMENTATION, path):
            return dict.fromkeys(FLAGS, True) | {'module_dirs': 'all'}

    if code and version_only and set(code) == VERSION_FILES.keys():
        code = []
        content = True
    if not code:
        return dict.fromkeys(FLAGS, False) | {'content': content, 'module_dirs': ''}

    dart = any(_matches((r'^(apps/client|packages|spec|contracts|tools)/', r'^\.fvmrc$'), path) for path in code)
    # Specs and contracts are consumed by the client too: a changed corpus can
    # fail its conformance tests without a line of Dart moving.
    client = any(_matches((r'^(apps/client|packages|spec|contracts)/', r'^\.fvmrc$'), path) for path in code)
    backend = any(_matches((r'^apps/(backend|feedback-worker)/', r'^(spec|contracts|tools)/'), path) for path in code)
    android = any(_matches(ANDROID, path) for path in code)
    retrieval = any(_matches((r'^packages/(core|data)/', r'(^|/)pubspec\.(yaml|lock)$', r'^\.fvmrc$'), path) for path in code)
    sync = any(_matches((r'^packages/(core|data)/', r'^apps/backend/', r'^(spec|contracts|tools)/',
                         r'(^|/)pubspec\.(yaml|lock)$', r'^\.fvmrc$'), path) for path in code)
    # Guards check for direct runtime imports on ordinary client changes.
    # The removal and re-analysis are needed for changes to the AI package,
    # its entry point or the dependency resolution.
    ai_delete = any(_matches((r'^packages/ai/', r'^apps/client/lib/main_ai\.dart$',
                              r'^apps/client/pubspec\.(yaml|lock)$',
                              r'^\.fvmrc$', r'^tools/'), path) for path in code)
    # Shared code, assets and test configuration can affect Soon modules.
    # Only a known module directory can narrow that part of the suite.
    shared = active is None or any(_matches((
        r'^(packages|spec|contracts)/', r'^\.fvmrc$',
        r'^apps/client/(?:assets/|lib/(?:widgets|platform|l10n)/|pubspec\.|dart_test\.yaml$)',
        r'^apps/client/test/(?!modules/)(?:[^/]+/|flutter_test_config\.dart$)',
        r'^apps/client/(?:lib|test)/modules/[^/]+$',
    ), path) for path in code)
    changed = {m[1] for p in code if (m := re.match(r'^apps/client/(?:lib|test)/modules/([^/]+)/', p))}
    known = {p.name for p in (ROOT / 'apps/client/test/modules').glob('*')
             if MODULE_ID.fullmatch(p.name) and p.is_dir()}
    dirs = 'all' if shared or changed - known else ' '.join(sorted(set(active) | changed))
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
    return [path for path in os.fsdecode(output).split('\0') if path]


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
    """Recognize a paired version bump from regular Git blobs."""
    if not base or not VERSION_FILES.keys() <= set(files):
        return False
    if not all(path in VERSION_FILES or _matches(DOCUMENTATION + CONTENT, path) for path in files):
        return False
    try:
        # Diff the branch's own changes. A main-only dependency edit should
        # not obscure a version bump when inspecting an unmerged branch.
        entries = subprocess.check_output(
            ['git', 'diff', '--raw', '--no-abbrev', '--no-renames', '-z',
             f'{base}...HEAD', '--', *VERSION_FILES],
            stderr=subprocess.DEVNULL,
        ).split(b'\0')[:-1]
        versions = {}
        for metadata, filename in zip(entries[::2], entries[1::2], strict=True):
            before_mode, after_mode, before_sha, after_sha, status = metadata.split()
            if (before_mode, after_mode, status) != (b':100644', b'100644', b'M'):
                return False
            path = filename.decode()
            pattern = VERSION_FILES[path]
            before = subprocess.check_output(['git', 'cat-file', 'blob', before_sha])
            after = subprocess.check_output(['git', 'cat-file', 'blob', after_sha])
            old = list(pattern.finditer(before))
            new = list(pattern.finditer(after))
            if len(old) != 1 or len(new) != 1:
                return False
            old, new = old[0], new[0]
            if old[1] == new[1] or (
                before[:old.start(1)], before[old.end(1):]
            ) != (after[:new.start(1)], after[new.end(1):]):
                return False
            versions[path] = old[1], new[1]
    except (subprocess.CalledProcessError, ValueError):
        return False
    return versions.keys() == VERSION_FILES.keys() and len(set(versions.values())) == 1


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
    rollout = ROOT / 'apps/client/lib/modules/module_rollout.dart'
    active = None
    if rollout.is_file():
        match = re.search(r'nexAvailableModuleIds\s*=\s*\{([^}]+)\}', rollout.read_text())
        if match and re.fullmatch(r"\s*(?:'[a-z][a-z0-9_]*'\s*,\s*)+", match[1]):
            active = re.findall(r"'([^']+)'", match[1])
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
