#!/usr/bin/env python3
import copy
import unittest

from check_ci_results import failures


class CiResultsTest(unittest.TestCase):
    def summary(self, dart=False, backend=False):
        names = ("changes core-boundary widget-layouts dart-packages retrieval-budget "
                 "timeline-budget flutter-ai-package flutter-ui-package client-android "
                 "ai-deletion-proof backend feedback-worker merge-conformance "
                 "sync-integration client-windows client-ios").split()
        needs = {name: {"result": "success"} for name in names}
        needs["changes"]["outputs"] = {"dart": str(dart).lower(), "backend": str(backend).lower()}
        for name in ("client-windows", "client-ios"):
            needs[name]["result"] = "skipped"
        if not backend:
            for name in ("backend", "feedback-worker"):
                needs[name]["result"] = "skipped"
        if not dart:
            for name in ("dart-packages", "retrieval-budget", "timeline-budget",
                         "flutter-ai-package", "flutter-ui-package", "client-android",
                         "ai-deletion-proof"):
                needs[name]["result"] = "skipped"
        if not dart and not backend:
            for name in ("merge-conformance", "sync-integration"):
                needs[name]["result"] = "skipped"
        return needs

    def test_intentional_skips_for_each_change_scope_pass(self):
        for dart, backend in ((False, False), (True, False), (False, True), (True, True)):
            with self.subTest(dart=dart, backend=backend):
                self.assertEqual(failures(self.summary(dart, backend)), [])

    def test_skipping_a_selected_job_fails(self):
        needs = self.summary(True, True)
        for name in needs:
            if name in ("client-windows", "client-ios"):
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
        del needs["client-android"]
        self.assertTrue(failures(needs))
        needs = self.summary()
        needs["changes"]["outputs"]["dart"] = ""
        self.assertTrue(failures(needs))

    def test_new_unclassified_job_cannot_silently_skip(self):
        needs = self.summary()
        needs["new-check"] = {"result": "skipped"}
        self.assertTrue(failures(needs))


if __name__ == "__main__":
    unittest.main()
