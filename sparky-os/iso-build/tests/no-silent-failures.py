#!/usr/bin/env python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
"""Run the packer's actual offline block with stubbed image commands, and base-list.
SUBJECT selects iso-build from an unchanged baseline or the candidate.
No mounts, chroots, host APT operations or ISO packing are performed.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SUBJECT = Path(os.environ.get('SUBJECT', Path(__file__).resolve().parents[1]))
HELPERS = ['libjcat1', 'grub-efi-amd64-signed-template', 'shim-helpers-amd64-signed-template']
PACKAGES = ['grub-efi', 'grub-efi-amd64'] + HELPERS


class Failures(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f'{self.bin}:/usr/bin:/bin', TMPDIR=str(self.root),
                        FIXTURE=str(self.root), MODE='', OMIT='')
        self.mock('apt-cache', '''
[ "$MODE" != apt-fail ] || { echo 'APT cache unreadable' >&2; exit 100; }
shift
for p; do
 [ "$MODE:$p" != missing:missing ] || continue
 echo "$p:"
 if [ "$MODE:$p" = none:missing ]; then echo '  Candidate: (none)'; else echo '  Candidate: 1.0'; fi
done''')
        self.mock('dpkg-scanpackages', '''
[ "$MODE" != index-fail ] || { echo 'index write failed' >&2; exit 1; }
for p in grub-efi grub-efi-amd64 libjcat1 grub-efi-amd64-signed-template shim-helpers-amd64-signed-template; do
 [ "$p" = "$OMIT" ] || printf 'Package: %s\\nVersion: 1.0\\n\\n' "$p"
done''')
        (self.root/'names').write_text('available\nmissing\n')
        (self.root/'remove').write_text('')
        self.env.update(NAMES=str(self.root/'names'), REMOVE=str(self.root/'remove'))

    def mock(self, name, body):
        p=self.bin/name; p.write_text('#!/bin/sh\n'+body+'\n'); p.chmod(0o755)

    def base(self, mode=''):
        self.env['MODE']=mode
        return subprocess.run(['sh', str(SUBJECT/'base-list.sh')], env=self.env,
                              text=True, capture_output=True)

    def pack(self, mode='', omit=''):
        self.env.update(MODE=mode, OMIT=omit)
        source=(SUBJECT/'pack.sh').read_text()
        block=source[source.index("\t# the packages SparkyLinux's securebootinstall"):source.index('\n\tapt_in clean',source.index("\t# the packages SparkyLinux's securebootinstall"))]
        harness='''set -eu
R=$FIXTURE/rootfs
apt_in() {
 printf '%s\\n' "$*" >> "$FIXTURE/apt-calls"
 case "$*" in
  *--download-only*) [ "$MODE" != download-fail ] || { echo 'network unavailable' >&2; return 100; };;
  *) [ "$MODE" != install-fail ] || { echo 'helper unavailable' >&2; return 100; };;
 esac
}
inr() {
 case "$1" in
 dpkg-query)
  [ "$MODE" != query-fail ] || { echo 'package database unreadable' >&2; return 2; }
  case "$*" in
   *Version*) echo 1.0;;
   *) if [ "$MODE" = absent-helper ]; then echo 'not-installed'; else echo 'installed'; fi;;
  esac;;
 sh)
  [ "$MODE" != download-fail ] || { echo 'network unavailable' >&2; return 100; };;
 *) echo "unexpected command $*" >&2; return 99;;
 esac
}
'''
        return subprocess.run(['sh','-c',harness+block], env=self.env,text=True,capture_output=True)

    def assert_failure(self,r,detail):
        self.assertNotEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertIn(detail,r.stderr)

    def test_U06_helper_install_failure(self):
        self.assert_failure(self.pack('install-fail'),'Secure Boot helper')

    def test_U06_missing_helper_after_success(self):
        self.assert_failure(self.pack('absent-helper'),'not installed')

    def test_U06_helper_query_failure(self):
        self.assert_failure(self.pack('query-fail'),'Could not check Secure Boot helper')

    def test_U06_download_failure(self):
        self.assert_failure(self.pack('download-fail'),'Offline Secure Boot package download failed')

    def test_U06_missing_download(self):
        for package in PACKAGES:
            with self.subTest(package=package):
                self.assert_failure(self.pack(omit=package),f'package {package} is missing')

    def test_U06_index_failure(self):
        self.assert_failure(self.pack('index-fail'),'Offline Packages index could not be generated')

    def test_U06_success(self):
        r=self.pack(); self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('--download-only --reinstall install', (self.root/'apt-calls').read_text())
        index=self.root/'rootfs/usr/share/sparky-stereo/offline-debs/Packages'
        for p in PACKAGES:self.assertIn(f'Package: {p}\n',index.read_text())

    def test_U07_failed_apt_cache(self):
        r=self.base('apt-fail');self.assert_failure(r,'APT cache unreadable');self.assertEqual(r.stdout,'')

    def test_U07_unavailable_candidate(self):
        r=self.base('none');self.assert_failure(r,'Base image packages unavailable:');self.assertIn('missing',r.stderr);self.assertEqual(r.stdout,'')

    def test_U07_omitted_record(self):
        r=self.base('missing');self.assert_failure(r,'Base image packages unavailable:');self.assertEqual(r.stdout,'')

    def test_U07_missing_names(self):
        (self.root/'names').unlink();r=self.base();self.assertNotEqual(r.returncode,0);self.assertEqual(r.stdout,'')

    def test_U07_success_and_selection_policy(self):
        (self.root/'names').write_text('z-package\navailable\navailable\nlibfoo\nlibrsvg\nlibdvdcss2\nlibasound2-plugins\nlinux-image-amd64\nlinux-image-6.1\nremoved\n')
        (self.root/'remove').write_text('removed\n')
        r=self.base();self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(r.stdout,'available\nlibasound2-plugins\nlibdvdcss2\nlibrsvg\nz-package\n')


if __name__=='__main__':unittest.main(verbosity=2)
