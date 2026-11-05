import unittest
from ci_paths import FLAGS, changed_files, select

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
        for paths, event in (([], 'pull_request'), (['.github/a'], 'pull_request'), (['README.md'], 'workflow_call')):
            value = select(paths, event, ACTIVE)
            self.assertTrue(all(value[k] for k in FLAGS))
            self.assertEqual(value['module_dirs'], 'all')

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
        for path in ('packages/data/lib/a.dart', 'packages/core/lib/a.dart', 'tools/ci_paths.py', '.fvmrc'):
            value = select([path], active=ACTIVE)
            self.assertTrue(all(value[k] for k in ('retrieval', 'sync', 'ai_delete')), path)
        self.assertTrue(select(['apps/backend/src/routes/auth.ts'])['sync'])
        self.assertTrue(select(['apps/client/pubspec.lock'])['ai_delete'])
        self.assertFalse(select(['README.md'])['dart'])


if __name__ == '__main__':
    unittest.main()
