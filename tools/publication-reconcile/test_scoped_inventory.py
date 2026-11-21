#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check search bounds and link refusal independently of package contents."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('scoped_inventory', Path(__file__).with_name('scoped-inventory.py'))
scoped = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scoped)


class SearchScope(unittest.TestCase):
    def test_files_and_directories_that_are_links_are_never_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stage = root / 'storage/lane/stage'
            stage.mkdir(parents=True)
            outside = root / 'outside'
            outside.mkdir()
            (outside / 'outside.deb').touch()
            (stage / 'real.deb').touch()
            (stage / 'file.deb').symlink_to(outside / 'outside.deb')
            (stage / 'directory').symlink_to(outside, target_is_directory=True)
            errors, skipped = [], []
            _, files = scoped.discover([root / 'storage'], [], 4, errors, skipped)
            self.assertEqual(files, [stage / 'real.deb'])
            self.assertEqual(errors, [])
            self.assertIn(str(stage / 'file.deb'), skipped)
            self.assertIn(str(stage / 'directory'), skipped)

    def test_named_root_with_link_ancestor_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'real/stage').mkdir(parents=True)
            (root / 'real/stage/package.deb').touch()
            (root / 'alias').symlink_to(root / 'real', target_is_directory=True)
            errors, skipped = [], []
            _, files = scoped.discover([], [str(root / 'alias/stage')], 4, errors, skipped)
            self.assertEqual(files, [])
            self.assertEqual(skipped, [str(root / 'alias/stage')])

    def test_discovery_and_stage_file_depths_are_separate(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stage = root / 'a/b/stage'
            (stage / 'one/two/three/four').mkdir(parents=True)
            allowed = stage / 'one/two/three/in.deb'
            allowed.touch()
            (stage / 'one/two/three/four/out.deb').touch()
            (root / 'a/b/c/d/stage').mkdir(parents=True)
            (root / 'a/b/c/d/stage/deep.deb').touch()
            _, files = scoped.discover([root], [], 4, [], [])
            self.assertEqual(files, [allowed])

    def test_explicit_output_without_stage_name_is_included(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'result.dsc').touch()
            _, files = scoped.discover([], [str(root)], 4, [], [])
            self.assertEqual(files, [root / 'result.dsc'])

    def test_missing_directory_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'absent'
            errors = []
            _, files = scoped.discover([], [str(root)], 4, errors, [])
            self.assertEqual(files, [])
            self.assertEqual(errors, ['missing directory: ' + str(root)])


if __name__ == '__main__':
    unittest.main()
