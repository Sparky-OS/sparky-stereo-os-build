#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Run as root in a disposable container with the candidate verifier/toolkit installed.

No dpkg binary is substituted here: these are verifier boundary tests. The native
functional suite separately checks when dpkg calls it and its fallback decisions.
"""

import hashlib
import lzma
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, '/usr/lib/dpkg-stereo')
from lean import project

HELPER = '/usr/lib/dpkg-stereo/conffile-verify'
LIB = Path('/usr/lib/dpkg-stereo/lean')
PACKAGE = 'order376-probe'
PATH = '/etc/default/order376'
ORIGINAL = b'# Explanation of the distributed setting.\n' * 20 + b'value=old\n'
sha = lambda data: hashlib.sha256(data).hexdigest()
MD5 = hashlib.md5(ORIGINAL).hexdigest()
LEAN = project.project(PATH, ORIGINAL, PACKAGE, check=False).lean
assert LEAN is not None


class VerifierTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.work = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def invoke(self, original=ORIGINAL, current=LEAN, package=PACKAGE, path=PATH,
               md5=MD5, original_sha=None, lean_sha=None, compressed=None, env=None):
        cache = self.work / 'original.xz'
        cache.write_bytes(lzma.compress(original) if compressed is None else compressed)
        installed = self.work / 'installed'
        installed.write_bytes(current)
        with cache.open('rb') as orig, installed.open('rb') as cur:
            return subprocess.run([HELPER, package, path, md5, original_sha or sha(original),
                                   lean_sha or sha(current), str(cur.fileno())], stdin=orig,
                                  pass_fds=(cur.fileno(),), stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, timeout=15, env=env)

    def expect(self, code, **kwargs):
        result = self.invoke(**kwargs)
        self.assertEqual(result.returncode, code, result.stderr.decode())
        self.assertEqual(result.stdout, b'')
        return result

    def test_real_projection(self):
        self.expect(0)

    def test_multiarch_package_uses_own_name_without_architecture_in_pointer(self):
        self.expect(0, package=PACKAGE + ':amd64')

    def test_forged_sha_lean_does_not_hide_edit(self):
        edited = LEAN.replace(b'value=old', b'value=personal')
        self.expect(13, current=edited, lean_sha=sha(edited))

    def test_forged_original_does_not_replace_owning_md5(self):
        edited = ORIGINAL.replace(b'value=old', b'value=personal')
        self.expect(10, original=edited, original_sha=sha(edited))

    def test_md5_and_sha_original_are_both_checked(self):
        self.expect(10, md5='0' * 32)
        self.expect(10, original_sha='0' * 64)

    def test_current_bytes_are_rechecked(self):
        self.expect(11, lean_sha='0' * 64)

    def test_package_and_path_select_the_projection(self):
        self.expect(13, package='another-package')
        self.expect(12, path='/etc/apt/order376.conf')

    def test_old_output_is_refused(self):
        older = project.project(PATH, ORIGINAL, PACKAGE, pointer=False, check=False).lean
        self.assertIsNotNone(older)
        self.expect(13, current=older)

    def test_changed_renderer_is_read_on_next_call(self):
        self.expect(0)
        source = LIB / 'core.py'
        saved = source.read_bytes()
        try:
            source.write_bytes(saved + b'\nPOINTER_URL += "?changed-renderer"\n')
            self.expect(13)
        finally:
            source.write_bytes(saved)
        self.expect(0)

    def test_corrupt_and_truncated_cache(self):
        self.expect(12, compressed=b'not an xz stream')
        self.expect(12, compressed=lzma.compress(ORIGINAL)[:-5])

    def test_size_limit(self):
        self.expect(12, original=b'x' * ((4 << 20) + 1))

    def test_untrusted_renderer_mode_and_owner(self):
        source = LIB / 'conffile.py'
        info = source.stat()
        try:
            source.chmod(0o666)
            self.expect(14)
            source.chmod(0o644)
            os.chown(source, 1000, 1000)
            self.expect(14)
        finally:
            os.chown(source, info.st_uid, info.st_gid)
            source.chmod(info.st_mode & 0o7777)

    def test_renderer_symlink_refused(self):
        source = LIB / 'conffile.py'
        saved = source.read_bytes()
        target = self.work / 'replacement.py'
        target.write_bytes(saved)
        try:
            source.unlink()
            source.symlink_to(target)
            self.expect(14)
        finally:
            source.unlink()
            source.write_bytes(saved)
            source.chmod(0o644)

    def test_environment_cannot_supply_python_code(self):
        marker = self.work / 'executed'
        (self.work / 'sitecustomize.py').write_text(f'open({str(marker)!r}, "w").close()\n')
        self.expect(0, env=dict(os.environ, PYTHONPATH=str(self.work)))
        self.assertFalse(marker.exists())

    def test_render_cannot_write_or_start_a_process(self):
        source = LIB / 'project.py'
        saved = source.read_bytes()
        marker = self.work / 'written'
        for action in (f'open({str(marker)!r}, "w")',
                       '__import__("subprocess").run(["/usr/bin/true"])'):
            try:
                source.write_bytes(saved + ('\ndef project(*args, **kwargs):\n    ' + action + '\n').encode())
                result = self.expect(12)
                self.assertIn(b'PermissionError', result.stderr)
                self.assertFalse(marker.exists())
            finally:
                source.write_bytes(saved)

    def test_invalid_request(self):
        self.expect(15, package='../other')
        self.expect(15, path='relative/path')
        self.expect(15, md5='wrong')


if __name__ == '__main__':
    unittest.main(verbosity=2)
