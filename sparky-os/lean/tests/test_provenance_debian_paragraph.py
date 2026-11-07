"""ORDER 451: the credit of the edition never overrides the packagers' own copyright for debian/*.

DEP-5 (Debian copyright format 1.0, "Files" field): a file is covered by the last Files paragraph whose
pattern matches it. The tests resolve files the way a reader of the copyright file does.
"""

import fnmatch
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PROVENANCE = Path(__file__).resolve().parents[2] / 'repo/provenance.sh'
HEADER = 'Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/\n\n'
UPSTREAM = 'Files: *\nCopyright: 2026 Upstream Authors\nLicense: GPL-2+\n'
DEBIAN = ('Files: debian/*\nCopyright: 2026 Debian Qt/KDE Maintainers\n 2026 Aaron Rainbolt\nLicense: GPL-2+\n')
LICENCE = 'License: GPL-2+\n The licence text.\n'
CREDIT = "Daniel Ramos's edition of SparkyLinux"


def paragraphs(text):
    out = []
    for block in re.split(r'\n{2,}', text.strip('\n')):
        m = re.match(r'Files:((?:[^\n]*)(?:\n[ \t][^\n]*)*)', block)
        if m:
            out.append((m.group(1).split(), block))
    return out


def holder(text, path):
    """The Copyright block of the last Files paragraph that matches path (DEP-5: the last match wins)."""
    found = None
    for patterns, block in paragraphs(text):
        if any(fnmatch.fnmatchcase(path, p) for p in patterns):
            found = block
    return found


