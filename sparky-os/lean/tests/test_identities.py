"""One label, one renderer (ORDER 352): the toolkit's own code is its VERSION's row in the version table, a
renderer change without the next VERSION fails here, and the release gate refuses a package whose lc1
manifest pairs a label with a digest the table does not give it."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from lean import VERSION, identities, package, project, release  # noqa: E402

LEAN = Path(project.__file__).parent


class Table(unittest.TestCase):
    def test_the_toolkit_is_its_versions_one_row(self):
        """The review step, automated: a change to a renderer file needs the next VERSION and its row."""
        self.assertIsNone(identities.toolkit_problem(VERSION, project.IDENTITY, project.CODE_SHA256))
        self.assertEqual(identities.RELEASED[VERSION], {project.CODE_SHA256: project.IDENTITY})

    def test_a_renderer_change_without_a_bump_fails(self):
        for name in ('lang_zig.py', 'project.py', 'ZigTokens.zig', 'JvmLexer.java'):
            with self.subTest(name), tempfile.TemporaryDirectory() as d:
                copy = Path(d) / 'lean'
                shutil.copytree(LEAN, copy, ignore=shutil.ignore_patterns('__pycache__', 'tests'))
                with open(copy / name, 'a', encoding='utf-8') as f:
                    f.write('\n')
                code = project.code_sha256(copy)
                self.assertNotEqual(code, project.CODE_SHA256)
                identity = project.IDENTITY.rsplit(' code ', 1)[0] + f' code {code[:16]}'
                why = identities.toolkit_problem(VERSION, identity, code)
                self.assertIn('give the change the next VERSION', why)

    def test_a_new_file_named_like_an_adapter_moves_the_digest(self):
        with tempfile.TemporaryDirectory() as d:
            copy = Path(d) / 'lean'
            shutil.copytree(LEAN, copy, ignore=shutil.ignore_patterns('__pycache__', 'tests'))
            (copy / 'lang_new.py').write_text('KEY = "new"\n')
            self.assertNotEqual(project.code_sha256(copy), project.CODE_SHA256)

    def test_a_bump_without_its_row_fails(self):
        self.assertIn('has no row', identities.toolkit_problem('9.9.99', 'lean 9.9.99 (x) code ' + 'a' * 16, 'a' * 64))

    def test_rows_are_consistent(self):
        for version, rows in identities.RELEASED.items():
            for digest, identity in rows.items():
                with self.subTest(version=version, digest=digest[:16]):
                    self.assertRegex(digest, r'^[0-9a-f]{64}$')
                    m = identities.LABEL.fullmatch(identity)
                    self.assertIsNotNone(m)
                    self.assertEqual(m.group(1), version)
                    if m.group(3):
                        self.assertEqual(m.group(3), digest[:16])
                    self.assertNotIn(digest, identities.NEVER_RELEASED)
                    self.assertIsNone(identities.problem(identity, digest))
        later = [v for v in identities.RELEASED if tuple(map(int, v.split('.'))) >= (0, 1, 24)]
        self.assertIn(VERSION, later)
        for version in later:
            self.assertEqual(len(identities.RELEASED[version]), 1, version)

    def test_pairs_refused(self):
        never = '0906d5288e79c2b2231ada0152845d7f355c598a3e9884740f00d62e924a2081'
        label = 'lean 0.1.23 (collapse-blank,pointer,c-drop-lines) code 0906d5288e79c2b2'
        self.assertIn('never released under lean 0.1.23', identities.problem(label, never))
        released = '26ccce6201a30ee14a50006856be96ec05bf46b12f8e053a9a1b926e8578334c'
        self.assertIsNone(identities.problem('lean 0.1.23 (collapse-blank,pointer,c-drop-lines) code 26ccce6201a30ee1',
                                             released))
        self.assertIn('is not the renderer lean 0.1.23 released',
                      identities.problem('lean 0.1.23 (collapse-blank,pointer,c-drop-lines) code ' + 'b' * 16, 'b' * 64))
        self.assertIn('was released as', identities.problem('lean 0.1.23 (collapse-blank,pointer) code 26ccce6201a30ee1',
                                                            released))
        self.assertIn('not a released version', identities.problem('lean 0.1.16 (collapse-blank,pointer)', 'c' * 64))
        self.assertIn('is not of the form', identities.problem('lean 0.1.0 (historical', 'a' * 64))


class Gate(unittest.TestCase):
    """check-debs (build-tree, check-selection and check-repo run it) and check-identity, on real archives."""

    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='test-identity-')
        self.addCleanup(self.work.cleanup)
        self.base = Path(self.work.name)

    def deb(self, name, renderer=None):
        root = self.base / f'stage-{name}'
        (root / 'DEBIAN').mkdir(parents=True)
        (root / 'DEBIAN/control').write_text(f'Package: {name}\nVersion: 1\nArchitecture: all\n'
                                            'Maintainer: Example <dev@example.org>\nDescription: Test package\n')
        script = root / 'usr/bin' / name
        script.parent.mkdir(parents=True)
        script.write_text('#!/bin/sh\n' + '# A long explanation for the developer, kept in HR.\n' * 6 + 'echo hi\n')
        out = self.base / f'out-{name}'
        release.build_tree(root, out)
        deb = out / f'{name}_1_all.deb'
        if renderer is None:
            return deb
        # the same archive with another renderer in its manifest, the control marker bound to it again
        tree = self.base / f'tree-{name}'
        subprocess.run(['dpkg-deb', '-R', str(deb), str(tree)], check=True)
        mp = tree / package.manifest_path(name, 'all').lstrip('/')
        obj = package.json.loads(mp.read_bytes())
        obj['renderer'] = renderer
        raw = package.encode(obj)
        mp.write_bytes(raw)
        package.set_fields(tree / 'DEBIAN/control', {package.FIELD: f'lc1 {package.digest(raw)}'})
        md5 = tree / 'DEBIAN/md5sums'
        lines = [line for line in md5.read_text().splitlines() if not line.endswith(mp.relative_to(tree).as_posix())]
        lines.append(f'{package.file_hash(mp, "md5")}  {mp.relative_to(tree).as_posix()}')
        md5.write_text('\n'.join(lines) + '\n')
        bad = self.base / f'{name}-tampered_1_all.deb'
        subprocess.run(['dpkg-deb', '--root-owner-group', '-Zxz', '-b', str(tree), str(bad)], check=True,
                       stdout=subprocess.DEVNULL)
        return bad

    def test_current_and_released_renderers_pass(self):
        good = self.deb('lc-now')
        self.assertEqual(len(release.check_debs(sorted(good.parent.glob('*.deb')))), 2)   # with its HR companion
        old = self.deb('lc-old', {'identity': 'lean 0.1.23 (collapse-blank,pointer,c-drop-lines) code 26ccce6201a30ee1',
                                  'sha256': '26ccce6201a30ee14a50006856be96ec05bf46b12f8e053a9a1b926e8578334c'})
        release.check_identity([good, old])

    def test_a_label_with_another_digest_is_refused(self):
        bad = self.deb('lc-0906', {'identity': 'lean 0.1.23 (collapse-blank,pointer,c-drop-lines) code 0906d5288e79c2b2',
                                   'sha256': '0906d5288e79c2b2231ada0152845d7f355c598a3e9884740f00d62e924a2081'})
        with self.assertRaisesRegex(package.Invalid, 'never released under lean 0.1.23'):
            release.check_debs([bad])
        with self.assertRaisesRegex(package.Invalid, '1 of 2 packages carry a renderer'):
            release.check_identity([self.deb('lc-fine'), bad])

    def test_build_tree_refuses_a_toolkit_whose_code_is_not_its_row(self):
        root = self.base / 'stage-x'
        (root / 'DEBIAN').mkdir(parents=True)
        (root / 'DEBIAN/control').write_text('Package: x\nVersion: 1\nArchitecture: all\nMaintainer: E <e@example.org>\n'
                                            'Description: x\n')
        rows = dict(identities.RELEASED)
        rows[VERSION] = {'f' * 64: project.IDENTITY}
        original = identities.RELEASED
        identities.RELEASED = rows
        try:
            with self.assertRaisesRegex(package.Invalid, 'give the change the next VERSION'):
                release.build_tree(root, self.base / 'out-x')
        finally:
            identities.RELEASED = original
        self.assertFalse((self.base / 'out-x').exists())


if __name__ == '__main__':
    unittest.main()
