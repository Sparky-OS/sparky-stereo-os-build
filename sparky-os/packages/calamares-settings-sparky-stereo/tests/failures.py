#!/usr/bin/env python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
"""Installer failure injection; every external probe/write stays inside a fixture.

SUBJECT selects an unmodified baseline or an extracted installed package adapter.
The shellprocess checks validate the upstream CommandList configuration contract;
they do not claim to exercise Calamares' GUI.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml

PACKAGE = Path(os.environ.get('SUBJECT', Path(__file__).resolve().parents[1]))


class InstallerFailures(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.esp = self.root / 'esp'
        self.src = self.esp / 'EFI/sparky'
        self.src.mkdir(parents=True)
        self.fw = self.root / 'firmware'
        self.fw.mkdir()
        self.target = self.root / 'target'
        self.target.mkdir()
        for name in ('shimx64.efi', 'grubx64.efi', 'mmx64.efi', 'grub.cfg'):
            (self.src / name).write_text('signed fixture ' + name)
        self.env = dict(os.environ, PATH=f'{self.bin}:/usr/bin:/bin',
                        INSTALLER_LANG='en', ESP=str(self.esp), EFI_FIRMWARE=str(self.fw),
                        ROOT=str(self.target), TARGET='/dev/test-root',
                        OS_PROBER=str(self.bin / 'os-prober'), ADJTIME=str(self.root / 'adjtime'),
                        GRUBD=str(self.root / 'grub.d'), OFFLINE=str(self.root / 'offline'),
                        APT_DIR=str(self.root / 'apt'), LISTS=str(self.root / 'lists'))
        self.mock('os-prober', 'exit 0')
        self.mock('findmnt', 'case "$*" in *FSTYPE*) echo vfat;; *) echo /dev/test-root;; esac')
        self.mock('hwclock', 'echo "UNEXPECTED HWCLOCK" >&2; exit 99')
        self.mock('chroot', 'echo "UNEXPECTED CHROOT" >&2; exit 99')

    def mock(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\n' + body + '\n')
        path.chmod(0o755)

    def run_script(self, name, *args):
        return subprocess.run([str(PACKAGE / 'lib' / name), *args], env=self.env,
                              text=True, capture_output=True, timeout=10)

    def failed(self, result, message):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(message, result.stderr)
        self.assertIn('restart the installer', result.stderr)
        self.assertNotIn('holds shim, GRUB and MokManager', result.stdout)

    def no_boot(self):
        self.assertFalse((self.esp / 'EFI/BOOT').exists())

    def test_U01_shellprocess_contract(self):
        expected = {'dualboot': (False, 120), 'efifallback': (True, 120),
                    'grublanguage': (True, 300), 'offlineon': (False, 60), 'offlineoff': (True, 60)}
        for name, (host, timeout) in expected.items():
            with self.subTest(name=name):
                conf = yaml.safe_load((PACKAGE / f'etc/modules/shellprocess-{name}.conf').read_text())
                self.assertEqual(conf['dontChroot'], host)
                self.assertEqual(conf['timeout'], timeout)
                self.assertEqual(len(conf['script']), 1)
                self.assertFalse(conf['script'][0].startswith('-'), 'Calamares suppresses this failure')
                self.assertIn('INSTALLER_LANG=${LANG}', conf['script'][0])

    def test_U02_absent_esp(self):
        self.env['ESP'] = str(self.root / 'missing')
        self.failed(self.run_script('efi-fallback'), 'EFI System Partition')
        self.no_boot()

    def test_U02_unmounted_esp(self):
        self.mock('findmnt', 'echo "not mounted" >&2; exit 1')
        self.failed(self.run_script('efi-fallback'), 'not mounted')
        self.no_boot()

    def test_U02_wrong_filesystem(self):
        self.mock('findmnt', 'echo ext4')
        self.failed(self.run_script('efi-fallback'), 'FSTYPE=ext4')
        self.no_boot()

    def test_U02_missing_loaders(self):
        for name in ('shimx64.efi', 'grubx64.efi', 'mmx64.efi', 'grub.cfg'):
            with self.subTest(name=name):
                f = self.src / name
                old = f.read_bytes()
                f.unlink()
                self.failed(self.run_script('efi-fallback'), name)
                self.no_boot()
                f.write_bytes(old)

    def test_U03_copy_failure(self):
        dst = self.esp / 'EFI/BOOT'
        dst.mkdir()
        old = dst / 'BOOTX64.EFI'
        old.write_text('old loader')
        self.mock('cp', 'echo "injected read-only filesystem" >&2; exit 30')
        self.failed(self.run_script('efi-fallback'), 'injected read-only filesystem')
        self.assertEqual(old.read_text(), 'old loader')

    def test_U03_short_write(self):
        self.mock('cp', ': > "$2"')
        self.failed(self.run_script('efi-fallback'), 'cmp')

    def test_U03_mkdir_failure(self):
        self.mock('mkdir', 'echo "injected disk full" >&2; exit 28')
        self.failed(self.run_script('efi-fallback'), 'injected disk full')
        self.no_boot()

    def test_U03_rename_failure(self):
        self.mock('mv', 'echo "injected rename error" >&2; exit 5')
        self.failed(self.run_script('efi-fallback'), 'injected rename error')

    def test_U03_flush_failure(self):
        self.mock('sync', 'echo "injected flush error" >&2; exit 5')
        self.failed(self.run_script('efi-fallback'), 'injected flush error')

    def test_U04_failed_detection(self):
        for script in ('dual-boot', 'efi-fallback'):
            with self.subTest(script=script):
                self.mock('os-prober', 'echo "probe permission denied" >&2; exit 7')
                self.failed(self.run_script(script), 'probe permission denied')
                self.assertFalse((self.root / 'adjtime').exists())
                self.no_boot()

    def test_U04_partial_failed_detection(self):
        self.mock('os-prober', 'echo /dev/test:Windows:Windows:efi; echo "probe I/O error" >&2; exit 8')
        for script in ('dual-boot', 'efi-fallback'):
            with self.subTest(script=script):
                self.failed(self.run_script(script), 'probe I/O error')
                self.assertFalse((self.root / 'adjtime').exists())
                self.no_boot()

    def test_U04_failed_root_detection(self):
        self.env['TARGET'] = ''
        self.mock('findmnt', 'case "$*" in *FSTYPE*) echo vfat;; *) echo "root probe failed" >&2; exit 4;; esac')
        self.failed(self.run_script('efi-fallback'), 'root probe failed')
        self.no_boot()

    def test_U04_failed_directory_read(self):
        self.mock('find', 'echo "ESP read error" >&2; exit 1')
        self.failed(self.run_script('efi-fallback'), 'ESP read error')
        self.no_boot()

    def test_U04_dualboot_write_failure(self):
        self.mock('os-prober', 'echo /dev/test:Windows:Windows:efi')
        self.env['ADJTIME'] = str(self.root / 'absent/adjtime')
        self.failed(self.run_script('dual-boot'), 'adjtime')

    def test_U05_missing_index(self):
        self.failed(self.run_script('offline-packages', 'on'), 'Offline installation packages')
        self.assertFalse((self.root / 'apt').exists())

    def test_U05_empty_or_invalid_index(self):
        offline = self.root / 'offline'
        offline.mkdir()
        for data in ('', 'not an index\n'):
            with self.subTest(data=data):
                (offline / 'Packages').write_text(data)
                self.failed(self.run_script('offline-packages', 'on'), 'Offline installation packages')
                self.assertFalse((self.root / 'apt').exists())

    def test_U05_source_write_failure(self):
        offline = self.root / 'offline'
        offline.mkdir()
        (offline / 'Packages').write_text('Package: grub-efi-amd64\n')
        source = self.root / 'apt/sources.list.d/sparky-stereo-offline.sources'
        source.mkdir(parents=True)
        self.failed(self.run_script('offline-packages', 'on'), 'sparky-stereo-offline.sources')

    def test_U05_cleanup_failure(self):
        self.mock('rm', 'echo "injected cleanup error" >&2; exit 9')
        self.failed(self.run_script('offline-packages', 'off'), 'injected cleanup error')

    def test_grub_language_missing_target(self):
        self.env['ROOT'] = str(self.root / 'absent')
        self.failed(self.run_script('grub-language'), 'boot menu language')

    def test_all_localized_errors(self):
        for lang in ('en', 'pl', 'pt_BR', 'fr', 'de', 'ja', 'ko', 'zh_CN', 'zh_TW'):
            with self.subTest(lang=lang):
                self.env['INSTALLER_LANG'] = lang + '.UTF-8'
                r = self.run_script('offline-packages', 'on')
                self.assertNotEqual(r.returncode, 0)
                self.assertIn('Packages', r.stderr)
                expected = (PACKAGE / 'lib/lang' / lang).read_text().split("OFFLINE_ERROR='")[1].split("'\n")[0]
                self.assertIn(expected, r.stderr)

    def test_success_controls(self):
        # A successful empty probe is different from a failed probe.
        self.assertEqual(self.run_script('dual-boot').returncode, 0)
        self.assertFalse((self.root / 'adjtime').exists())
        r = self.run_script('efi-fallback')
        self.assertEqual(r.returncode, 0, r.stderr)
        for src, dst in (('shimx64.efi', 'BOOTX64.EFI'), ('grubx64.efi', 'grubx64.efi'),
                         ('mmx64.efi', 'mmx64.efi'), ('grub.cfg', 'grub.cfg')):
            self.assertEqual((self.src / src).read_bytes(), (self.esp / 'EFI/BOOT' / dst).read_bytes())

    def test_bios_control(self):
        self.env['EFI_FIRMWARE'] = str(self.root / 'bios')
        self.mock('os-prober', 'exit 99')
        self.assertEqual(self.run_script('efi-fallback').returncode, 0)
        self.no_boot()

    def test_windows_preservation_control(self):
        self.mock('os-prober', 'echo /dev/windows:Windows:Windows:efi')
        dst = self.esp / 'EFI/Boot'
        dst.mkdir()
        (dst / 'bootx64.efi').write_text('Windows loader')
        self.assertEqual(self.run_script('efi-fallback').returncode, 0)
        self.assertEqual(list(dst.iterdir()), [dst / 'bootx64.efi'])
        self.assertEqual((dst / 'bootx64.efi').read_text(), 'Windows loader')


if __name__ == '__main__':
    unittest.main(verbosity=2)
