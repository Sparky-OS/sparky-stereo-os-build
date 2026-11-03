#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Conffile diagnostics and pre-invoke tests with the real problems engine.

Run in a disposable container after installing the candidate program, helper,
message files and generated catalogue. Every test uses an isolated data root.
"""
import contextlib
import hashlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, '/usr/lib/dpkg-stereo')
import dpkg_stereo as stereo
import conffile_events as events
from lean import project

PACKAGE = 'order376-events'
PATH = '/etc/default/order376-events'
ORIGINAL = b'# The distributed setting has this explanation.\n' * 20 + b'value=old\n'
LEAN = project.project(PATH, ORIGINAL, PACKAGE, check=False).lean
MD5 = hashlib.md5(ORIGINAL).hexdigest()


class EventsTest(unittest.TestCase):
    def setUp(self):
        self.hook_version = patch.dict(os.environ, DPKG_LEAN_CODE_VERSION='2')
        self.hook_version.start()
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.P = stereo.Paths(str(self.root))
        self.file = self.root / PATH.lstrip('/')
        self.file.parent.mkdir(parents=True)
        self.file.write_bytes(LEAN)
        info = self.root / 'var/lib/dpkg/info'
        info.mkdir(parents=True)
        (info / (PACKAGE + '.list')).write_text(PATH + '\n')
        (info.parent / 'status').write_text(
            f'Package: {PACKAGE}\nStatus: install ok installed\nArchitecture: all\n'
            f'Version: 1\nConffiles:\n {PATH} {MD5}\n\n')
        stereo.store_pristine(self.P, ORIGINAL)
        records = stereo.Records(self.P)
        records[PATH] = dict(path=PATH, package=PACKAGE, version='1', conffile='1',
                             sha_orig=stereo.sha256(ORIGINAL), md5_orig=MD5, sha_lean=stereo.sha256(LEAN),
                             handler='shell', variant='env', bytes_orig=len(ORIGINAL), bytes_lean=len(LEAN))
        records.save()
        self.journal = Path(self.P.state('conffile-events'))

    def tearDown(self):
        self.tmp.cleanup()
        self.hook_version.stop()

    def event(self, code):
        self.journal.write_text(f'{PACKAGE}\t{PATH.encode().hex()}\t{code}\n')
        self.journal.chmod(0o600)

    def report(self, refresh=False):
        with contextlib.redirect_stderr(io.StringIO()):
            return events.report(self.P, stereo, refresh)

    def kept(self):
        return next(p for p in stereo.kept_problems(self.P) if p['step'] == 'conffiles')

    def test_fallback_kept_with_file_package_reason_and_dist(self):
        self.file.write_bytes(b'value=personal\n')
        candidate = Path(str(self.file) + '.dpkg-dist')
        candidate.write_bytes(b'value=new\n')
        self.event(13)
        self.assertFalse(self.report())
        item = self.kept()['items'][0]
        self.assertEqual((item['package'], item['path'], item['reason'], item['location']),
                         (PACKAGE, PATH, 13, PATH + '.dpkg-dist'))
        self.assertEqual(self.journal.read_bytes(), b'')
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(stereo.show_problems(self.P), 1)
        for word in (PACKAGE, PATH, 'does not reproduce', '.dpkg-dist'):
            self.assertIn(word, output.getvalue())
        self.assertEqual(self.file.read_bytes(), b'value=personal\n')

    def test_missing_verifier_names_dpkg_new(self):
        Path(str(self.file) + '.dpkg-new').write_bytes(b'value=new\n')
        self.event(14)
        self.assertFalse(self.report())
        self.assertEqual(self.kept()['items'][0]['location'], PATH + '.dpkg-new')
        self.assertEqual(self.file.read_bytes(), LEAN)

    def test_success_clears_a_previous_refusal(self):
        self.event(13)
        self.assertFalse(self.report())
        self.event(0)
        self.assertTrue(self.report())
        self.assertFalse(stereo.kept_problems(self.P))

    def test_purged_package_clears_its_old_diagnostic(self):
        self.event(13)
        self.assertFalse(self.report())
        (self.root / 'var/lib/dpkg/status').write_text('')
        self.assertTrue(self.report())
        self.assertFalse(stereo.kept_problems(self.P))
        self.assertEqual(self.file.read_bytes(), LEAN)

    def test_failed_engine_does_not_discard_the_journal(self):
        self.event(13)
        saved = self.journal.read_bytes()
        with patch.object(stereo, 'keep_problem', return_value=False):
            self.assertFalse(self.report())
        self.assertEqual(self.journal.read_bytes(), saved)

    def test_bad_journal_is_not_discarded(self):
        self.event(99)
        saved = self.journal.read_bytes()
        with self.assertRaises(ValueError):
            self.report()
        self.assertEqual(self.journal.read_bytes(), saved)

    def test_repair_only_rechecks(self):
        self.file.write_bytes(b'value=personal\n')
        self.event(13)
        self.assertFalse(self.report())
        self.assertFalse(self.report(refresh=True))
        self.assertEqual(self.file.read_bytes(), b'value=personal\n')
        self.file.write_bytes(ORIGINAL)  # explicit user resolution
        self.assertTrue(self.report(refresh=True))
        self.assertFalse(stereo.kept_problems(self.P))

    def test_capability_two_writes_no_conffile(self):
        before = self.file.stat()
        capability = subprocess.CompletedProcess([], 0, b'dpkg-lean-code (= 2)', b'')
        with patch.object(stereo.subprocess, 'run', return_value=capability), \
             patch.object(stereo, 'write_lean', side_effect=AssertionError('pre-invoke wrote a conffile')):
            self.assertEqual(stereo.pre_invoke(self.P, 'install'), 0)
        after = self.file.stat()
        self.assertEqual((before.st_ino, before.st_mtime_ns, before.st_ctime_ns),
                         (after.st_ino, after.st_mtime_ns, after.st_ctime_ns))
        self.assertEqual(self.file.read_bytes(), LEAN)

    def test_old_running_binary_with_new_database_keeps_restoration(self):
        capability = subprocess.CompletedProcess([], 0, b'dpkg-lean-code (= 2)', b'')
        with patch.dict(os.environ, DPKG_LEAN_CODE_VERSION=''), \
             patch.object(stereo.subprocess, 'run', return_value=capability):
            self.assertEqual(stereo.pre_invoke(self.P, 'install'), 1)
        self.assertEqual(self.file.read_bytes(), ORIGINAL)

    def test_older_dpkg_keeps_restoration(self):
        capability = subprocess.CompletedProcess([], 0, b'dpkg-lean-code (= 1)', b'')
        with patch.object(stereo.subprocess, 'run', return_value=capability):
            self.assertEqual(stereo.pre_invoke(self.P, 'install'), 1)
        self.assertEqual(self.file.read_bytes(), ORIGINAL)

    def test_capability_query_failure_is_reportable(self):
        capability = subprocess.CompletedProcess([], 1, b'', b'query failed')
        with patch.object(stereo.subprocess, 'run', return_value=capability), self.assertRaises(RuntimeError):
            stereo.pre_invoke(self.P, 'install')
        self.assertEqual(self.file.read_bytes(), LEAN)

    def test_nine_languages_have_the_same_message_arguments(self):
        keys = list(range(52, 63)) + [64, 65, 66]
        for lang in stereo.LANGS:
            for key in keys:
                name = f'LOCAL{key}'
                self.assertIn(name, stereo.strings(lang))
                self.assertEqual(stereo.strings(lang)[name].count('%s'),
                                 stereo.strings('en')[name].count('%s'), (lang, name))


if __name__ == '__main__':
    unittest.main(verbosity=2)
