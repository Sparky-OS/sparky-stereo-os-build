#!/usr/bin/env python3
"""Exercise the image check with package and module fixtures, without kernel access."""
import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('zfs_check', Path(__file__).resolve().parents[1] / 'zfs-check.py')
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)
KERNEL = '7.3.1-stereo3d14'


class ZfsImageCheck(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'var/lib/dpkg').mkdir(parents=True)
        (self.root / 'boot').mkdir()
        (self.root / 'boot' / f'vmlinuz-{KERNEL}').touch()
        self.packages = ['zfs-dkms', 'zfsutils-linux', 'zfs-zed', f'linux-headers-{KERNEL}']
        self.write_status()

    def write_status(self):
        (self.root / 'var/lib/dpkg/status').write_text(''.join(
            f'Package: {name}\nStatus: install ok installed\nVersion: 2.4.4\n\n'
            for name in self.packages))

    def modinfo(self, command, **kwargs):
        self.assertEqual(command[:3], ['modinfo', '-b', str(self.root)])
        self.assertEqual(command[3:7], ['-k', KERNEL, '-F', 'vermagic'])
        self.assertIn(command[7], ('spl', 'zfs'))
        return subprocess.CompletedProcess(command, 0, KERNEL + ' SMP preempt mod_unload\n', '')

    def test_complete_image(self):
        with patch.object(check.subprocess, 'run', side_effect=self.modinfo) as run:
            self.assertEqual(check.check(self.root), [])
            self.assertEqual(run.call_count, 2)

    def test_each_required_package_missing(self):
        for name in self.packages[:]:
            with self.subTest(name=name):
                old = self.packages[:]
                self.packages.remove(name)
                self.write_status()
                with patch.object(check.subprocess, 'run', side_effect=self.modinfo):
                    self.assertTrue(check.check(self.root))
                self.packages = old

    def test_unconfigured_zfs(self):
        p = self.root / 'var/lib/dpkg/status'
        p.write_text(p.read_text().replace('install ok installed', 'install ok half-configured', 1))
        with patch.object(check.subprocess, 'run', side_effect=self.modinfo):
            self.assertIn('zfs-dkms is missing or not configured', check.check(self.root))

    def test_missing_modules_and_failed_inspector(self):
        for error in (FileNotFoundError('modinfo missing'), subprocess.CalledProcessError(1, ['modinfo'], stderr='Module zfs not found')):
            with self.subTest(error=error), patch.object(check.subprocess, 'run', side_effect=error):
                errors = check.check(self.root)
                self.assertEqual(len(errors), 2)
                self.assertTrue(all('cannot inspect' in e for e in errors))

    def test_wrong_or_empty_module_vermagic(self):
        for value in ('7.2.0-stereo3d13 SMP', ''):
            with self.subTest(value=value), patch.object(check.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, value, '')):
                self.assertEqual(len(check.check(self.root)), 2)

    def test_each_kernel_checked(self):
        (self.root / 'boot/vmlinuz-7.3.1-stereo3d14-v3').touch()
        def inspect(command, **kwargs):
            if command[4] != KERNEL:
                raise subprocess.CalledProcessError(1, command, stderr='Module not found')
            return self.modinfo(command, **kwargs)
        with patch.object(check.subprocess, 'run', side_effect=inspect) as run:
            errors = check.check(self.root)
            self.assertEqual(run.call_count, 4)
            self.assertEqual(len(errors), 3)
            self.assertTrue(all('7.3.1-stereo3d14-v3' in error for error in errors))

    def test_missing_kernel_or_status(self):
        (self.root / 'boot' / f'vmlinuz-{KERNEL}').unlink()
        self.assertIn('no kernel image found in /boot', check.check(self.root))
        (self.root / 'var/lib/dpkg/status').unlink()
        self.assertIn('cannot read installed package status', check.check(self.root)[0])


if __name__ == '__main__':
    unittest.main()
