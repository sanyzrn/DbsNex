import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from ci_paths import FLAGS, changed_files, select, version_only_change

ACTIVE = ('cycle', 'pause', 'habits', 'occasions', 'words')


class PathsTest(unittest.TestCase):
    def test_resolved_empty_git_diff_runs_all(self):
        self.assertEqual(changed_files('HEAD'), [])
        self.assertTrue(all(select(changed_files('HEAD'))[key] for key in FLAGS))

    def test_contracts_run_both_languages_and_sync(self):
        for path in ('spec/note-types.json', 'spec/merge-conformance.json', 'contracts/sync.json'):
            value = select([path], active=ACTIVE)
            self.assertTrue(all(value[k] for k in ('dart', 'backend', 'sync')))

    def test_workflow_call_workflows_and_empty_diff_run_everything(self):
        for paths, event in (([], 'pull_request'), (['.github/workflows/ci.yml'], 'pull_request')):
            value = select(paths, event, ACTIVE)
            self.assertTrue(all(value[k] for k in FLAGS), paths)
            self.assertEqual(value['module_dirs'], 'all')
        # A release has no base to diff, so the changed-files formatter has
        # nothing meaningful to check and is left to pull requests.
        release = select(['README.md'], 'workflow_call', ACTIVE)
        self.assertTrue(all(release[k] for k in FLAGS if k != 'format'))
        self.assertFalse(release['format'])

    def test_screen_only_does_not_seed_large_libraries(self):
        value = select(['apps/client/lib/screens/home.dart'], active=ACTIVE)
        self.assertTrue(value['dart'])
        for key in ('retrieval', 'sync', 'ai_delete', 'backend'):
            self.assertFalse(value[key], key)
        self.assertEqual(set(value['module_dirs'].split()), set(ACTIVE))

    def test_soon_module_and_shared_dependencies_are_kept(self):
        value = select(['apps/client/lib/modules/parking/view.dart'], active=ACTIVE)
        self.assertIn('parking', value['module_dirs'].split())
        for path in ('apps/client/lib/modules/shared.dart', 'apps/client/lib/platform/store.dart',
                     'apps/client/test/support/helper.dart', 'packages/data/lib/a.dart',
                     'apps/client/lib/modules/common/widget.dart'):
            self.assertEqual(select([path], active=ACTIVE)['module_dirs'], 'all', path)

    def test_heavy_dependencies_and_deleted_paths(self):
        for path in ('packages/data/lib/a.dart', 'packages/core/lib/a.dart', '.fvmrc'):
            value = select([path], active=ACTIVE)
            self.assertTrue(all(value[k] for k in ('retrieval', 'sync')), path)
        self.assertTrue(select(['apps/backend/src/routes/auth.ts'])['sync'])
        self.assertTrue(select(['apps/client/pubspec.lock'])['android'])
        self.assertFalse(select(['README.md'])['dart'])

    def test_native_asset_guard_runs_real_android_builds(self):
        value = select(['tools/check_sqlite_assets.py'], active=ACTIVE)
        self.assertTrue(value['android'])
        self.assertTrue(value['dart'])

    def test_documentation_alone_runs_nothing(self):
        # The reported waste: prose, a PR template or CODEOWNERS used to buy a
        # full matrix, and every Android build.
        for path in ('README.md', 'docs/06-development.md', 'docs/images/graph.png',
                     'LICENSE', '.github/pull_request_template.md', '.github/CODEOWNERS',
                     '.github/dependabot.yml', 'packages/data/README.md'):
            value = select([path], active=ACTIVE)
            self.assertFalse(any(value[k] for k in FLAGS), path)
            self.assertFalse(value['content'], path)

    def test_changelog_and_guide_run_only_the_content_checks(self):
        for path in ('CHANGELOG.md', 'CHANGELOG.fa.md', 'docs/development/CHANGELOG.md',
                     'apps/client/assets/CHANGELOG.fa.md', 'apps/client/assets/guide/en.md'):
            value = select([path], active=ACTIVE)
            self.assertTrue(value['content'], path)
            # `client` is what the full Flutter suite hangs on; content must
            # not set it, or the changelog is back to a nine-minute run.
            self.assertFalse(any(value[k] for k in FLAGS if k != 'content'), path)

    def test_a_version_bump_without_a_changelog_still_runs_the_version_tests(self):
        # `version_test` is the only thing holding the two statements of the
        # version together. Selecting nothing for the bump left them free to
        # disagree until a release.
        files = ['apps/client/pubspec.yaml', 'apps/client/lib/app_version.dart']
        value = select(files, active=ACTIVE, version_only=True)
        self.assertEqual([k for k in FLAGS if value[k]], ['content'])

    def test_an_unrecognised_path_runs_everything(self):
        # A second app, a script outside tools/, a root config: nothing here can
        # be proved harmless, so nothing may be skipped for it.
        for path in ('apps/desktop/linux/main.cc', 'scripts/deploy.sh',
                     'analysis_options.yaml', 'melos.yaml', 'apps/store/README.md',
                     'apps/client/build_tools/compile.dart', 'apps/client/config.yaml',
                     'apps/backend/.npmrc', 'apps/feedback-worker/new-runtime/config.toml',
                     'packages/new_package/README.md', 'packages/data/build.yaml',
                     'tools/check_store_permissions_extra.sh', 'tools/theme_atelier/new_tool.py',
                     'docs/scripts/generate.py', 'addons/new_tool.dart', 'spec/new/tool.py',
                     '.github/scripts/prepare.sh', '.gitattributes', 'Makefile', 'README.md\n'):
            value = select([path], active=ACTIVE)
            self.assertTrue(all(value[k] for k in FLAGS), path)
            self.assertEqual(value['module_dirs'], 'all', path)

    def test_a_custom_action_is_code_not_prose(self):
        # .github/actions/* is executed by a workflow; the rest of .github is
        # templates and metadata that cannot change a result.
        value = select(['.github/actions/setup/action.yml'], active=ACTIVE)
        self.assertTrue(all(value[k] for k in FLAGS))

    def test_release_prep_commit_is_content_not_code(self):
        files = ['CHANGELOG.md', 'CHANGELOG.fa.md', 'apps/client/pubspec.yaml',
                 'apps/client/lib/app_version.dart']
        value = select(files, active=ACTIVE, version_only=True)
        self.assertEqual([k for k in FLAGS if value[k]], ['content'])
        # A non-version edit to the same two files is a real code change.
        value = select(files, active=ACTIVE, version_only=False)
        self.assertTrue(value['dart'] and value['android'] and value['client'])

    def test_ai_deletion_proof_follows_the_ai_package(self):
        self.assertTrue(select(['packages/ai/lib/cloud.dart'])['ai_delete'])
        self.assertTrue(select(['apps/client/lib/main_ai.dart'])['ai_delete'])
        self.assertFalse(select(['packages/core/lib/sync/a.dart'])['ai_delete'])
        self.assertFalse(select(['packages/ui/lib/a.dart'])['ai_delete'])

    def test_android_build_follows_production_inputs(self):
        for path in (
            'apps/client/android/app/build.gradle.kts',
            'apps/client/pubspec.lock',
            'apps/client/lib/main.dart',
            'apps/client/lib/main_ai.dart',
            'apps/client/lib/screens/home.dart',
            'apps/client/lib/l10n/app_fa.arb',
            'apps/client/l10n.yaml',
            'apps/client/assets/fonts/Vazirmatn.ttf',
            'apps/client/assets/guide/images/home.webp',
            'apps/client/assets/privacy/fa.md',
            'apps/client/assets/new-guide.md',
            'apps/client/third_party/sqlite/sqlite3.c',
            'packages/core/lib/note.dart',
            'packages/data/lib/data.dart',
            'packages/ui/lib/widget.dart',
            'packages/ai/lib/adapter.dart',
            'packages/data/hook/build.dart',
            'packages/ui/android/src/main/kotlin/Plugin.kt',
            'packages/ui/pubspec.yaml',
            'tools/install_android_ndk.sh',
            'tools/daily_nudge_native_test.py',
        ):
            with self.subTest(path=path):
                value = select([path], active=ACTIVE)
                self.assertTrue(value['android'], path)
                self.assertTrue(value['client'] or path.startswith('tools/'), path)

    def test_test_only_and_content_changes_skip_android(self):
        for path in (
            'apps/client/test/widget_test.dart',
            'apps/client/test/fixtures/fixture.md',
            'apps/client/dart_test.yaml',
            'packages/core/test/note_test.dart',
            'packages/data/tool/database_probe.dart',
            'tools/generate_app_icons.py',
            'apps/client/assets/CHANGELOG.md',
            'apps/client/assets/guide/en.md',
        ):
            with self.subTest(path=path):
                self.assertFalse(select([path], active=ACTIVE)['android'])
        self.assertTrue(select(['apps/client/test/fixtures/fixture.md'], active=ACTIVE)['client'])

    def test_uncertain_module_selection_runs_all_module_tests(self):
        for path in ('apps/client/test/flutter_test_config.dart', 'apps/client/test/fixtures/sample.md',
                     'apps/client/assets/privacy/fa.md', 'contracts/nex-portable-v1.json'):
            with self.subTest(path=path):
                self.assertEqual(select([path], active=ACTIVE)['module_dirs'], 'all')
        self.assertEqual(select(['apps/client/lib/screens/home.dart'], active=None)['module_dirs'], 'all')