class Provenance(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def stage(self, name, copyright_text, maintainer='Example <dev@example.org>'):
        root = self.base / name
        (root / 'DEBIAN').mkdir(parents=True)
        (root / 'DEBIAN/control').write_text(
            f'Package: {name}\nVersion: 1\nArchitecture: all\nMaintainer: {maintainer}\nDescription: Fixture\n')
        cf = root / f'usr/share/doc/{name}/copyright'
        cf.parent.mkdir(parents=True)
        cf.write_text(copyright_text)
        return root, cf

    def source(self, name, files, manifest=None):
        root = self.base / (name + '-source')
        for f in files:
            p = root / f
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('x\n')
        if manifest is not None:
            (root / 'debian/sparky-provenance-files').write_text(manifest)
        return root

    def run_prov(self, root, source=None, check=True):
        cmd = ['bash', str(PROVENANCE), '--tree', str(root)]
        if source:
            cmd += ['--source', str(source)]
        return subprocess.run(cmd, check=check, capture_output=True, text=True)

    def test_a_native_package_keeps_the_whole_debian_paragraph(self):
        root, cf = self.stage('native', HEADER + UPSTREAM)
        self.run_prov(root)
        text = cf.read_text()
        self.assertEqual(text.count('Files: debian/*\n'), 1, text)
        self.assertIn(CREDIT, holder(text, 'debian/control'))
        self.assertIn('Daniel Ramos (Capitain Jack)', holder(text, 'debian/rules'))

    def test_b_a_rebuilt_package_leaves_the_packagers_debian_paragraph_alone(self):
        original = HEADER + UPSTREAM + '\n' + DEBIAN + '\n' + LICENCE
        root, cf = self.stage('rebuilt', original)
        src = self.source('rebuilt', ['debian/changelog', 'debian/patches/s1-0001-ours.patch', 'debian/patches/0001-debian.patch',
                                      'debian/sparky-lean-toolkit/provenance.sh'],
                          manifest='# our patches\ndebian/patches/s1-0001-ours.patch\n')
        self.run_prov(root, src)
        text = cf.read_text()
        self.assertTrue(text.startswith(original.rstrip('\n')), 'the file as it was comes first, unchanged')
        for path in ('debian/changelog', 'debian/control', 'debian/patches/0001-debian.patch'):
            self.assertIn('Debian Qt/KDE Maintainers', holder(text, path), path)
            self.assertNotIn(CREDIT, holder(text, path), path)
        for path in ('debian/patches/s1-0001-ours.patch', 'debian/sparky-lean-toolkit/provenance.sh',
                     'debian/sparky-provenance-files'):
            h = holder(text, path)
            self.assertIn(CREDIT, h, path)
            self.assertIn('Daniel Ramos (Capitain Jack)', h, path)
            self.assertIn('License: GPL-2+', h, path)
            self.assertNotIn('Debian Qt/KDE Maintainers', h, path)
        self.assertEqual(holder(text, 'src/main.cpp').count('Upstream Authors'), 1)

    def test_b_without_a_source_tree_only_the_lean_files_are_named(self):
        root, cf = self.stage('nosrc', HEADER + UPSTREAM + '\n' + DEBIAN)
        self.run_prov(root)
        text = cf.read_text()
        self.assertIn('Debian Qt/KDE Maintainers', holder(text, 'debian/changelog'))
        self.assertIn(CREDIT, holder(text, 'debian/sparky-lean-toolkit/lean/x.py'))

    def test_b_again_and_over_an_older_false_credit_gives_the_same_bytes(self):
        old = (HEADER + UPSTREAM + '\n' + DEBIAN + '\nFiles: debian/*\nComment: Sparky Stereo OS packaging. old\n'
               'Copyright: 2026 Daniel Ramos (Capitain Jack)\nLicense: GPL-2+\n On Debian systems.\n')
        root, cf = self.stage('again', old)
        self.run_prov(root)
        once = cf.read_text()
        self.assertIn('Debian Qt/KDE Maintainers', holder(once, 'debian/control'))
        self.assertEqual(once.count('Sparky Stereo OS packaging'), 1)
        self.run_prov(root)
        self.assertEqual(cf.read_text(), once)

    def test_b_a_manifest_entry_that_matches_nothing_stops_the_build(self):
        root, cf = self.stage('bad', HEADER + UPSTREAM + '\n' + DEBIAN)
        src = self.source('bad', ['debian/changelog'], manifest='debian/patches/missing.patch\n')
        result = self.run_prov(root, src, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('matches no file', result.stderr)

    def test_c_a_copyright_file_not_in_debian_format_gains_no_field(self):
        original = 'This package was debianized by Someone.\n\nCopyright 2020 Someone\nLicense: GPL-2\n'
        root, cf = self.stage('plain', original)
        self.run_prov(root)
        text = cf.read_text()
        self.assertTrue(text.startswith(original.rstrip('\n')))
        self.assertIn(CREDIT, text)
        self.assertEqual(paragraphs(text), [])
        self.assertNotIn('\nFiles:', text)
        self.assertNotIn('\nLicense: GPL-2+', text)
        self.run_prov(root)
        self.assertEqual(cf.read_text(), text)

    def test_the_packaging_of_ours_under_another_licence_keeps_it(self):
        text = HEADER + 'Files: *\nCopyright: 2026 Upstream\nLicense: BSL-1.0\n\nLicense: BSL-1.0\n The licence text.\n'
        root, cf = self.stage('bsl', text + '\nFiles: debian/*\nComment: Sparky Stereo OS packaging, older.\n'
                              'Copyright: 2026 Daniel Ramos (Capitain Jack)\nLicense: BSL-1.0\n')
        self.run_prov(root)
        out = cf.read_text()
        self.assertIn('\nLicense: BSL-1.0\n', holder(out, 'debian/control') + '\n')
        self.assertNotIn('GPL', holder(out, 'debian/control'))
        self.assertIn('License: BSL-1.0\n The licence text.\n', out)

    def test_the_lean_build_step_hands_the_source_tree_to_provenance(self):
        text = (Path(__file__).resolve().parents[1] / 'debhelper.py').read_text()
        self.assertIn("'--tree', str(staging), '--source', str(root)", text)


if __name__ == '__main__':
    unittest.main()
