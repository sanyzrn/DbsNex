#!/usr/bin/env python3
import copy
import unittest

from check_ci_results import SELECTION, failures

JOBS = ("guard changed-format dart-packages retrieval-budget timeline-budget "
        "flutter-ai-package flutter-ui-package client-tests client-android-build "
        "backend feedback-worker sync-integration ai-deletion-proof "
        "client-windows client-ios").split()


class CiResultsTest(unittest.TestCase):
    def summary(self, dart=False, backend=False, content=False, android=False, **overrides):
        flags = {'dart': dart, 'backend': backend,
                 # `client` follows Dart unless a test says otherwise.
                 'client': dart, 'content': content, 'android': android,
                 'guards': dart, 'format': dart,
                 'retrieval': dart, 'sync': dart or backend, 'ai_delete': dart}
        flags.update(overrides)
        needs = {'changes': {'result': 'success',
                             'outputs': {key: str(value).lower() for key, value in flags.items()}}}
        needs.update({name: {'result': 'skipped'} for name in JOBS})
        selected = {
            'guard': flags['guards'],
            'changed-format': flags['format'],
            'dart-packages': flags['dart'],
            'retrieval-budget': flags['retrieval'],
            'timeline-budget': flags['client'],
            'flutter-ai-package': flags['dart'],
            'flutter-ui-package': flags['dart'],
            'client-tests': flags['client'] or flags['content'],
            'client-android-build': flags['android'],
            'backend': flags['backend'],
            'feedback-worker': flags['backend'],
            'sync-integration': flags['sync'],
            'ai-deletion-proof': flags['ai_delete'],
        }
        for name, run in selected.items():
            if run:
                needs[name]['result'] = 'success'
        return needs

    def test_intentional_skips_for_each_change_scope_pass(self):
        for dart, backend in ((False, False), (True, False), (False, True), (True, True)):
            with self.subTest(dart=dart, backend=backend):
                self.assertEqual(failures(self.summary(dart, backend)), [])

    def test_documentation_and_content_only_changes_pass(self):
        # The whole point of the change selection: these run one quick job (or
        # none) and must still satisfy the required check.
        self.assertEqual(failures(self.summary()), [])
        self.assertEqual(failures(self.summary(content=True)), [])

    def test_a_content_change_needs_the_content_job(self):
        needs = self.summary(content=True)
        needs['client-tests']['result'] = 'skipped'
        self.assertTrue(failures(needs))

    def test_narrow_heavy_jobs_may_skip_but_selected_ones_must_run(self):
        needs = self.summary(True, False)
        for flag, job in (('retrieval', 'retrieval-budget'), ('sync', 'sync-integration'),
                          ('ai_delete', 'ai-deletion-proof'), ('format', 'changed-format'),
                          ('guards', 'guard')):
            needs['changes']['outputs'][flag] = 'false'
            needs[job]['result'] = 'skipped'
        self.assertEqual(failures(needs), [])
        needs['changes']['outputs']['sync'] = 'true'
        self.assertTrue(failures(needs))

    def test_skipping_a_selected_job_fails(self):
        needs = self.summary(True, True, android=True)
        for name, job in needs.items():
            if job["result"] != "success" or name == "changes":
                continue
            with self.subTest(name=name):
                changed = copy.deepcopy(needs)
                changed[name]["result"] = "skipped"
                self.assertTrue(failures(changed))

    def test_failures_and_cancellations_always_fail(self):
        for result in ("failure", "cancelled"):
            needs = self.summary()
            needs["client-windows"]["result"] = result
            self.assertTrue(failures(needs))

    def test_missing_jobs_and_unknown_flags_fail(self):
        needs = self.summary()
        del needs["client-android-build"]
        self.assertTrue(failures(needs))
        needs = self.summary()
        needs["changes"]["outputs"]["dart"] = ""
        self.assertTrue(failures(needs))
        for flag in SELECTION:
            needs = self.summary()
            needs["changes"]["outputs"][flag] = ""
            self.assertTrue(failures(needs), flag)

    def test_new_unclassified_job_cannot_silently_skip(self):
        needs = self.summary()
        needs["new-check"] = {"result": "skipped"}
        self.assertTrue(failures(needs))


if __name__ == "__main__":
    unittest.main()
