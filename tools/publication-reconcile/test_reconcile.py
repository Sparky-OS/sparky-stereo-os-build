#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Contract checks for read-only discovery and conservative source selection."""
import csv
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from inventory import paragraphs, source_identity, walk
from reconcile import binary_key, newest
from payload import listing_name, member_name


class Identities(unittest.TestCase):
    def test_binary_only_rebuild_keeps_explicit_source_version(self):
        row = paragraphs('Package: sample-bin\nVersion: 2:1.0-1+b2\nSource: sample (2:1.0-1)\n')[0]
        self.assertEqual(source_identity(row), ('sample', '2:1.0-1'))

    def test_omitted_source_uses_binary_name_and_version(self):
        self.assertEqual(source_identity({'Package': 'native', 'Version': '1.0'}), ('native', '1.0'))

    def test_epoch_and_debian_revision_are_not_lexical_order(self):
        self.assertEqual(newest(['1:1.0-2', '2.0-10', '1:1.0-10']), '1:1.0-10')

    def test_cpu_variant_is_distinct_even_with_native_architecture(self):
        row = {'binary': 'sample', 'version': '1.0', 'architecture': 'amd64'}
        self.assertNotEqual(binary_key(row), binary_key(dict(row, variant='amd64v3')))

    def test_directory_bound_does_not_claim_deeper_discovery(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'a/stage/source/deeper').mkdir(parents=True)
            dirs = {p.relative_to(root).as_posix() for p, _, _, _ in walk(root, 2, [])}
            self.assertIn('a/stage', dirs)
            self.assertNotIn('a/stage/source', dirs)


class RecipeTargets(unittest.TestCase):
    def test_required_compiler_seed_remains_a_gap_beside_its_successor(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'inventory.json').write_text(json.dumps({'published': [], 'staged': []}))
            (root / 'roots.tsv').write_text('root\ncompiler\n')
            targets = [{'source': 'compiler', 'version': '1.0', 'required_version': True, 'location': 'seed.env'},
                       {'source': 'compiler', 'version': '2.0', 'location': 'next.env'}]
            (root / 'reviewed.json').write_text(json.dumps({'compiler': {'targets': targets, 'mode': 'parameterized', 'note': 'fixture'}}))
            subprocess.run([sys.executable, str(Path(__file__).with_name('resolve.py')),
                            str(root / 'inventory.json'), str(root / 'roots.tsv'), str(root / 'reviewed.json'),
                            '--output', str(root)], check=True, capture_output=True)
            with (root / 'recipe-reconciliation.tsv').open() as stream:
                rows = list(csv.DictReader(stream, delimiter='\t'))
            self.assertEqual([r['recipe_version'] for r in rows], ['1.0', '2.0'])
            self.assertTrue(all(r['state'] == 'recipe newer than published and bounded stages' for r in rows))


class Listings(unittest.TestCase):
    def test_listing_directories_match_tar_names(self):
        self.assertEqual(listing_name('drwxr-xr-x root/root 0 2026-11-18 00:00 ./usr/'), member_name('./usr'))
        self.assertEqual(listing_name('drwxr-xr-x root/root 0 2026-11-18 00:00 ./'), member_name('.'))

    def test_links_and_spaces_keep_the_payload_path(self):
        self.assertEqual(listing_name('lrwxrwxrwx root/root 0 2026-11-18 00:00 ./usr/a b -> target'), 'usr/a b')
        self.assertEqual(listing_name('hrw-r--r-- root/root 0 2026-11-18 00:00 ./usr/a link to usr/b'), 'usr/a')

    def test_unreadable_listing_refuses_instead_of_claiming_no_removal(self):
        with self.assertRaises(ValueError):
            listing_name('not a dpkg-deb listing')


class Decisions(unittest.TestCase):
    def test_held_unlisted_predecessor_and_changed_identity_are_not_candidates(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            published = []
            staged, rules = [], []
            for name in ('held', 'unlisted', 'successor', 'conflict', 'equal', 'superseded'):
                folder = root / ('superseded' if name in ('successor', 'superseded') else name)
                folder.mkdir(exist_ok=True)
                path = folder / (name + '.deb')
                path.write_bytes(b'archive placeholder')
                row = {'kind': 'binary', 'binary': name, 'version': '1.0', 'source': name,
                       'source_version': '1.0', 'architecture': 'all', 'variant': '', 'lean': '',
                       'path': str(path), 'bytes': path.stat().st_size}
                staged.append(row)
                if name in ('held', 'conflict', 'equal'):
                    sha = hashlib.sha256(path.read_bytes()).hexdigest()
                    published.append(dict(row, filename='unused', sha256=sha if name != 'conflict' else '0' * 64))
                if name in ('held', 'successor', 'conflict'):
                    rules.append({'root': str(folder), 'source': name, 'version': '1.0',
                                  'decision': 'held' if name == 'held' else 'candidate', 'reason': 'fixture'})
            (root / 'inventory.json').write_text(json.dumps({'build_root': str(root), 'published': published, 'staged': staged}))
            (root / 'rules.json').write_text(json.dumps(rules))
            subprocess.run([sys.executable, str(Path(__file__).with_name('reconcile.py')),
                            str(root / 'inventory.json'), str(root / 'rules.json'), '--output', str(root)],
                           check=True, capture_output=True)
            with (root / 'stage-files.tsv').open() as stream:
                rows = list(csv.DictReader(stream, delimiter='\t'))
            actual = {r['binary']: r['decision'] for r in rows}
            self.assertEqual(actual, {'held': 'held', 'unlisted': 'unlisted', 'successor': 'candidate',
                                     'conflict': 'identity-conflict', 'equal': 'already-published',
                                     'superseded': 'superseded'})
            with (root / 'candidate-binaries.tsv').open() as stream:
                self.assertEqual([r['binary'] for r in csv.DictReader(stream, delimiter='\t')], ['successor'])


if __name__ == '__main__':
    unittest.main()
