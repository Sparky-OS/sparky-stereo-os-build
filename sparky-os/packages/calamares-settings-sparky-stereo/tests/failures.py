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
                    'grublanguage': (True, 300), 'offlineon': (False, 60), 'offlineoff': (True, 60),
                    'languagepacks': (True, 1800)}
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

    # ORDER 252c, J8: the language packs step. The chroot and the problems engine are stand-ins that record their calls.
    def language_fixture(self, lang, tool=True):
        (self.target / 'etc/default').mkdir(parents=True, exist_ok=True)
        (self.target / 'etc/default/locale').write_text(f'LANG={lang}\n')
        if tool:
            (self.target / 'usr/bin').mkdir(parents=True, exist_ok=True)
            (self.target / 'usr/bin/sparky-stereo-locales').write_text('#!/bin/sh\n')
            (self.target / 'usr/bin/sparky-stereo-locales').chmod(0o755)
        self.calls = self.root / 'calls'
        self.calls.write_text('')
        self.mock('sparky-stereo-problems', f'echo "ENGINE root=$SPARKY_STEREO_ROOT $*" >> {self.calls}')

    def mock_chroot(self, update=0, tool=0):
        # chroot ROOT env VAR... COMMAND ARG...: records the command and ends with the status the case wants
        self.mock('chroot', f'shift; shift; while case "$1" in *=*) shift;; *) false;; esac; do :; done; '
                            f'echo "CHROOT $*" >> {self.calls}; case "$1" in apt-get) exit {update};; *) exit {tool};; esac')

    def test_languagepacks_english_does_nothing(self):
        self.language_fixture('en_US.UTF-8')
        r = self.run_script('language-packs')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.calls.read_text(), '')

    def test_languagepacks_adds_the_chosen_language(self):
        self.language_fixture('de_DE.UTF-8')
        self.mock_chroot()
        r = self.run_script('language-packs')
        self.assertEqual(r.returncode, 0, r.stderr)
        calls = self.calls.read_text().splitlines()
        self.assertEqual(calls[0], 'CHROOT apt-get update')
        self.assertEqual(calls[1], 'CHROOT /usr/bin/sparky-stereo-locales --add system')
        self.assertIn('clear --machine sparky-stereo-locales add-system', calls[2])
        self.assertEqual(len(calls), 3, calls)

    def kept(self):
        lines = [l for l in self.calls.read_text().splitlines() if l.startswith('ENGINE') and ' keep ' in l]
        self.assertEqual(len(lines), 1, self.calls.read_text())
        self.assertIn(f'root={self.target}', lines[0])
        self.assertIn('--repair ["/usr/bin/sparky-stereo-locales","--add","system"]', lines[0])
        self.assertIn('sparky-stereo-locales add-system', lines[0])
        return lines[0]

    def test_languagepacks_tool_missing_is_kept_not_fatal(self):
        self.language_fixture('ja_JP.UTF-8', tool=False)
        r = self.run_script('language-packs')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('the Locale tool is not in the new system', self.kept())
        self.assertIn('the Locale tool is not in the new system', r.stderr)
        self.assertNotIn('CHROOT', self.calls.read_text())

    def test_languagepacks_no_network_is_kept_not_fatal(self):
        self.language_fixture('ja_JP.UTF-8')
        self.mock_chroot(update=100)
        r = self.run_script('language-packs')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('apt-get update ended with status 100', self.kept())
        self.assertNotIn('--add system', self.calls.read_text().split('ENGINE')[0])

    def test_languagepacks_tool_failure_is_kept_not_fatal(self):
        self.language_fixture('ko_KR.UTF-8')
        self.mock_chroot(tool=4)
        r = self.run_script('language-packs')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('ended with status 4', self.kept())

    def test_languagepacks_unkeepable_stops_the_installation(self):
        self.language_fixture('ko_KR.UTF-8')
        self.mock_chroot(tool=4)
        self.mock('sparky-stereo-problems', 'echo "engine failed" >&2; exit 1')
        r = self.run_script('language-packs')
        self.failed(r, 'language packages')

    def test_languagepacks_engine_missing_stops_the_installation(self):
        self.language_fixture('ko_KR.UTF-8')
        self.mock_chroot(tool=4)
        (self.bin / 'sparky-stereo-problems').unlink()
        # the engine may be installed on the machine that runs the test (the installer image has it): the path holds
        # every tool of /usr/bin except the engine, so the engine is missing whatever is installed
        shadow = self.root / 'usr-bin'
        shadow.mkdir()
        for tool in Path('/usr/bin').iterdir():
            if tool.name != 'sparky-stereo-problems':
                (shadow / tool.name).symlink_to(tool)
        self.env['PATH'] = f'{self.bin}:{shadow}'
        r = self.run_script('language-packs')
        self.failed(r, 'language packages')

    def test_languagepacks_missing_root_and_every_language(self):
        self.env['ROOT'] = str(self.root / 'absent')
        for lang in ('en', 'pl', 'pt_BR', 'fr', 'de', 'ja', 'ko', 'zh_CN', 'zh_TW'):
            with self.subTest(lang=lang):
                self.env['INSTALLER_LANG'] = lang + '.UTF-8'
                r = self.run_script('language-packs')
                self.assertNotEqual(r.returncode, 0)
                expected = (PACKAGE / 'lib/lang' / lang).read_text().split("LANGPACKS_ERROR='")[1].split("'\n")[0].replace("'\\''", "'")
                self.assertIn(expected, r.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
