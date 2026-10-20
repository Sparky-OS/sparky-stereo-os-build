# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Rebuild a real source package with links and a different caller umask."""
import io
import os
from pathlib import Path
import subprocess
import tarfile
import unittest

from . import test_package
from lean import standalone


class StandaloneSource(unittest.TestCase):
    setUp = test_package.Packages.setUp
    stage = test_package.Packages.stage

    def test_source_roundtrip_preserves_payload_links_modes_and_bytes(self):
        tree = self.stage('1+lc1')
        docs = tree / 'usr/share/doc/lc-demo'
        docs.mkdir(parents=True)
        (docs / 'copyright').write_text('Copyright 2026 Example\nLicense: MIT\n')
        wants = tree / 'etc/systemd/system/multi-user.target.wants'
        wants.mkdir()
        (wants / 'lc-demo.service').symlink_to('../lc-demo.service')
        (wants / 'uninstalled.service').symlink_to('../uninstalled.service')
        authoring = self.base / 'authoring'
        authoring.mkdir()
        (authoring / 'README').write_text('Authored inputs for the fixture.\n')
        (authoring / 'readme-link').symlink_to('README')
        for path in tree.rglob('*'):
            if not path.is_symlink():
                path.chmod(path.stat().st_mode | 0o020)
        initial = self.base / 'initial'
        caller_umask = os.umask(0o002)
        try:
            standalone.build(tree, initial, authoring)
        finally:
            os.umask(caller_umask)
        rebuild = self.base / 'rebuild'
        rebuild.mkdir()
        source = rebuild / 'source'
        subprocess.run(['dpkg-source', '-x', str(initial / 'lc-demo_1+lc1.dsc'),
                        str(source)], check=True, capture_output=True)
        self.assertTrue((source / 'authoring/readme-link').is_symlink())
        caller_umask = os.umask(0o077)
        try:
            subprocess.run(['dpkg-buildpackage', '-us', '-uc', '-b'], cwd=source,
                           check=True, capture_output=True)
        finally:
            os.umask(caller_umask)

        def contents(archive, option):
            raw = subprocess.check_output(['dpkg-deb', option, str(archive)])
            with tarfile.open(fileobj=io.BytesIO(raw)) as stream:
                return {item.name: (item.type, item.mode, item.linkname,
                                    stream.extractfile(item).read() if item.isfile() else None)
                        for item in stream if item.name != './'}

        for archive in initial.glob('*.deb'):
            for option in ('--fsys-tarfile', '--ctrl-tarfile'):
                self.assertEqual(contents(archive, option),
                                 contents(rebuild / archive.name, option))
