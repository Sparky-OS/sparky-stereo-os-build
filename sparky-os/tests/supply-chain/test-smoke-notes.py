#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Replay the recorded KWin abort through the link gate; never start a program."""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from lean import linkcheck, package

QT_ERROR = ('Failed to gain real time thread priority: Operation not permitted\n'
            'qt.qpa.plugin: Could not load the Qt platform plugin "wayland-org.kde.kwin.qpa" even though it was found.\n')


class SmokeNotes(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='smoke-notes-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.table = self.root / 'smoke.tsv'
        self.table.write_text('kwin-wayland\t/usr/bin/kwin_wayland\t--version\n')
        self.completed = subprocess.CompletedProcess([], 134, '', QT_ERROR)
        self.qualified = types.SimpleNamespace(arch='amd64', directory=self.root,
            owner=types.SimpleNamespace(ensure_space=lambda *a: None),
            run=lambda *a: self.completed, close=lambda: None)
        def extraction(deb, dest, space):
            exe = Path(dest) / 'usr/bin/kwin_wayland'
            exe.parent.mkdir(parents=True)
            exe.write_bytes(b'fixture')
        for target, kwargs in [
            ('control_field', {'return_value': 'kwin-wayland'}),
            ('extract', {'side_effect': extraction}),
            ('_is_elf', {'return_value': True}),
            ('loader_command', {'return_value': (['/loader', '/usr/bin/kwin_wayland'], False)}),
        ]:
            mock = patch.object(linkcheck, target, **kwargs)
            mock.start()
            self.addCleanup(mock.stop)

    def smoke(self):
        notes = []
        findings = linkcheck.smoke('/candidate.deb', self.table, qualified=self.qualified, notes=notes)
        return findings, notes

    def test_recorded_134_is_note_and_contains_signal_and_stderr(self):
        findings, notes = self.smoke()
        self.assertEqual(findings, [])
        self.assertEqual(len(notes), 1)
        for expected in ('/usr/bin/kwin_wayland', '134 (SIGABRT)', QT_ERROR.splitlines()[0], 'Qt platform plugin'):
            self.assertIn(expected, notes[0])

    def test_zero_has_neither(self):
        self.completed = subprocess.CompletedProcess([], 0, '', '')
        self.assertEqual(self.smoke(), ([], []))

    def test_loader_error_still_fails_without_note(self):
        self.completed = subprocess.CompletedProcess([], 127, '', 'error while loading shared libraries: libmissing.so')
        findings, notes = self.smoke()
        self.assertEqual(len(findings), 1)
        self.assertIn('loader error', findings[0])
        self.assertEqual(notes, [])

    def test_direct_signal_and_unknown_status(self):
        for status, rendered in ((-6, '-6 (SIGABRT)'), (255, '255')):
            with self.subTest(status=status):
                self.completed = subprocess.CompletedProcess([], status, '', QT_ERROR)
                findings, notes = self.smoke()
                self.assertEqual(findings, [])
                self.assertIn(rendered, notes[0])

    def test_check_prints_note_and_records_it_without_failing(self):
        ctx = types.SimpleNamespace(qualify=lambda *a: self.qualified)
        out = io.StringIO()
        with patch.object(linkcheck, 'compare', return_value=([], [])), contextlib.redirect_stdout(out):
            notes = linkcheck.check('/candidate.deb', smoke_table=self.table, archive_context=ctx)
        self.assertEqual(len(notes), 1)
        self.assertIn('134 (SIGABRT)', out.getvalue())
        record = json.loads((self.root / 'link-check.json').read_text())
        self.assertEqual(record['notes'], notes)
        self.assertEqual(record['findings'], [])

    def test_loader_failure_is_still_recorded_and_raised(self):
        self.completed = subprocess.CompletedProcess([], 127, '', 'undefined symbol: missing')
        ctx = types.SimpleNamespace(qualify=lambda *a: self.qualified)
        with patch.object(linkcheck, 'compare', return_value=([], [])), self.assertRaises(package.Invalid):
            linkcheck.check('/candidate.deb', smoke_table=self.table, archive_context=ctx)
        record = json.loads((self.root / 'link-check.json').read_text())
        self.assertEqual(len(record['findings']), 1)
        self.assertEqual(record['notes'], [])


if __name__ == '__main__':
    unittest.main()
