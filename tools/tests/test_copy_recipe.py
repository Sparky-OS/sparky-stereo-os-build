#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / 'copy-recipe.py'


class CopyRecipe(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.src = self.root / 'source'
        self.src.mkdir()
        self.dst = self.root / 'dest'

    def write(self, name, data='tracked\n'):
        path = self.src / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        return path

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.src), *args], check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def track(self):
        self.git('init', '-q')
        self.git('add', '.')

    def copy(self, ok=True, **kwargs):
        result = subprocess.run([sys.executable, str(HELPER), str(self.src), str(self.dst)],
                                capture_output=True, text=True, **kwargs)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result

    def names(self):
        return {str(p.relative_to(self.dst)) for p in self.dst.rglob('*')
                if p.is_symlink() or p.is_file()}

    def test_tracked_working_bytes_modes_and_names(self):
        names = {'bin/a b', 'test/new\nline', '.hidden', '-option', 'lib/x'}
        for name in names:
            self.write(name)
        self.write('bin/run').chmod(0o755)
        (self.src / 'link').symlink_to('missing-target')
        self.track()
        self.write('lib/x', 'working change\n')
        for name in ('untracked', 'bin/__pycache__/x.pyc', 'test/__pycache__/x', 'lib/stray.pyc'):
            self.write(name, 'must not ship\n')
        self.assertIn('files as git tracks them', self.copy().stdout)
        self.assertEqual(self.names(), names | {'bin/run', 'link'})
        self.assertEqual((self.dst / 'lib/x').read_bytes(), b'working change\n')
        self.assertEqual((self.dst / 'bin/run').stat().st_mode & 0o777, 0o755)
        self.assertEqual(os.readlink(self.dst / 'link'), 'missing-target')

    def test_export(self):
        self.write('payload')
        self.write('bin/__pycache__/cached')
        self.write('lib/stray.pyc')
        (self.src / 'link').symlink_to('payload')
        self.assertIn('no git work tree', self.copy().stdout)
        self.assertEqual(self.names(), {'payload', 'link'})

    def test_missing_git(self):
        self.write('payload')
        result = self.copy(False, env=os.environ | {'PATH': '/nonexistent'})
        self.assertIn('git', result.stderr)
        self.assertFalse(self.dst.exists())

    def test_broken_git(self):
        self.write('payload')
        self.write('.git', 'gitdir: /nonexistent\n')
        self.copy(False)
        self.assertFalse(self.dst.exists())

    def test_missing_tracked_file(self):
        self.write('payload')
        self.track()
        (self.src / 'payload').unlink()
        self.copy(False)
        self.assertFalse(self.dst.exists())

    def test_tracked_directory_replacement(self):
        self.write('payload')
        self.track()
        (self.src / 'payload').unlink()
        self.write('payload/private')
        self.copy(False)
        self.assertFalse(self.dst.exists())

    def test_symlink_directory_replacement(self):
        self.write('dir/payload')
        self.track()
        (self.src / 'dir').rename(self.root / 'outside')
        (self.src / 'dir').symlink_to(self.root / 'outside')
        self.copy(False)
        self.assertFalse(self.dst.exists())

    def test_unreadable(self):
        self.assertNotEqual(os.getuid(), 0, 'run this proof as a regular build user')
        path = self.write('payload')
        self.track()
        path.chmod(0)
        self.addCleanup(path.chmod, 0o644)
        self.assertIn('Permission denied', self.copy(False).stderr)

    def test_submodule_not_recursively_copied(self):
        self.write('payload')
        self.track()
        self.git('update-index', '--add', '--cacheinfo',
                 '160000,0123456789012345678901234567890123456789,submodule')
        self.write('submodule/private')
        self.copy(False)
        self.assertFalse(self.dst.exists())

    def test_git_inventory_failure(self):
        self.write('payload')
        self.track()
        shim = self.root / 'bin'
        shim.mkdir()
        path = shim / 'git'
        path.write_text('#!/bin/sh\nif [ "$3" = rev-parse ]; then echo true; exit 0; fi\necho "index unreadable" >&2\nexit 1\n')
        path.chmod(0o755)
        self.assertIn('index unreadable', self.copy(False, env=os.environ | {'PATH': str(shim)}).stderr)
        self.assertFalse(self.dst.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
