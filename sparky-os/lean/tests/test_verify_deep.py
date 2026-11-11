"""dpkg-stereo --verify --deep on a healthy system (ORDER 398): what is information and what stays a counted problem.

The program is read from DPKG_STEREO_BIN (default: this tree's), so the same file runs red on an older one.
Each case builds a small root, then runs verify() with the database readers standing in for dpkg's files."""

import contextlib
import hashlib
import importlib.machinery
import importlib.util
import io
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from lean import project  # noqa: E402

TREE = Path(__file__).resolve().parents[2]
BIN = Path(os.environ.get('DPKG_STEREO_BIN') or TREE / 'packages/dpkg-stereo/bin/dpkg-stereo')
LANGS = TREE / 'packages/dpkg-stereo/lang'
os.environ.setdefault('DPKG_STEREO_LANG_DIR', str(LANGS))
sha = lambda b: hashlib.sha256(b).hexdigest()  # noqa: E731
md5 = lambda b: hashlib.md5(b).hexdigest()  # noqa: E731
PATH = '/usr/bin/demo'
SHELL = ('#!/bin/sh\n' + '# a line of commentary, long enough that the projection is worth its pointer line\n' * 6
         + 'echo demo\n').encode()


def load():
    loader = importlib.machinery.SourceFileLoader('dpkg_stereo_verify_398', str(BIN))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class Case(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='verify-deep-398-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.m = load()
        self.lean = project.project(PATH, SHELL, 'demo', check=False).lean
        self.assertIsNotNone(self.lean)

    def put(self, path, data):
        target = self.root / path.lstrip('/')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)

    def run_verify(self, installed, deep=True, rows=(), listed=(PATH,), sums=None, conffile='0', record_lean=None):
        """installed: the bytes of PATH on disk; rows: manifest rows [(path, status, kind, sha)] of the lc1 package."""
        m = self.m
        P = m.Paths(str(self.root))
        self.put(PATH, installed)
        rec = {'path': PATH, 'package': 'demo', 'version': '1.0', 'conffile': conffile, 'sha_orig': sha(SHELL),
               'md5_orig': md5(SHELL), 'sha_lean': record_lean or sha(installed), 'handler': 'shell', 'variant': '',
               'bytes_orig': '0', 'bytes_lean': '0'}
        manifest = {'files': [{'path': p, 'status': s, 'kind': 'file', 'sha256': h} for p, s, h in rows]}
        fake_lc = types.SimpleNamespace(
            installed=lambda P, names=None: {'demo': manifest},
            file_hash=lambda path: sha(open(path, 'rb').read()))
        patches = [
            mock.patch.object(m, 'Records', lambda P, kind='records', pkgs=None: {PATH: rec} if kind == 'records' else {}),
            mock.patch.object(m, 'dpkg_db', lambda P, files=None: {}),
            mock.patch.object(m, 'conffiles', lambda P, db=None: {'demo': {PATH: md5(SHELL)} if conffile == '1' else {}}),
            mock.patch.object(m, 'dpkg_packages', lambda P, db=None: {'demo': ('1.0', 'demo')}),
            mock.patch.object(m, '_installed', lambda P, db, states=None: iter([('demo', {'Version': '1.0', 'Conffiles': {}})])),
            mock.patch.object(m, 'package_files', lambda P, info: list(listed)),
            mock.patch.object(m, 'md5sums', lambda P, info: {PATH: md5(SHELL)} if sums is None else sums),
            mock.patch.object(m, 'deb_members', lambda *a, **k: {PATH: SHELL}),
            mock.patch.object(m, 'pending_c_paths', lambda P: {}),
            mock.patch.object(m, 'lc_package', fake_lc),
            mock.patch.object(m, 'load_pristine', lambda P, h: SHELL),
        ]
        out = io.StringIO()
        with contextlib.ExitStack() as stack:
            for p in patches:
                stack.enter_context(p)
            with contextlib.redirect_stdout(out):
                rc = m.verify(P, [], deep=deep)
        return rc, out.getvalue()

    def other_row(self, name, status, original, installed):
        self.put(name, installed)
        return (name, status, sha(original))

    # an earlier renderer's form -------------------------------------------------------------------------------
    def old_form(self):
        old = self.lean + b'\n'
        self.assertNotEqual(old, self.lean)
        return old

    def test_earlier_renderer_form_is_information(self):
        rc, out = self.run_verify(self.old_form())
        self.assertIn('OLDFORM   ' + PATH, out)
        self.assertNotIn('MISMATCH', out)
        self.assertIn('0 problems', out)
        self.assertEqual(rc, 0, out)

    def test_earlier_renderer_form_not_taken_by_restore_stays_counted(self):
        # the owning package does not list the path: restore would refuse it, so the problem is counted
        rc, out = self.run_verify(self.old_form(), listed=())
        self.assertIn('MISMATCH  ' + PATH, out)
        self.assertNotIn('OLDFORM', out)
        self.assertEqual(rc, 1, out)

    def test_changed_projection_stays_counted(self):
        installed = self.old_form()
        rc, out = self.run_verify(installed, record_lean=sha(self.lean))
        self.assertIn('CHANGED   ' + PATH, out)
        self.assertEqual(rc, 1, out)

    def test_exact_projection_is_clean(self):
        rc, out = self.run_verify(self.lean)
        self.assertEqual(rc, 0, out)
        self.assertNotIn('OLDFORM', out)

    def test_a_conffile_needs_the_exact_render(self):
        rc, out = self.run_verify(self.old_form(), conffile='1')
        self.assertIn('MISMATCH  ' + PATH, out)
        self.assertNotIn('OLDFORM', out)
        self.assertEqual(rc, 1, out)

    def test_not_deep_does_not_say_oldform(self):
        rc, out = self.run_verify(self.old_form(), deep=False)
        self.assertNotIn('OLDFORM', out)
        self.assertEqual(rc, 0, out)

    # rows dpkg-stereo did not project ---------------------------------------------------------------------------
    def test_rewritten_row_that_was_not_projected_is_information(self):
        row = self.other_row('/lib/modules/7.3/modules.dep', 'left', b'old\n', b'depmod rewrote it\n')
        rc, out = self.run_verify(self.lean, rows=[row])
        self.assertIn('AFTERINST /lib/modules/7.3/modules.dep', out)
        self.assertNotIn('LCCHANGED', out)
        self.assertIn('1 files dpkg-stereo did not project', out)
        self.assertEqual(rc, 0, out)

    def test_projected_row_that_changed_stays_counted(self):
        row = self.other_row('/usr/bin/other', 'projected', b'old\n', b'edited\n')
        rc, out = self.run_verify(self.lean, rows=[row])
        self.assertIn('LCCHANGED /usr/bin/other', out)
        self.assertNotIn('AFTERINST', out)
        self.assertEqual(rc, 1, out)

    def test_missing_row_that_was_not_projected_stays_counted(self):
        rc, out = self.run_verify(self.lean, rows=[('/etc/gone', 'left', sha(b'x\n'))])
        self.assertIn('LCCHANGED /etc/gone', out)
        self.assertEqual(rc, 1, out)

    def test_intact_rows_say_nothing(self):
        self.put('/etc/same', b'same\n')
        rc, out = self.run_verify(self.lean, rows=[('/etc/same', 'left', sha(b'same\n'))])
        self.assertNotIn('AFTERINST', out)
        self.assertEqual(rc, 0, out)

    def test_information_never_hides_a_problem(self):
        row = self.other_row('/lib/modules/7.3/modules.dep', 'left', b'old\n', b'depmod rewrote it\n')
        rc, out = self.run_verify(self.old_form(), rows=[row], listed=())
        self.assertIn('AFTERINST', out)
        self.assertEqual(rc, 1, out)

    def test_messages_in_every_language(self):
        for lang in ('en', 'de', 'es', 'fr', 'ja', 'ko', 'pl', 'pt_BR', 'zh_CN', 'zh_TW'):
            for key in ('LOCAL77', 'LOCAL78', 'LOCAL79', 'LOCAL80'):
                self.assertIn(key + '="', (LANGS / lang).read_text(encoding='utf-8'), (lang, key))
                self.assertEqual(self.m.text(key, [3] if key in ('LOCAL79', 'LOCAL80') else [], lang).count('%s'), 0)


if __name__ == '__main__':
    unittest.main()
