import json
import unittest
from require_tests import ran_tests


class TestExecutionGuard(unittest.TestCase):
    def test_tap_empty_skipped_and_failed_suites_fail(self):
        for output in ('', '# tests 0\n# pass 0\n# fail 0\n# cancelled 0\n',
                       '# tests 3\n# pass 0\n# skipped 3\n# fail 0\n# cancelled 0\n',
                       '# tests 2\n# pass 1\n# fail 1\n# cancelled 0\n'):
            self.assertFalse(ran_tests(output, 'tap'))
        self.assertTrue(ran_tests('# tests 3\n# pass 3\n# fail 0\n# cancelled 0\n', 'tap'))

    def test_dart_requires_completed_real_tests(self):
        def result(**kw):
            return json.dumps({'type': 'testDone', 'result': 'success', **kw}) + '\n'
        done = json.dumps({'type': 'done', 'success': True})
        for output in (done, result(hidden=True) + done, result(skipped=True) + done, result()):
            self.assertFalse(ran_tests(output, 'dart'))
        self.assertTrue(ran_tests(result(hidden=False, skipped=False) + done, 'dart'))


if __name__ == '__main__':
    unittest.main()
