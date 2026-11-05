import contextlib
import io
import tempfile
import unittest
import zipfile
from pathlib import Path

from check_sqlite_assets import check


class SQLiteAssetsTest(unittest.TestCase):
    def artifact(self, prefix="", libraries=None, machines=None, flutter=True):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = Path(tmp.name) / "app.zip"
        libraries = {"arm64-v8a", "armeabi-v7a", "x86_64"} if libraries is None else libraries
        machines = machines or {"arm64-v8a": 183, "armeabi-v7a": 40, "x86_64": 62}
        with zipfile.ZipFile(path, "w") as archive:
            for abi, machine in machines.items():
                if flutter:
                    archive.writestr(f"{prefix}lib/{abi}/libflutter.so", b"engine")
                if abi in libraries:
                    header = bytearray(64)
                    header[:6] = b"\x7fELF\x02\x01"
                    header[18:20] = machine.to_bytes(2, "little")
                    archive.writestr(f"{prefix}lib/{abi}/libsqlite3.so", header)
        return path

    def test_apk_and_bundle_cover_every_flutter_abi(self):
        for prefix in ("", "base/"):
            with contextlib.redirect_stdout(io.StringIO()):
                check(self.artifact(prefix))

    def test_one_missing_abi_fails_even_if_another_is_bundled(self):
        with self.assertRaisesRegex(ValueError, "missing for armeabi-v7a"):
            check(self.artifact(libraries={"arm64-v8a", "x86_64"}))

    def test_wrong_machine_fails(self):
        with self.assertRaisesRegex(ValueError, "architecture mismatch"):
            check(self.artifact(machines={"arm64-v8a": 62}))

    def test_empty_artifact_does_not_pass(self):
        with self.assertRaisesRegex(ValueError, "no Flutter ABI"):
            check(self.artifact(flutter=False))


if __name__ == "__main__":
    unittest.main()
