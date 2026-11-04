import copy
import unittest
from pathlib import Path
from unittest.mock import patch
from verify_apk_updates import VARIANTS, metadata, verify


class ApkUpdateTest(unittest.TestCase):
    def test_reads_real_tool_output_and_rejects_missing_metadata(self):
        badging = "package: name='com.sanyzrn.nex' versionCode='206050000' versionName='2.6.5'\nnative-code: 'arm64-v8a' 'x86_64'\n"
        signer = 'Signer #1 certificate SHA-256 digest: ' + 'a' * 64 + '\n'
        with patch('verify_apk_updates.subprocess.check_output', side_effect=[badging, signer]) as command:
            value = metadata(Path('release.apk'), Path('/sdk/build-tools'))
            self.assertEqual(value['code'], 206050000)
            self.assertEqual(value['abis'], {'arm64-v8a', 'x86_64'})
            self.assertIn('verify', command.call_args_list[1].args[0])
        for bad, cert in (('', signer), (badging, ''), (badging.split('native-code:')[0], signer)):
            with patch('verify_apk_updates.subprocess.check_output', side_effect=[bad, cert]), self.assertRaises(ValueError):
                metadata(Path('broken.apk'), Path('/sdk/build-tools'))

    def fixtures(self):
        abis = {'arm64-v8a', 'armeabi-v7a', 'x86_64'}
        def artifact(variant, code):
            return {'id': 'com.sanyzrn.nex', 'signers': {'a' * 64}, 'code': code,
                    'abis': abis.copy() if variant in ('universal', 'store') else {variant}}
        old = {v: artifact(v, 10000 + i * 1000) for i, v in enumerate(VARIANTS)}
        new = {v: artifact(v, 20000 + i * 1000) for i, v in enumerate(VARIANTS)}
        return old, new

    def test_all_variants_can_update(self):
        verify(*self.fixtures())

    def test_universal_must_outrank_previous_split(self):
        for code in (11000, 14000):
            old, new = self.fixtures()
            new['universal']['code'] = code
            with self.assertRaisesRegex(ValueError, 'versionCode'):
                verify(old, new)

    def test_signature_package_store_and_abi_regressions_fail(self):
        for variant in VARIANTS:
            for field, value in (('signers', {'b' * 64}), ('id', 'other.app'), ('abis', set())):
                old, new = self.fixtures()
                new[variant][field] = copy.copy(value)
                with self.subTest(variant=variant, field=field), self.assertRaises(ValueError):
                    verify(old, new)
        old, new = self.fixtures()
        del new['store']
        with self.assertRaises(ValueError):
            verify(old, new)


if __name__ == '__main__':
    unittest.main()
