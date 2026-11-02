#!/usr/bin/env python3
"""Exercise release validation against isolated source trees, including old main."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).with_name("release_notes.py").resolve()
EN = "# Changelog\n\n## Unreleased\n\n## v2.5.3\n\n- New release.\n\n## v2.5.2\n\n- Old release.\n"
FA = "# تازه‌ها\n\n## Unreleased\n\n## v2.5.3\n\n- نسخهٔ تازه.\n\n## v2.5.2\n\n- نسخهٔ قبل.\n"


class ReleaseNotesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write("CHANGELOG.md", EN)
        self.write("CHANGELOG.fa.md", FA)
        self.write("apps/client/assets/CHANGELOG.md", EN)
        self.write("apps/client/assets/CHANGELOG.fa.md", FA)
        self.write("apps/client/pubspec.yaml", "name: nex_client\nversion: 2.5.3\n")
        self.write("apps/client/lib/app_version.dart", "const nexAppVersion = '2.5.3';\n")

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content.encode("utf-8"))

    def run_tool(self, tag="v2.5.3", expected=0):
        output = self.root / "RELEASE_NOTES.md"
        result = subprocess.run(
            [sys.executable, str(TOOL), "--tag", tag, "--root", str(self.root), "--output", str(output)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        if expected:
            self.assertFalse(output.exists(), "Invalid source must not generate publishable notes")
        return result, output

    def test_extracts_only_requested_release_in_both_languages(self):
        _, output = self.run_tool()
        self.assertEqual(output.read_text(), "- New release.\n\n<!-- nex:fa -->\n- نسخهٔ تازه.\n")

    def test_old_main_without_release_section_fails_with_recovery(self):
        self.write("CHANGELOG.md", EN.replace("## v2.5.3\n\n- New release.\n\n", ""))
        result, _ = self.run_tool(expected=1)
        self.assertIn("Merge the release PR first", result.stderr)
        self.assertIn("Re-running an old run keeps its original commit", result.stderr)

    def test_blank_section_is_not_publishable(self):
        self.write("CHANGELOG.md", EN.replace("- New release.", " \n\t"))
        result, _ = self.run_tool(expected=1)
        self.assertIn("section is empty", result.stderr)

    def test_comment_only_section_is_not_publishable(self):
        self.write("CHANGELOG.md", EN.replace("- New release.", "<!-- TODO -->"))
        self.run_tool(expected=1)

    def test_duplicate_sections_are_rejected(self):
        self.write("CHANGELOG.md", EN + "\n## v2.5.3\n\n- Duplicate.\n")
        self.run_tool(expected=1)

    def test_missing_tag_does_not_fall_back_to_newest_release(self):
        self.run_tool("v2.5.4", expected=1)

    def test_old_version_cannot_be_stamped_as_new_source(self):
        for name, content in (
            ("apps/client/pubspec.yaml", "version: 2.5.2\n"),
            ("apps/client/lib/app_version.dart", "const nexAppVersion = '2.5.2';\n"),
        ):
            with self.subTest(name=name):
                old = (self.root / name).read_text()
                self.write(name, content)
                result, _ = self.run_tool(expected=1)
                self.assertIn("requested release is v2.5.3", result.stderr)
                self.write(name, old)

    def test_stale_bundled_notes_fail(self):
        for name in ("CHANGELOG.md", "CHANGELOG.fa.md"):
            with self.subTest(name=name):
                self.write("apps/client/assets/" + name, "old notes")
                self.run_tool(expected=1)
                self.write("apps/client/assets/" + name, EN if name == "CHANGELOG.md" else FA)

    def test_crlf_checkouts_work(self):
        for name in ("CHANGELOG.md", "CHANGELOG.fa.md"):
            text = (self.root / name).read_text().replace("\n", "\r\n")
            self.write(name, text)
            self.write("apps/client/assets/" + name, text)
        self.run_tool()

    def test_optional_persian_fallback_is_preserved(self):
        self.write("CHANGELOG.fa.md", "## v2.5.2\n\n- نسخهٔ قبل.\n")
        self.write("apps/client/assets/CHANGELOG.fa.md", "## v2.5.2\n\n- نسخهٔ قبل.\n")
        result, output = self.run_tool()
        self.assertIn("::warning::", result.stdout)
        self.assertEqual(output.read_text(), "- New release.\n")

    def test_empty_persian_section_fails(self):
        self.write("CHANGELOG.fa.md", FA.replace("- نسخهٔ تازه.", ""))
        self.run_tool(expected=1)

    def test_prerelease_and_build_suffixes_are_supported(self):
        for name, text in (("CHANGELOG.md", EN), ("CHANGELOG.fa.md", FA)):
            text = text.replace("## v2.5.3", "## v2.5.3-beta.1")
            self.write(name, text)
            self.write("apps/client/assets/" + name, text)
        self.write("apps/client/pubspec.yaml", "version: 2.5.3+205030000\n")
        self.run_tool("2.5.3-beta.1")


if __name__ == "__main__":
    unittest.main()
