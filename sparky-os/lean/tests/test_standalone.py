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
        self.source_roundtrip('all')

    def test_debian_revision_keeps_its_source_name(self):
        tree = self.stage('1-1')
        docs = tree / 'usr/share/doc/lc-demo'
        docs.mkdir(parents=True)
        (docs / 'copyright').write_text('Copyright 2026 Example\nLicense: MIT\n')
        out = self.base / 'out'
        standalone.build(tree, out, self.authoring(git=True))
        self.assertIn('Version: 1-1', (out / 'lc-demo_1-1.dsc').read_text())
        self.assertTrue((out / 'lc-demo_1-1.tar.xz').is_file())

    def test_architecture_constrained_scripts_rebuild_with_same_architecture(self):
        arch = subprocess.check_output(['dpkg-architecture', '-qDEB_HOST_ARCH'],
                                       text=True).strip()
        self.source_roundtrip(arch)

    def test_architecture_opt_in_does_not_allow_compiled_payload(self):
        arch = subprocess.check_output(['dpkg-architecture', '-qDEB_HOST_ARCH'],
                                       text=True).strip()
        tree = self.stage('1+lc1', arch=arch)
        (tree / 'usr/bin/native-demo').write_bytes(b'\x7fELFfixture')
        with self.assertRaisesRegex(ValueError, 'compiled payload'):
            standalone.build(tree, self.base / 'out', self.base, arch)

    def test_recipe_build_dependency_is_retained_in_source(self):
        tree = self.stage('1+lc1')
        docs = tree / 'usr/share/doc/lc-demo'
        docs.mkdir(parents=True)
        (docs / 'copyright').write_text('Copyright 2026 Example\nLicense: MIT\n')
        out = self.base / 'out'
        standalone.build(tree, out, self.authoring(git=True), build_dependencies=['sparky-stereo-problems'])
        with tarfile.open(out / 'lc-demo_1+lc1.tar.xz') as archive:
            control = archive.extractfile('lc-demo-1+lc1/debian/control').read().decode()
        self.assertIn(', sparky-stereo-problems\n', control)
        self.assertIn('sparky-stereo-problems', (out / 'lc-demo_1+lc1.dsc').read_text())

    def authoring(self, git):
        """A recipe folder with an untracked note and Python caches beside its inputs."""
        recipe = self.base / 'recipe'
        recipe.mkdir()
        (recipe / 'build.sh').write_text('#!/bin/sh\necho build\n')
        (recipe / 'README').write_text('The recipe inputs.\n')
        if git:
            run = lambda *a: subprocess.run(['git', '-C', str(recipe), '-c', 'user.name=Test',  # noqa: E731
                                             '-c', 'user.email=test@example.org', *a], check=True, capture_output=True)
            run('init', '-q')
            run('add', 'build.sh', 'README')
            run('commit', '-q', '-m', 'inputs')
            (recipe / 'README').write_text('The recipe inputs, edited in the work tree.\n')
        (recipe / 'PRIVATE-NOTE.md').write_text('A note for myself, never for the archive.\n')
        (recipe / '__pycache__').mkdir()
        (recipe / '__pycache__/helper.cpython-314.pyc').write_bytes(b'\0cache')
        (recipe / 'helper.pyc').write_bytes(b'\0cache')
        return recipe

    def authoring_members(self, out):
        with tarfile.open(out / 'lc-demo_1+lc1.tar.xz') as stream:
            prefix = 'lc-demo-1+lc1/authoring/'
            return {item.name[len(prefix):]: stream.extractfile(item).read() for item in stream
                    if item.name.startswith(prefix) and item.isfile()}

    def built(self, recipe):
        tree = self.stage('1+lc1')
        docs = tree / 'usr/share/doc/lc-demo'
        docs.mkdir(parents=True)
        (docs / 'copyright').write_text('Copyright 2026 Example\nLicense: MIT\n')
        standalone.build(tree, self.base / 'out', recipe, 'all')
        return self.authoring_members(self.base / 'out')

    def test_authoring_in_a_checkout_ships_only_what_git_tracks(self):
        """ORDER 339's rule for lean.standalone --authoring: the untracked note and the caches stay out of the source
        and HR archives; a tracked file goes with its working bytes."""
        members = self.built(self.authoring(git=True))
        self.assertEqual(set(members), {'build.sh', 'README'})
        self.assertEqual(members['README'], b'The recipe inputs, edited in the work tree.\n')

    def test_authoring_outside_git_is_the_folder_without_caches(self):
        members = self.built(self.authoring(git=False))
        self.assertEqual(set(members), {'build.sh', 'README', 'PRIVATE-NOTE.md'})

    def test_a_checkout_git_cannot_read_stops_the_copy(self):
        recipe = self.authoring(git=False)
        (recipe / '.git').write_text('gitdir: /nonexistent/broken\n')
        with self.assertRaises(ValueError):
            self.built(recipe)

    def source_roundtrip(self, arch):
        tree = self.stage('1+lc1', arch=arch)
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
        # dpkg-source normalizes owner-only executable files to mode 0755.
        # The installed payload must retain its original execution permissions.
        private_executable = docs / 'owner-executable'
        private_executable.write_text('fixture data\n')
        private_executable.chmod(0o744)
        (docs / 'shipped-config~').write_text('Authored payload with a backup-like name.\n')
        initial = self.base / 'initial'
        caller_umask = os.umask(0o002)
        try:
            standalone.build(tree, initial, authoring, arch)
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
