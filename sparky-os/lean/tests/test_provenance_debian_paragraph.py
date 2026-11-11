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
OURS = 'Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'
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

    def stage(self, name, copyright_text, maintainer='Example <dev@example.org>'):  # the default stands for a rebuild
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
        root, cf = self.stage('native', HEADER + UPSTREAM, maintainer=OURS)
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
                              'Copyright: 2026 Daniel Ramos (Capitain Jack)\nLicense: BSL-1.0\n', maintainer=OURS)
        self.run_prov(root)
        out = cf.read_text()
        self.assertIn('\nLicense: BSL-1.0\n', holder(out, 'debian/control') + '\n')
        self.assertNotIn('GPL', holder(out, 'debian/control'))
        self.assertIn('License: BSL-1.0\n The licence text.\n', out)

    def test_the_lean_build_step_hands_the_source_tree_to_provenance(self):
        text = (Path(__file__).resolve().parents[1] / 'debhelper.py').read_text()
        self.assertIn("'--tree', str(staging), '--source', str(root)", text)

    def test_b_a_rebuild_without_a_debian_paragraph_does_not_claim_debian_star(self):
        # qemu, fltk1.4, mlt and dpkg are such packages: Debian's copyright only has Files: *, the control says Original-Maintainer
        root, cf = self.stage('rebuild-star', HEADER + UPSTREAM)
        src = self.source('rebuild-star', ['debian/changelog', 'debian/patches/s1-0001-ours.patch'],
                          manifest='debian/patches/s1-0001-ours.patch\n')
        self.run_prov(root, src)
        text = cf.read_text()
        self.assertNotIn('\nFiles: debian/*\n', text)
        self.assertNotIn(CREDIT, holder(text, 'debian/changelog'))
        self.assertIn(CREDIT, holder(text, 'debian/patches/s1-0001-ours.patch'))
        self.run_prov(root, src)
        self.assertEqual(cf.read_text(), text)

    def test_the_rebuild_signal_survives_a_restamp(self):
        # the second pass sees our maintainer, but the Original-Maintainer the first pass wrote stays
        root, cf = self.stage('restamp', HEADER + UPSTREAM)
        self.run_prov(root)
        first = cf.read_text()
        self.assertIn('Original-Maintainer: Example', (root / 'DEBIAN/control').read_text())
        self.run_prov(root)
        self.assertEqual(cf.read_text(), first)

    def changelog(self, root, name, trailer):
        import gzip
        path = root / f'usr/share/doc/{name}/changelog.Debian.gz'
        path.write_bytes(gzip.compress((f'{name} (1) unstable; urgency=low\n\n  * x\n\n -- {trailer}  Sat, 07 Nov 2026 00:00:00 +0000\n').encode()))

    def test_b_a_rebuild_told_by_its_changelog_when_the_control_has_no_original_maintainer(self):
        # a source rebuilt along our chain (kwin, qemu's second binaries) has our Maintainer already; the packagers' entries stay
        root, cf = self.stage('chain', HEADER + UPSTREAM, maintainer=OURS)
        self.changelog(root, 'chain', 'Debian Packager <packager@example.org>')
        self.run_prov(root)
        text = cf.read_text()
        self.assertNotIn('\nFiles: debian/*\n', text)
        self.assertNotIn(CREDIT, holder(text, 'debian/changelog'))

    def test_a_native_package_with_only_our_entries_keeps_the_whole_paragraph(self):
        root, cf = self.stage('ownlog', HEADER + UPSTREAM, maintainer=OURS)
        self.changelog(root, 'ownlog', 'root <root@0123456789ab>')
        self.run_prov(root)
        self.assertIn(CREDIT, holder(cf.read_text(), 'debian/changelog'))


class PatchHeaders(unittest.TestCase):
    HELPER = Path(__file__).resolve().parents[2] / 'repo/provenance-files.py'
    UPSTREAM_PATCH = ('From dccbdbad Mon Sep 17 00:00:00 2001\nFrom: Another Author <author@example.org>\n'
                      'Subject: [PATCH] carried\n\n(cherry picked from commit 0ea31ae7)\n---\n a | 1 +\n')
    OURS_PATCH = 'From: Daniel Campos Ramos <Capitain_Jack@yahoo.com>\nSubject: [PATCH] ours\n\n---\n a | 1 +\n'
    ORIGIN_PATCH = ('From: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nOrigin: upstream, https://example.org/c/1\n'
                    'Subject: carried by us\n\n---\n a | 1 +\n')

    def tree(self, **patches):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        d = Path(tmp.name) / 'debian/patches'
        d.mkdir(parents=True)
        for name, text in patches.items():
            (d / name).write_text(text)
        return Path(tmp.name)

    def run_helper(self, root, *patterns):
        return subprocess.run([sys.executable, '-I', str(self.HELPER), str(root), *patterns], capture_output=True, text=True)

    def test_only_the_patches_that_say_they_are_ours_are_named(self):
        root = self.tree(**{'s41-0001-carried.patch': self.UPSTREAM_PATCH, 's42-0001-ours.patch': self.OURS_PATCH,
                            's43-0001-origin.patch': self.ORIGIN_PATCH})
        r = self.run_helper(root, 's??-????-*.patch')
        self.assertEqual(r.returncode, 0, r.stderr)
        names = (root / 'debian/sparky-provenance-files').read_text()
        self.assertIn('debian/patches/s42-0001-ours.patch', names)
        self.assertNotIn('s41-0001', names)
        self.assertNotIn('s43-0001', names)
        self.assertIn('left out s41-0001-carried.patch', r.stdout)

    def test_a_patch_with_no_header_stops_the_run_and_is_named(self):
        root = self.tree(**{'s42-0001-ours.patch': self.OURS_PATCH, 's42-0002-bare.patch': '--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n'})
        r = self.run_helper(root, 's??-????-*.patch')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('s42-0002-bare.patch', r.stderr)
        self.assertFalse((root / 'debian/sparky-provenance-files').exists())

    def test_a_vendor_patch_is_ours_only_when_daniel_wrote_it(self):
        # DEP-3's "vendor" is a patch made by a distribution: ours when the header names Daniel, another vendor's otherwise
        ours = 'From: Daniel Campos Ramos <Capitain_Jack@yahoo.com>\nOrigin: vendor\nForwarded: no\nSubject: ours\n\n---\n a | 1 +\n'
        theirs = 'Author: Another Vendor <vendor@example.org>\nOrigin: vendor, https://example.org/v/1\nSubject: theirs\n\n---\n a | 1 +\n'
        root = self.tree(**{'s47-0004-ours-vendor.patch': ours, 's47-0005-their-vendor.patch': theirs})
        r = self.run_helper(root, 's??-????-*.patch')
        self.assertEqual(r.returncode, 0, r.stderr)
        names = (root / 'debian/sparky-provenance-files').read_text()
        self.assertIn('debian/patches/s47-0004-ours-vendor.patch', names)
        self.assertNotIn('s47-0005', names)

    def test_a_pattern_that_matches_no_patch_stops_the_run(self):
        root = self.tree(**{'s42-0001-ours.patch': self.OURS_PATCH})
        self.assertNotEqual(self.run_helper(root, 'x*.patch').returncode, 0)


if __name__ == '__main__':
    unittest.main()