class ChangedFilesTest(unittest.TestCase):
    """The diff must describe this branch, not everything that moved on main."""

    def git(self, *args, cwd):
        result = subprocess.run(
            ['git', '-c', 'user.email=ci@example.com', '-c', 'user.name=CI',
             '-c', 'commit.gpgsign=false', '-c', 'init.defaultBranch=main', *args],
            cwd=cwd, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, f'git {args}: {result.stderr}')
        return result.stdout.strip()

    def test_squash_merged_base_is_not_this_branch_s_change(self):
        old = os.getcwd()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            os.chdir(root)
            try:
                self.git('init', '-q', cwd=root)
                (root / 'code.dart').write_text('one\n')
                (root / 'other.md').write_text('one\n')
                self.git('add', '.', cwd=root)
                self.git('commit', '-qm', 'base', cwd=root)
                self.git('checkout', '-qb', 'topic', cwd=root)
                (root / 'code.dart').write_text('two\n')
                self.git('commit', '-qam', 'topic', cwd=root)
                # main moves on; resolving the conflict the usual way folds
                # main's state into the branch, which leaves the merge base
                # behind and made a three-dot diff report main's file too.
                self.git('checkout', '-q', 'main', cwd=root)
                (root / 'other.md').write_text('main moved\n')
                self.git('commit', '-qam', 'main moved', cwd=root)
                base = self.git('rev-parse', 'HEAD', cwd=root)
                self.git('checkout', '-q', 'topic', cwd=root)
                self.git('merge', '-q', '--squash', 'main', cwd=root)
                self.git('commit', '-qm', 'take main', cwd=root)

                self.assertEqual(changed_files(base), ['code.dart'])
                self.assertFalse(version_only_change(base, changed_files(base)))
            finally:
                os.chdir(old)

    def test_a_branch_behind_main_does_not_report_main_s_new_files(self):
        old = os.getcwd()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            os.chdir(root)
            try:
                self.git('init', '-q', cwd=root)
                (root / 'notes.md').write_text('one\n')
                (root / 'existing.dart').write_text('one\n')
                self.git('add', '.', cwd=root)
                self.git('commit', '-qm', 'base', cwd=root)
                self.git('checkout', '-qb', 'topic', cwd=root)
                (root / 'notes.md').write_text('docs only\n')
                self.git('commit', '-qam', 'docs', cwd=root)
                self.git('checkout', '-q', 'main', cwd=root)
                (root / 'server.ts').write_text('main only\n')
                self.git('add', '.', cwd=root)
                self.git('commit', '-qm', 'feature', cwd=root)
                base = self.git('rev-parse', 'HEAD', cwd=root)
                self.git('checkout', '-q', 'topic', cwd=root)

                # The branch is behind main: main's new file would show as a
                # deletion in a plain two-dot diff, and a docs-only change
                # would select the backend suite.
                self.assertEqual(changed_files(base), ['notes.md'])
            finally:
                os.chdir(old)

    def test_a_branch_behind_main_is_still_only_a_version_bump(self):
        # main moved after the branch point. A two-dot diff against main's tip
        # reports main's new line as this branch's deletion, so the careful
        # version bump paid for the whole matrix.
        old = os.getcwd()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            os.chdir(root)
            try:
                self.git('init', '-q', cwd=root)
                client = root / 'apps/client'
                (client / 'lib').mkdir(parents=True)
                (client / 'pubspec.yaml').write_text('name: nex\nversion: 2.9.5\n')
                (client / 'lib/app_version.dart').write_text("const nexAppVersion = '2.9.5';\n")
                self.git('add', '.', cwd=root)
                self.git('commit', '-qm', 'base', cwd=root)
                self.git('checkout', '-qb', 'bump', cwd=root)
                (client / 'pubspec.yaml').write_text('name: nex\nversion: 2.9.6\n')
                (client / 'lib/app_version.dart').write_text("const nexAppVersion = '2.9.6';\n")
                self.git('commit', '-qam', 'bump', cwd=root)
                self.git('checkout', '-q', 'main', cwd=root)
                (client / 'pubspec.yaml').write_text('name: nex\nversion: 2.9.5\ndeps: 1\n')
                self.git('commit', '-qam', 'main moved', cwd=root)
                base = self.git('rev-parse', 'HEAD', cwd=root)
                self.git('checkout', '-q', 'bump', cwd=root)

                files = changed_files(base)
                self.assertEqual(sorted(files), ['apps/client/lib/app_version.dart',
                                                 'apps/client/pubspec.yaml'])
                self.assertTrue(version_only_change(base, files))
            finally:
                os.chdir(old)

    def test_version_only_change_is_recognised(self):
        old = os.getcwd()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            os.chdir(root)
            try:
                self.git('init', '-q', cwd=root)
                client = root / 'apps/client'
                (client / 'lib').mkdir(parents=True)
                (client / 'pubspec.yaml').write_text('name: nex\nversion: 2.9.5\n')
                (client / 'lib/app_version.dart').write_text("const nexAppVersion = '2.9.5';\n")
                self.git('add', '.', cwd=root)
                self.git('commit', '-qm', 'base', cwd=root)
                (client / 'pubspec.yaml').write_text('name: nex\nversion: 2.9.6\n')
                (client / 'lib/app_version.dart').write_text("const nexAppVersion = '2.9.6';\n")
                self.git('commit', '-qam', 'bump', cwd=root)
                base = self.git('rev-parse', 'HEAD^', cwd=root)
                files = changed_files(base)
                self.assertEqual(sorted(files), ['apps/client/lib/app_version.dart', 'apps/client/pubspec.yaml'])
                self.assertTrue(version_only_change(base, files))
                # A dependency edit in the same file is not a version bump.
                (client / 'pubspec.yaml').write_text('name: nex\nversion: 2.9.6\ndeps: 1\n')
                self.git('commit', '-qam', 'dep', cwd=root)
                self.assertFalse(version_only_change(base, changed_files(base)))
            finally:
                os.chdir(old)


    def test_version_shortcut_rejects_any_other_change_in_the_version_files(self):
        cases = (
            ('one file only', 'name: nex\nversion: 2.9.6\n', None),
            ('mismatched versions', 'name: nex\nversion: 2.9.6\n', "const nexAppVersion = '2.9.7';\n"),
            ('code after declaration', 'name: nex\nversion: 2.9.6\n',
             "const nexAppVersion = '2.9.6'; const added = 1;\n"),
            ('duplicate YAML key', 'name: nex\nversion: 2.9.6\nversion: 2.9.7\n', "const nexAppVersion = '2.9.6';\n"),
            ('invalid YAML version', 'name: nex\nversion: 2.9.6: invalid\n', "const nexAppVersion = '2.9.6';\n"),
            ('build suffix', 'name: nex\nversion: 2.9.6+1\n', "const nexAppVersion = '2.9.6';\n"),
            ('file deletion', '', "const nexAppVersion = '2.9.6';\n"),
            ('mode change', 'name: nex\nversion: 2.9.6\n', "const nexAppVersion = '2.9.6';\n"),
            ('type change', 'name: nex\nversion: 2.9.6\n', "const nexAppVersion = '2.9.6';\n"),
        )
        old = os.getcwd()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            os.chdir(root)
            try:
                self.git('init', '-q', cwd=root)
                client = root / 'apps/client'
                pubspec = client / 'pubspec.yaml'
                dart = client / 'lib/app_version.dart'
                dart.parent.mkdir(parents=True)
                pubspec.write_text('name: nex\nversion: 2.9.5\n')
                dart.write_text("const nexAppVersion = '2.9.5';\n")
                self.git('add', '.', cwd=root)
                self.git('commit', '-qm', 'base', cwd=root)
                base = self.git('rev-parse', 'HEAD', cwd=root)

                for case, manifest, constant in cases:
                    with self.subTest(case=case):
                        self.git('reset', '--hard', base, cwd=root)
                        if manifest:
                            pubspec.write_text(manifest)
                        else:
                            pubspec.unlink()
                        if constant is not None:
                            dart.write_text(constant)
                        if case == 'type change':
                            dart.unlink()
                            dart.symlink_to(pubspec)
                        self.git('add', '-A', cwd=root)
                        if case == 'mode change':
                            self.git('update-index', '--chmod=+x', str(dart), cwd=root)
                        self.git('commit', '-qm', case, cwd=root)
                        files = changed_files(base)
                        shortcut = version_only_change(base, files)
                        self.assertFalse(shortcut)
                        self.assertTrue(select(files, version_only=shortcut)['android'])
            finally:
                os.chdir(old)

    def test_renaming_scopes_reports_both_paths(self):
        old = os.getcwd()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            os.chdir(root)
            try:
                self.git('init', '-q', cwd=root)
                source = root / 'apps/client/lib/old.dart'
                source.parent.mkdir(parents=True)
                source.write_text('const before = 1;\n')
                self.git('add', '.', cwd=root)
                self.git('commit', '-qm', 'base', cwd=root)
                source.rename(root / 'README.md')
                self.git('add', '-A', cwd=root)
                self.git('commit', '-qm', 'rename', cwd=root)
                files = changed_files('HEAD^')
                self.assertCountEqual(files, ['apps/client/lib/old.dart', 'README.md'])
                self.assertTrue(select(files)['android'])
            finally:
                os.chdir(old)


if __name__ == '__main__':
    unittest.main()
