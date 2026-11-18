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

    def forge(self):
        edited = LEAN.replace(b'value=old', b'value=own')
        self.file.write_bytes(edited)
        records = stereo.Records(self.P)
        records[PATH] = dict(records[PATH], sha_lean=stereo.sha256(edited))
        records.save()
        return edited

    def test_older_dpkg_pre_invoke_refuses_forged_projection(self):
        edited = self.forge()
        with patch.dict(os.environ, DPKG_LEAN_CODE_VERSION=''), self.assertRaisesRegex(RuntimeError, 'projection-mismatch'):
            stereo.pre_invoke(self.P, 'install')
        self.assertEqual(self.file.read_bytes(), edited)

    def test_restore_refuses_forged_projection_and_keeps_problem(self):
        edited = self.forge()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(stereo.restore(self.P, [PACKAGE]), 1)
        self.assertEqual(self.file.read_bytes(), edited)
        self.assertIn(PATH, stereo.Records(self.P))
        problem = next(p for p in stereo.kept_problems(self.P) if p['step'] == 'restore')
        self.assertIn('projection-mismatch', problem['items'][0]['detail'])

    def test_restore_valid_projection(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(stereo.restore(self.P, [PACKAGE]), 0)
        self.assertEqual(self.file.read_bytes(), ORIGINAL)

    def test_noop_configure_does_not_query_capability(self):
        with patch.object(stereo.subprocess, 'run', side_effect=AssertionError('unneeded capability process')), \
             patch.object(stereo, 'write_lean', side_effect=AssertionError('no-op wrote a conffile')):
            self.assertEqual(stereo.pre_invoke(self.P, 'configure'), 0)
        self.assertEqual(self.file.read_bytes(), LEAN)

    def tree(self, modes=None):
        """A verifier tree of its own under the test's root, as dpkg's native caller and the verifier walk it."""
        base = self.root / 'trust'
        for name, mode in (('', 0o755), ('usr', 0o755), ('usr/lib', 0o755), ('usr/lib/dpkg-stereo', 0o755),
                           ('usr/lib/dpkg-stereo/lean', 0o755), ('usr/lib/dpkg-stereo/lean/__pycache__', 0o755)):
            (base / name).mkdir(exist_ok=True)
            (base / name).chmod(mode)
        verifier = base / 'usr/lib/dpkg-stereo/conffile-verify'
        verifier.write_text('#!/bin/sh\n')
        verifier.chmod(0o755)
        (base / 'usr/lib/dpkg-stereo/lean/core.py').write_text('x = 1\n')
        (base / 'usr/lib/dpkg-stereo/lean/core.py').chmod(0o644)
        for name, mode in (modes or {}).items():
            (base / name).chmod(mode)
        patcher = patch.object(events, 'TREE_BASE', str(base))
        patcher.start()
        self.addCleanup(patcher.stop)
        return base

    def test_trust_findings_are_empty_for_a_trusted_tree(self):
        self.tree()
        self.assertEqual(events.trust_findings(), [])

    def test_trust_findings_name_the_folder_and_its_mode(self):
        self.tree({'usr/lib/dpkg-stereo': 0o775})
        self.assertEqual(events.trust_findings()[0], ['LOCAL86', '/usr/lib/dpkg-stereo', '775'])

    def test_trust_findings_cover_the_lean_tree_the_verifier_walks(self):
        self.tree({'usr/lib/dpkg-stereo/lean/core.py': 0o664})
        (self.root / 'trust/usr/lib/dpkg-stereo/lean/core.py').chmod(0o664)
        self.assertEqual(events.trust_findings(), [['LOCAL86', '/usr/lib/dpkg-stereo/lean/core.py', '664']])

    def test_trust_findings_name_a_foreign_owner_a_link_and_a_missing_verifier(self):
        base = self.tree()
        os.chown(base / 'usr/lib/dpkg-stereo/lean', 12345, 0)
        self.assertEqual(events.trust_findings(), [['LOCAL87', '/usr/lib/dpkg-stereo/lean', 12345]])
        os.chown(base / 'usr/lib/dpkg-stereo/lean', 0, 0)
        (base / 'usr/lib/dpkg-stereo/lean/link').symlink_to('core.py')
        self.assertEqual(events.trust_findings(), [['LOCAL88', '/usr/lib/dpkg-stereo/lean/link']])
        (base / 'usr/lib/dpkg-stereo/lean/link').unlink()
        (base / 'usr/lib/dpkg-stereo/conffile-verify').chmod(0o644)
        self.assertEqual(events.trust_findings(), [['LOCAL90', '/usr/lib/dpkg-stereo/conffile-verify', '644']])
        (base / 'usr/lib/dpkg-stereo/conffile-verify').unlink()
        self.assertEqual(events.trust_findings(), [['LOCAL89', '/usr/lib/dpkg-stereo/conffile-verify']])

    def test_mend_changes_only_dpkg_stereos_own_tree(self):
        base = self.tree({'usr/lib': 0o775, 'usr/lib/dpkg-stereo': 0o775, 'usr/lib/dpkg-stereo/lean': 0o775})
        foreign = base / 'usr/lib/dpkg-stereo/lean/__pycache__'
        os.chown(foreign, 12345, 0)
        foreign.chmod(0o777)
        mended = events.mend_own_tree()
        self.assertEqual(sorted(m[0] for m in mended), ['/usr/lib/dpkg-stereo', '/usr/lib/dpkg-stereo/lean'])
        self.assertEqual(oct((base / 'usr/lib').stat().st_mode & 0o7777), '0o775')
        self.assertEqual(oct((base / 'usr/lib/dpkg-stereo').stat().st_mode & 0o7777), '0o755')
        self.assertEqual(oct(foreign.stat().st_mode & 0o7777), '0o777')

    def test_refusal_keeps_the_folder_and_the_check(self):
        self.tree({'usr/lib/dpkg-stereo': 0o775})
        self.file.write_bytes(LEAN)
        self.event(14)
        self.assertFalse(self.report())
        item = self.kept()['items'][0]
        self.assertEqual(item['finding'], ['LOCAL86', '/usr/lib/dpkg-stereo', '775'])
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            stereo.show_problems(self.P)
        self.assertIn('/usr/lib/dpkg-stereo', output.getvalue())
        self.assertIn('775', output.getvalue())

    def test_repair_settles_a_conffile_that_is_the_projection_of_its_package_original(self):
        self.event(14)
        self.assertFalse(self.report())
        self.assertEqual(self.file.read_bytes(), LEAN)
        self.assertTrue(self.report(refresh=True))
        self.assertFalse(stereo.kept_problems(self.P))
        self.assertEqual(self.file.read_bytes(), LEAN)

    def test_repair_says_what_it_cannot_mend_even_when_every_file_is_settled(self):
        self.tree({'usr/lib': 0o775})
        self.event(14)
        self.assertFalse(self.report())
        said = io.StringIO()
        with contextlib.redirect_stderr(said):
            self.assertTrue(events.report(self.P, stereo, True))
        self.assertIn('/usr/lib', said.getvalue())
        self.assertIn('775', said.getvalue())
        self.assertEqual(oct((self.root / 'trust/usr/lib').stat().st_mode & 0o7777), '0o775')

    def test_repair_does_not_settle_a_projection_of_another_version(self):
        self.file.write_bytes(project.project(PATH, ORIGINAL.replace(b'value=old', b'value=older'), PACKAGE,
                                              check=False).lean)
        kept = self.file.read_bytes()
        self.event(14)
        self.assertFalse(self.report())
        self.assertFalse(self.report(refresh=True))
        self.assertEqual(self.file.read_bytes(), kept)

    def test_repair_does_not_settle_a_person_edit_of_the_projection(self):
        edited = LEAN.replace(b'value=old', b'value=own')
        self.file.write_bytes(edited)
        self.event(14)
        self.assertFalse(self.report())
        self.assertFalse(self.report(refresh=True))
        self.assertEqual(self.file.read_bytes(), edited)

    def test_nine_languages_have_the_same_message_arguments(self):
        keys = list(range(61, 72)) + [73, 74, 75] + list(range(86, 93))
        for lang in stereo.LANGS:
            for key in keys:
                name = f'LOCAL{key}'
                self.assertIn(name, stereo.strings(lang))
                self.assertEqual(stereo.strings(lang)[name].count('%s'),
                                 stereo.strings('en')[name].count('%s'), (lang, name))


if __name__ == '__main__':
    unittest.main(verbosity=2)
