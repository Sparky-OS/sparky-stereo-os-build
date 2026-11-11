#!/usr/bin/env python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
"""Execute the real recipes with controlled translation failures and a sealing sentinel.
Use SUBJECT for baseline packages, GRUB_TARBALL for the pinned upstream release.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SUBJECT=Path(os.environ.get('SUBJECT',Path(__file__).resolve().parents[1]))


class Translations(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.bin=self.root/'bin';self.bin.mkdir()
        self.out=self.root/'out'
        stub=self.root/'modules/lean';stub.mkdir(parents=True)
        (stub/'__init__.py').touch()
        (stub/'standalone.py').write_text("from pathlib import Path\nimport sys\nPath(sys.argv[2], 'sealed').touch()\n")
        self.env=dict(os.environ,PATH=f'{self.bin}:/usr/bin:/bin',PYTHONPATH=str(stub.parent),
                      OUT=str(self.out),TMPDIR=str(self.root),SPARKY_SCRATCH=str(self.root))

    def mock(self,name,body):
        p=self.bin/name;p.write_text('#!/bin/sh\n'+body+'\n');p.chmod(0o755)

    def package(self,name):
        p=self.root/name;shutil.copytree(SUBJECT/name,p,symlinks=True);return p

    def run_build(self,p):
        return subprocess.run(['bash',str(p/'build.sh')],env=self.env,capture_output=True,text=True,timeout=90)

    def failed(self,r,diagnostic):
        self.assertNotEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertIn(diagnostic,r.stderr)
        self.assertFalse((self.out/'sealed').exists())

    def test_U10_failed_lrelease(self):
        p=self.package('sparky-stereo-calamares-branding')
        self.mock('lrelease6','echo "injected lrelease failure" >&2; exit 7')
        self.failed(self.run_build(p),'could not be built by lrelease')

    def test_U10_lrelease_omits_output(self):
        p=self.package('sparky-stereo-calamares-branding');self.mock('lrelease6','exit 0')
        self.failed(self.run_build(p),'was not generated')

    def test_U10_missing_installer_language(self):
        p=self.package('sparky-stereo-calamares-branding')
        (p/'translations/calamares-sparky_ja.ts').unlink()
        self.failed(self.run_build(p),'calamares-sparky_ja.ts')

    def test_U10_unfinished_translation(self):
        p=self.package('sparky-stereo-calamares-branding');f=p/'translations/calamares-sparky_fr.ts'
        f.write_text(f.read_text().replace('<translation>','<translation type="unfinished">',1))
        self.failed(self.run_build(p),'unfinished or missing translation')

    def test_U10_failed_msggrep(self):
        p=self.package('sparky-stereo-grub-l10n');self.mock('msggrep','echo "injected msggrep failure" >&2; exit 8')
        self.failed(self.run_build(p),'could not be extracted')

    def test_U10_failed_msgattrib(self):
        p=self.package('sparky-stereo-grub-l10n');self.mock('msgattrib','echo "injected msgattrib failure" >&2; exit 8')
        self.failed(self.run_build(p),'could not be extracted')

    def test_U10_failed_msgfmt(self):
        p=self.package('sparky-stereo-grub-l10n');self.mock('msgfmt','echo "injected msgfmt failure" >&2; exit 8')
        self.failed(self.run_build(p),'could not be compiled')

    def test_U10_msgfmt_omits_output(self):
        p=self.package('sparky-stereo-grub-l10n');self.mock('msgfmt','exit 0')
        self.failed(self.run_build(p),'produced no catalogue')

    def test_U10_missing_grub_language(self):
        p=self.package('sparky-stereo-grub-l10n')
        self.mock('tar','''/usr/bin/tar "$@" || exit $?
while [ "$#" -gt 0 ]; do
 if [ "$1" = -C ]; then shift; rm "$1/grub-2.14/po/ja.po"; exit; fi
 shift
done''')
        self.failed(self.run_build(p),'Required GRUB translation ja is missing')

    def test_success_installer(self):
        r=self.run_build(self.package('sparky-stereo-calamares-branding'))
        self.assertEqual(r.returncode,0,r.stderr);self.assertTrue((self.out/'sealed').exists())

    def test_U10_missing_maintainer_diagnostic(self):
        p=self.package('sparky-stereo-grub-l10n')
        (p/'lang/de').unlink()
        self.failed(self.run_build(p),'Cannot embed required GRUB package messages')

    def test_success_grub(self):
        r=self.run_build(self.package('sparky-stereo-grub-l10n'))
        self.assertEqual(r.returncode,0,r.stderr);self.assertTrue((self.out/'sealed').exists())


if __name__=='__main__':unittest.main(verbosity=2)
