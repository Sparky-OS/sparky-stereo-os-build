#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
"""The install-download gate against fixture status files and image roots: a package that declares a download is refused with its
name, size and source; FlightGear's data folder is refused; a clean image and a package that only mentions the field in its
description pass; an unreadable status stops with 2. SUBJECT selects another check-no-install-downloads.py."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SUBJECT = Path(os.environ.get('SUBJECT', Path(__file__).resolve().parents[1] / 'check-no-install-downloads.py'))
CLEAN = 'Package: bash\nStatus: install ok installed\nVersion: 5\nDescription: shell\n\nPackage: flightgear\nStatus: install ok installed\nVersion: 1\nDescription: sim\n'
DECL = ('Package: flightgear-data-installer\nStatus: install ok installed\nVersion: 2024.1.5-1\nSparky-Install-Download-Size: 1883333376\n'
        'Sparky-Install-Download-Source: https://sourceforge.net/x/download\nDescription: fetches\n')


def run(*args):
    out = subprocess.run([sys.executable, str(SUBJECT), *args], capture_output=True, text=True)
    return out.returncode, out.stdout + out.stderr


class Gate(unittest.TestCase):
    def root(self, status, data=False):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        (root / 'var/lib/dpkg').mkdir(parents=True)
        (root / 'var/lib/dpkg/status').write_text(status)
        if data:
            (root / 'usr/share/games/flightgear').mkdir(parents=True)
            (root / 'usr/share/games/flightgear/version').write_text('2024.1.5\n')
        return root

    def test_clean_image_passes(self):
        code, text = run(str(self.root(CLEAN)))
        self.assertEqual(code, 0, text)
        self.assertIn('PASS', text)

    def test_declaring_package_is_refused_with_size_and_source(self):
        code, text = run(str(self.root(CLEAN + '\n' + DECL)))
        self.assertEqual(code, 1, text)
        self.assertIn('flightgear-data-installer', text)
        self.assertIn('1883333376', text)
        self.assertIn('https://sourceforge.net/x/download', text)

    def test_removed_package_does_not_count(self):
        code, text = run(str(self.root(CLEAN + '\n' + DECL.replace('install ok installed', 'deinstall ok config-files'))))
        self.assertEqual(code, 0, text)

    def test_unpacked_package_counts(self):
        code, text = run(str(self.root(CLEAN + '\n' + DECL.replace('install ok installed', 'install ok unpacked'))))
        self.assertEqual(code, 1, text)

    def test_data_folder_is_refused(self):
        code, text = run(str(self.root(CLEAN, data=True)))
        self.assertEqual(code, 1, text)
        self.assertIn('FlightGear', text)

    def test_status_only_mode(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'status'
            path.write_text(CLEAN + '\n' + DECL)
            self.assertEqual(run('--status', str(path))[0], 1)
            path.write_text(CLEAN)
            self.assertEqual(run('--status', str(path))[0], 0)

    def test_field_in_a_description_is_not_a_declaration(self):
        text = CLEAN + '\nPackage: doc\nStatus: install ok installed\nDescription: explains\n Sparky-Install-Download-Size: is a control field\n'
        self.assertEqual(run('--status', str(self.root(text) / 'var/lib/dpkg/status'))[0], 0)

    def test_unreadable_status_stops(self):
        self.assertEqual(run('/nonexistent-root')[0], 2)


if __name__ == '__main__':
    unittest.main()
