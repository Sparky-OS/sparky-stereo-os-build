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
