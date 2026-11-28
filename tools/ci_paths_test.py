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
                     'analysis_options.yaml', 'melos.yaml', 'apps/store/README.md'):
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

    def test_android_build_follows_android_inputs_only(self):
        for path in ('apps/client/android/app/build.gradle.kts', 'apps/client/pubspec.lock',
                     'packages/ui/pubspec.yaml', 'tools/install_android_ndk.sh',
                     # Packaged into the APK.
                     'apps/client/assets/fonts/Vazirmatn.ttf',
                     # A plugin's native half ships inside the app.
                     'packages/ui/android/src/main/kotlin/Plugin.kt',
                     # The JVM policy runs inside the Android job.
                     'tools/daily_nudge_native_test.py',
                     # The ai flavor's entry point builds the shipping bundle.
                     'apps/client/lib/main_ai.dart'):
            self.assertTrue(select([path])['android'], path)
        for path in ('apps/client/lib/main.dart', 'tools/generate_app_icons.py',
                     # Content, not an APK input.
                     'apps/client/assets/CHANGELOG.md'):
            self.assertFalse(select([path])['android'], path)


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


if __name__ == '__main__':
    unittest.main()
