#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/30
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/30
"""Tests for old-kernels.py and for pack.sh's lines that use it (cut out of pack.sh and run on a fake root with
inr and apt_in as stubs): the ISO keeps only the kernel linux-image-sparky-stereo depends on.
Needs python3 and sh. Run: python3 sparky-os/iso-build/tests/test_old_kernels.py
"""
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.dirname(HERE)
K13, K14 = '7.3.0-stereo3d13', '7.3.1-stereo3d14'


def stanza(package, version='1', status='install ok installed'):
    return 'Package: %s\nStatus: %s\nVersion: %s\n' % (package, status, version)


class OldKernels(unittest.TestCase):

    def root(self, stanzas, trees=(), boot=()):
        t = tempfile.mkdtemp(prefix='old-kernels-')
        self.addCleanup(subprocess.run, ['rm', '-rf', t])
        os.makedirs(os.path.join(t, 'var/lib/dpkg'))
        with open(os.path.join(t, 'var/lib/dpkg/status'), 'w') as f:
            f.write('\n'.join(stanzas) + '\n')
        for r in trees:
            os.makedirs(os.path.join(t, 'usr/lib/modules', r, 'kernel'))
        os.makedirs(os.path.join(t, 'boot'), exist_ok=True)
        for r in boot:
            open(os.path.join(t, 'boot', 'vmlinuz-' + r), 'w').close()
        os.makedirs(os.path.join(t, 'tmp'))
        return t

    def select(self, root, keep):
        r = subprocess.run([sys.executable, os.path.join(BUILD, 'old-kernels.py'), root, keep], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.split()

    def test_one_kernel_prints_nothing(self):
        root = self.root([stanza('linux-image-' + K13), stanza('linux-headers-' + K13), stanza('linux-image-sparky-stereo')])
        self.assertEqual(self.select(root, K13), [])

    def test_the_older_kernel_and_its_companions(self):
        root = self.root([stanza('linux-image-' + K13), stanza('linux-headers-' + K13), stanza('linux-headers-%s-lc-hr' % K13),
                          stanza('linux-image-' + K14), stanza('linux-headers-' + K14), stanza('linux-headers-%s-lc-hr' % K14),
                          stanza('linux-image-sparky-stereo'), stanza('linux-headers-sparky-stereo'), stanza('linux-libc-dev'),
                          stanza('linux-image-7.2.12+deb14-amd64'), stanza('linux-base')])
        self.assertEqual(self.select(root, K14), ['linux-headers-' + K13, 'linux-headers-%s-lc-hr' % K13, 'linux-image-' + K13])

    def test_other_flavours_rc_releases_and_configuration_files(self):
        root = self.root([stanza('linux-image-' + K14), stanza('linux-image-7.3.0-rt-stereo3d13'),
                          stanza('linux-image-7.3.0-stereo3d13-v3'),
                          stanza('linux-image-7.3.0-rc6-stereo3d12', status='deinstall ok config-files'),
                          stanza('linux-image-7.3.0-rc5-stereo3d11', status='purge ok not-installed')])
        self.assertEqual(self.select(root, K14), ['linux-image-7.3.0-rc6-stereo3d12', 'linux-image-7.3.0-rt-stereo3d13',
                                                  'linux-image-7.3.0-stereo3d13-v3'])

    def pack_block(self):
        with open(os.path.join(BUILD, 'pack.sh')) as f:
            text = f.read()
        start = text.index('\t# the ISO ships one kernel (ORDER 297)')
        end = text.index('\n\tfi\n', start) + len('\n\tfi\n')
        return text[start:end]

    def run_block(self, root, kv):
        log = os.path.join(root, 'apt.log')
        script = ('R=%s; KV=%s\n'
                  'inr() { python3 "$R$2" "$R" "$4"; }\n'
                  'apt_in() { echo "$*" >> %s; }\n' % (root, kv, log))
        block = self.pack_block().replace('cp /build/old-kernels.py', 'cp %s/old-kernels.py' % BUILD)
        r = subprocess.run(['sh', '-ec', script + block], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        if not os.path.exists(log):
            return '', r.stdout
        with open(log) as f:
            return f.read(), r.stdout

    def test_pack_purges_the_older_kernel_and_its_module_tree(self):
        root = self.root([stanza('linux-image-' + K13), stanza('linux-headers-' + K13), stanza('linux-image-' + K14),
                          stanza('linux-headers-' + K14)], trees=(K13, K14), boot=(K14,))
        apt, out = self.run_block(root, K14)
        self.assertEqual(apt.strip(), 'purge linux-headers-%s linux-image-%s' % (K13, K13))
        self.assertIn('older edition kernels, purged: linux-headers-%s linux-image-%s' % (K13, K13), out)
        self.assertFalse(os.path.exists(os.path.join(root, 'usr/lib/modules', K13)))
        self.assertTrue(os.path.isdir(os.path.join(root, 'usr/lib/modules', K14)))
        self.assertFalse(os.path.exists(os.path.join(root, 'tmp/old-kernels.py')))

    def test_pack_with_one_kernel_changes_nothing(self):
        root = self.root([stanza('linux-image-' + K13), stanza('linux-headers-' + K13)], trees=(K13,), boot=(K13,))
        apt, out = self.run_block(root, K13)
        self.assertEqual(apt, '')
        self.assertTrue(os.path.isdir(os.path.join(root, 'usr/lib/modules', K13)))


if __name__ == '__main__':
    unittest.main(verbosity=2)
