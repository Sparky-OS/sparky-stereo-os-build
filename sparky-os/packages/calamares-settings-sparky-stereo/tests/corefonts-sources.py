#!/usr/bin/python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
"""Debian contrib edits in disposable source files, including preservation controls."""
from pathlib import Path
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / 'lib/core-fonts-contrib'

class Sources(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.apt = self.root / 'etc/apt'
        (self.apt / 'sources.list.d').mkdir(parents=True)

    def run_helper(self):
        return subprocess.run([str(HELPER), str(self.root)], capture_output=True, text=True)

    def test_deb822_keeps_other_components_comments_and_foreign_source(self):
        path = self.apt / 'sources.list.d/debian.sources'
        source = '# Keep this comment\nTypes: deb deb-src\nURIs: https://deb.debian.org/debian\nSuites: forky\nComponents: main non-free-firmware\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\n'
        path.write_text(source)
        other = self.apt / 'sources.list.d/vendor.sources'
        other.write_text('Types: deb\nURIs: https://example.invalid/\nSuites: stable\nComponents: main\n')
        original = other.read_bytes()
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(path.read_text(), source.replace('Components: main non-free-firmware', 'Components: main non-free-firmware contrib'))
        self.assertEqual(other.read_bytes(), original)
        previous = path.read_bytes()
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(path.read_bytes(), previous)

    def test_classic_options_and_comment_are_kept(self):
        path = self.apt / 'sources.list'
        source = 'deb [signed-by=/key.gpg] https://deb.debian.org/debian forky main # keep\n# deb https://deb.debian.org/debian sid main\n'
        path.write_text(source)
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(path.read_text(), source.replace('forky main #', 'forky main contrib #'))

    def test_multiline_deb822_fields(self):
        path = self.apt / 'sources.list.d/debian.sources'
        path.write_text('Types: deb\nURIs:\n https://deb.debian.org/debian\nSuites: forky\nComponents: main\n non-free-firmware\n')
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertIn(' non-free-firmware contrib\n', path.read_text())

    def test_disabled_or_foreign_only_source_stops(self):
        path = self.apt / 'sources.list.d/disabled.sources'
        path.write_text('Types: deb\nURIs: https://deb.debian.org/debian\nEnabled: no\nComponents: main\n')
        original = path.read_bytes()
        self.assertNotEqual(self.run_helper().returncode, 0)
        self.assertEqual(path.read_bytes(), original)

    def test_live_root_is_refused(self):
        result = subprocess.run([str(HELPER), '/'], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('refusing the live root', result.stderr)

if __name__ == '__main__':
    unittest.main()
