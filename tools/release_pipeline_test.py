"""Exercise tag parsing, release gates and CI dependency completeness."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class PipelineTest(unittest.TestCase):
    def test_untrusted_tag_is_data_and_valid_codes_increase(self):
        source = (ROOT / '.github/workflows/release.yml').read_text()
        block = source.split('      - id: parse\n', 1)[1].split('      - uses:', 1)[0]
        script = '\n'.join(line[10:] for line in block.splitlines() if line.startswith('          '))
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / 'executed'
            def run(tag):
                output = Path(directory) / 'output'
                output.write_text('')
                process = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', script], env=os.environ | {'RELEASE_TAG': tag, 'GITHUB_OUTPUT': str(output)}, capture_output=True, text=True)
                return process.returncode, output.read_text()
            for tag in (f'$(touch {marker})', 'v.2.6.6', 'v2.100.0', 'v2.6.6;exit 0'):
                self.assertNotEqual(run(tag)[0], 0)
            self.assertFalse(marker.exists())
            old_status, old = run('v2.6.5')
            new_status, new = run('2.6.6')
            self.assertEqual((old_status, new_status), (0, 0))
            code = lambda text: int(re.search(r'^code=(\d+)$', text, re.M)[1])
            self.assertGreater(code(new), code(old) + 4000)

    def test_publish_is_downstream_of_verify_and_android(self):
        source = (ROOT / '.github/workflows/release.yml').read_text()
        def block(name):
            return re.search(rf'^  {name}:\n(.*?)(?=^  [\w-]+:|\Z)', source, re.M | re.S)[1]
        self.assertIn('needs: [version, verify]', block('build-android'))
        self.assertIn('needs: [version, build-android]', block('publish-release'))
        self.assertIn('uses: ./.github/workflows/ci.yml', block('verify'))
        self.assertIn('tools/verify_apk_updates.py', block('build-android'))
        self.assertIn('tools/check_store_permissions.sh', block('build-android'))

    def test_every_ci_job_feeds_the_required_gate(self):
        source = (ROOT / '.github/workflows/ci.yml').read_text()
        jobs = set(re.findall(r'^  ([a-z][\w-]+):$', source.split('jobs:', 1)[1], re.M)) - {'ci-green'}
        gate = source.split('  ci-green:', 1)[1]
        dependencies = set(re.findall(r'^      - ([a-z][\w-]+)$', gate, re.M))
        self.assertEqual(jobs, dependencies)
        self.assertIn('if: always()', gate)

    def test_all_external_actions_are_immutable(self):
        for path in (ROOT / '.github/workflows').glob('*.yml'):
            for action in re.findall(r'uses: ([^\s]+)', path.read_text()):
                if not action.startswith('./'):
                    self.assertRegex(action, r'@[a-f0-9]{40}$', f'{path}: {action}')


if __name__ == '__main__':
    unittest.main()
