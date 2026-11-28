#!/usr/bin/env python3
import copy
import re
import unittest
from pathlib import Path

from check_ci_results import PAUSED, SELECTION, failures, required_jobs

JOBS = ("guard changed-format dart-packages retrieval-budget timeline-budget "
        "flutter-ai-package flutter-ui-package client-tests client-android-build "
        "backend feedback-worker sync-integration ai-deletion-proof "
        "client-windows client-ios").split()

CI = Path(__file__).resolve().parents[1] / '.github/workflows/ci.yml'


class CiResultsTest(unittest.TestCase):
    def summary(self, dart=False, backend=False, content=False, android=False, **overrides):
        flags = dict.fromkeys(SELECTION, False)
        flags.update({'dart': dart, 'backend': backend,
                      # `client` follows Dart unless a test says otherwise.
                      'client': dart, 'content': content, 'android': android,
                      'guards': dart, 'format': dart,
                      'retrieval': dart, 'sync': dart or backend, 'ai_delete': dart})
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

    def test_a_flagged_but_missing_output_fails(self):
        # `desktop` selects no job today; it is still a flag the gate reads, so
        # a workflow that stops emitting it must fail rather than read as
        # "nothing needed".
        needs = self.summary()
        del needs["changes"]["outputs"]["desktop"]
        self.assertTrue(any("desktop" in error for error in failures(needs)))


class WorkflowDriftTest(unittest.TestCase):
    """The gate is only as good as its agreement with the workflow it guards.

    `check_ci_results.py` validates the jobs it knows. A job added to ci.yml and
    left out of `needs` or out of `required` would be invisible: it could skip,
    fail or never be called and "CI green" would still pass. These tests read
    the workflow and hold the three lists together.
    """

    @classmethod
    def setUpClass(cls):
        lines = CI.read_text().splitlines()
        start = lines.index('jobs:')
        cls.jobs, cls.order = {}, []
        current = None
        for line in lines[start + 1:]:
            match = re.match(r'^  ([a-z0-9-]+):$', line)
            if match:
                current = match.group(1)
                cls.order.append(current)
                cls.jobs[current] = []
            elif current is not None:
                cls.jobs[current].append(line)

    def needs_of_green(self):
        needs, inside = [], False
        for line in self.jobs['ci-green']:
            if line.strip() == 'needs:':
                inside = True
                continue
            if inside:
                match = re.match(r'^      - ([a-z0-9-]+)$', line)
                if match:
                    needs.append(match.group(1))
                elif line.strip():
                    break
        return needs

    def test_every_job_is_required_or_explicitly_paused(self):
        required = required_jobs(dict.fromkeys(SELECTION, False))
        planned = set(required) | set(PAUSED) | {'changes', 'ci-green'}
        self.assertEqual(sorted(set(self.jobs) - planned), [],
                         'a job in ci.yml is not validated by check_ci_results.py')

    def test_every_required_job_exists_and_is_in_needs(self):
        required = required_jobs(dict.fromkeys(SELECTION, False))
        needs = set(self.needs_of_green())
        self.assertEqual(sorted(set(required) - set(self.jobs)), [],
                         'check_ci_results.py requires a job ci.yml does not define')
        self.assertEqual(sorted(set(required) - needs), [],
                         'a required job is missing from ci-green needs')
        self.assertEqual(sorted(needs - set(self.jobs)), [],
                         'ci-green needs a job that does not exist')

    def test_paused_jobs_are_really_paused_and_still_watched(self):
        needs = set(self.needs_of_green())
        for name in PAUSED:
            with self.subTest(job=name):
                self.assertIn(name, self.jobs)
                self.assertIn(name, needs, 'a paused job must still fail the gate when it fails')
                self.assertTrue(any(line.strip() == 'if: false' for line in self.jobs[name]),
                                f'{name} is listed as paused but its `if:` is not false')

    def test_every_selection_flag_is_emitted_by_the_changes_job(self):
        block = '\n'.join(self.jobs['changes'])
        for flag in SELECTION:
            self.assertIn(f'outputs.{flag}', block, flag)

    def test_the_gate_still_runs_on_every_event(self):
        # `if: always()` is what makes a skipped dependency fail rather than
        # read as a green required check.
        self.assertTrue(any(line.strip() == 'if: always()' for line in self.jobs['ci-green']))


if __name__ == '__main__':
    unittest.main()
