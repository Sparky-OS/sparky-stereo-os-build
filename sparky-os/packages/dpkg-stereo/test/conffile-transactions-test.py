#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Actual native dpkg transactions in a disposable root container.

Usage: conffile-transactions-test.py SOURCE-BUILT-DPKG
       conffile-transactions-test.py --installed
       conffile-transactions-test.py --installed-baseline TransactionsTest.test_forged_projection_cannot_hide_edit_through_hooks
The program/toolkit/catalogue must already be installed in the container.
Source-build mode supplies explicit hooks and the recipe's Provides field.
Installed mode checks real package metadata and uses the packaged hook file;
it does not rewrite dpkg's status stanza or add command-line hooks.
A fixture renderer package replaces core.py so dpkg itself changes the active
renderer during unpack. Never run this test on a host or a shared container.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

mode = sys.argv.pop(1)
INSTALLED = mode in ('--installed', '--installed-baseline')
NATIVE = '/usr/bin/dpkg' if INSTALLED else mode
sys.path.insert(0, '/usr/lib/dpkg-stereo')
import dpkg_stereo as stereo
from lean import project

PACKAGE = 'order376-transaction'
RENDERER = 'order376-renderer'
PATH = '/etc/default/order376-transaction'
CORE = Path('/usr/lib/dpkg-stereo/lean/core.py')
ORIGINAL = b'# The distributed setting has this explanation.\n' * 20 + b'value=old\n'
NEW = ORIGINAL.replace(b'value=old', b'value=new')
LEAN = project.project(PATH, ORIGINAL, PACKAGE, check=False).lean
NEW_LEAN = project.project(PATH, NEW, PACKAGE, check=False).lean
HOOK = '/usr/bin/python3 /usr/lib/dpkg-stereo/dpkg_stereo.py'


class TransactionsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not Path('/.dockerenv').exists() or os.geteuid() != 0:
            raise RuntimeError('use a disposable root container')
        cls.core = CORE.read_bytes()
        if INSTALLED:
            version, provides = subprocess.check_output(
                ['/usr/bin/dpkg-query', '-W', '-f=${Version}\n${Provides}', 'dpkg'], text=True).split('\n')
            baseline = mode == '--installed-baseline'
            expected = '1.23.11+stereo3d2+lc1' if baseline else '1.23.11+stereo3d3+lc1'
            assert version == expected, version
            assert provides == ('dpkg-lean-code (= 1)' if baseline else 'dpkg-lean-code (= 2)'), provides
            stereo_version = subprocess.check_output(
                ['/usr/bin/dpkg-query', '-W', '-f=${Version}', 'dpkg-stereo'], text=True)
            assert stereo_version == ('0.1.30' if baseline else '0.1.32'), stereo_version
            return
        cls.status_path = Path('/var/lib/dpkg/status')
        cls.status = cls.status_path.read_text()
        stanzas = cls.status.split('\n\n')
        for n, stanza in enumerate(stanzas):
            if stanza.startswith('Package: dpkg\n'):
                lines = [line for line in stanza.splitlines() if not line.startswith('Provides:')]
                lines.append('Provides: dpkg-lean-code (= 2)')
                stanzas[n] = '\n'.join(lines)
                break
        else:
            raise AssertionError('fixture image has no dpkg package')
        cls.status_path.write_text('\n\n'.join(stanzas))

    @classmethod
    def tearDownClass(cls):
        CORE.write_bytes(cls.core)
        if not INSTALLED:
            cls.status_path.write_text(cls.status)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='order376-')
        self.work = Path(self.tmp.name)
        self.file = Path(PATH)
        CORE.write_bytes(self.core)
        self.packages = {}
        self.mk(PACKAGE, '1', PATH, ORIGINAL, conffile=True)
        self.mk(PACKAGE, '2', PATH, NEW, conffile=True)
        self.mk(RENDERER, '1', str(CORE), self.core)
        self.mk(RENDERER, '2', str(CORE), self.core + b'\nPOINTER_URL += "?renderer-upgrade"\n')
        result = self.invoke('-i', self.packages[(PACKAGE, '1')])
        self.assertEqual(result.returncode, 0, result.stdout.decode())
        self.assertEqual(self.file.read_bytes(), LEAN)
        self.assertNotIn('DPKG_LEAN_CODE_VERSION', os.environ)

    def tearDown(self):
        self.invoke('--force-remove-reinstreq', '-P', PACKAGE, RENDERER, hooks=False)
        CORE.write_bytes(self.core)
        for suffix in ('', '.dpkg-dist', '.dpkg-new', '.dpkg-old'):
            Path(PATH + suffix).unlink(missing_ok=True)
        stereo.clear_problem(stereo.Paths(), 'conffiles')
        Path('/var/lib/dpkg-stereo/conffile-events').write_bytes(b'')
        self.tmp.cleanup()

    def mk(self, package, version, path, data, conffile=False):
        root = self.work / (package + version)
        control = root / 'DEBIAN'
        control.mkdir(parents=True)
        (control / 'control').write_text(
            f'Package: {package}\nVersion: {version}\nArchitecture: all\n'
            'Maintainer: Daniel Campos Ramos <Capitain_Jack@yahoo.com>\n'
            'Description: isolated native conffile transaction fixture\n')
        if conffile:
            (control / 'conffiles').write_text(path + '\n')
        target = root / path.lstrip('/')
        target.parent.mkdir(parents=True)
        target.write_bytes(data)
        archive = self.work / (package + version + '.deb')
        subprocess.run(['/usr/bin/dpkg-deb', '--root-owner-group', '-b', str(root), str(archive)],
                       check=True, stdout=subprocess.DEVNULL)
        self.packages[(package, version)] = str(archive)

    def invoke(self, *args, hooks=True):
        env = dict(os.environ)
        env.pop('DPKG_LEAN_CODE_VERSION', None)
        env.pop('DPKG_STEREO_DISABLE', None)
        if not hooks:
            env['DPKG_STEREO_DISABLE'] = '1'
        cmd = [NATIVE, '--root=/', '--admindir=/var/lib/dpkg', '--force-unsafe-io', '--force-overwrite']
        if hooks and not INSTALLED:
            cmd += ['--pre-invoke=' + HOOK + ' --pre-invoke', '--post-invoke=' + HOOK + ' --post-invoke']
        result = subprocess.run(cmd + list(args), input=b'', stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=600, env=env)
        proof = Path(os.environ.get('ORDER376_PROOF_DIR', str(self.work))) / self._testMethodName
        proof.mkdir(parents=True, exist_ok=True)
        log = proof / ('call-' + str(len(list(proof.glob('call-*')))) + '.log')
        log.write_bytes(result.stdout)
        log.with_suffix('.exit').write_text(str(result.returncode) + '\n')
        return result

    def refusal(self, result, reason, suffix):
        self.assertEqual(self.file.read_bytes(), LEAN, result.stdout.decode())
        self.assertEqual(Path(PATH + suffix).read_bytes(), NEW)
        kept = next(p for p in stereo.kept_problems(stereo.Paths()) if p['step'] == 'conffiles')
        item = next(i for i in kept['items'] if i['package'] == PACKAGE)
        self.assertEqual(item['reason'], reason)
        self.assertIn(PATH + suffix, item['location'])
        self.assertIn(PACKAGE.encode(), result.stdout)
        self.assertIn((PATH + suffix).encode(), result.stdout)

    def test_unchanged_projection_upgrades_silently_and_projects_again(self):
        result = self.invoke('-i', self.packages[(PACKAGE, '2')])
        self.assertEqual(result.returncode, 0, result.stdout.decode())
        self.assertNotIn(b'Configuration file', result.stdout)
        self.assertEqual(self.file.read_bytes(), NEW_LEAN)
        self.assertFalse(any(p['step'] == 'conffiles' for p in stereo.kept_problems(stereo.Paths())))

    def test_split_unpack_configure_keeps_the_old_conffile_record(self):
        result = self.invoke('--unpack', self.packages[(PACKAGE, '2')])
        self.assertEqual(result.returncode, 0, result.stdout.decode())
        self.assertEqual(self.file.read_bytes(), LEAN)
        records = stereo.Records(stereo.Paths())
        self.assertEqual(records[PATH]['sha_orig'], hashlib.sha256(ORIGINAL).hexdigest())
        result = self.invoke('--configure', PACKAGE)
        self.assertEqual(result.returncode, 0, result.stdout.decode())
        self.assertNotIn(b'Configuration file', result.stdout)
        self.assertEqual(self.file.read_bytes(), NEW_LEAN)

    def test_remove_then_reinstall_does_not_prompt_for_projection(self):
        result = self.invoke('-r', PACKAGE)
        self.assertEqual(result.returncode, 0, result.stdout.decode())
        result = self.invoke('-i', self.packages[(PACKAGE, '2')])
        self.assertEqual(result.returncode, 0, result.stdout.decode())
        self.assertNotIn(b'Configuration file', result.stdout)
        self.assertEqual(self.file.read_bytes(), NEW_LEAN)

    def test_purge_after_unpack_removes_retained_conffile_records(self):
        result = self.invoke('--unpack', self.packages[(PACKAGE, '2')])
        self.assertEqual(result.returncode, 0, result.stdout.decode())
        self.assertIn(PATH, stereo.Records(stereo.Paths()))
        result = self.invoke('-P', PACKAGE)
        self.assertEqual(result.returncode, 0, result.stdout.decode())
        self.assertFalse(PATH in stereo.Records(stereo.Paths()), 'purged conffile still recorded')
        self.assertFalse(PATH in stereo.read_table('/var/lib/dpkg-stereo/conffiles.tsv', stereo.FILE_COLS),
                         'purged conffile still indexed')

    def test_renderer_changed_in_same_run_prompts_and_keeps_old_bytes(self):
        result = self.invoke('-i', self.packages[(RENDERER, '2')], self.packages[(PACKAGE, '2')])
        self.assertNotEqual(result.returncode, 0, result.stdout.decode())
        self.assertIn(b'conffile prompt', result.stdout)
        self.refusal(result, 13, '.dpkg-new')

    def test_renderer_changed_in_earlier_run_prompts_and_keeps_old_bytes(self):
        first = self.invoke('-i', self.packages[(RENDERER, '2')])
        self.assertEqual(first.returncode, 0, first.stdout.decode())
        self.assertEqual(self.file.read_bytes(), LEAN)
        result = self.invoke('-i', self.packages[(PACKAGE, '2')])
        self.assertNotEqual(result.returncode, 0, result.stdout.decode())
        self.refusal(result, 13, '.dpkg-new')

    def test_renderer_changed_conf_old_keeps_old_bytes_and_reports_dist(self):
        result = self.invoke('--force-confold', '-i', self.packages[(RENDERER, '2')],
                             self.packages[(PACKAGE, '2')])
        self.assertEqual(result.returncode, 0, result.stdout.decode())
        self.refusal(result, 13, '.dpkg-dist')

    def test_missing_verifier_prompts_and_reports(self):
        verifier = Path('/usr/lib/dpkg-stereo/conffile-verify')
        saved = verifier.read_bytes()
        try:
            verifier.unlink()
            result = self.invoke('-i', self.packages[(PACKAGE, '2')])
            self.assertNotEqual(result.returncode, 0, result.stdout.decode())
            self.refusal(result, 14, '.dpkg-new')
        finally:
            verifier.write_bytes(saved)
            verifier.chmod(0o755)

    def test_forged_projection_cannot_hide_edit_through_hooks(self):
        # Keep the size identical, so the old hook's size check cannot mask
        # its trust in a forged sha_lean before native dpkg sees the edit.
        edited = LEAN.replace(b'value=old', b'value=own')
        self.assertEqual(len(edited), len(LEAN))
        self.assertNotEqual(edited, LEAN)
        self.file.write_bytes(edited)
        records = stereo.Records(stereo.Paths())
        records[PATH] = dict(records[PATH], sha_lean=hashlib.sha256(edited).hexdigest())
        records.save()
        result = self.invoke('-i', self.packages[(PACKAGE, '2')])
        self.assertEqual(self.file.read_bytes(), edited, result.stdout.decode())
        self.assertNotEqual(result.returncode, 0, result.stdout.decode())
        self.assertEqual(Path(PATH + '.dpkg-new').read_bytes(), NEW)
        kept = next(p for p in stereo.kept_problems(stereo.Paths()) if p['step'] == 'conffiles')
        self.assertTrue(any(i['package'] == PACKAGE and i['reason'] == 13 for i in kept['items']))


if __name__ == '__main__':
    unittest.main(verbosity=2)
