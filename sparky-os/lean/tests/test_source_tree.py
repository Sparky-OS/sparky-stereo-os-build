# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest

from lean import project, source_tree


@unittest.skipUnless(shutil.which('gcc'), 'GCC required')
class SourceBuildTests(unittest.TestCase):
    def test_source_consumer_plan_preserves_input_and_survives_restore(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'debian').mkdir()
            (root / 'hacks').mkdir()
            raw = b'// Resource parser depends on the original textual layout.\nint value;\n'
            source = root / 'hacks/source.c'
            source.write_bytes(raw)
            ordinary = root / 'ordinary.c'
            ordinary.write_bytes(raw)
            plan = {'hacks/*.c': 'resource validation parses C text before preprocessing'}
            (root / source_tree.PRESERVE_PLAN).write_text(json.dumps(plan))
            source_tree.project_tree(root)
            self.assertEqual(source.read_bytes(), raw)
            self.assertNotEqual(ordinary.read_bytes(), raw)
            report = json.loads((root / '.sparky-lc/source.json').read_text())
            self.assertEqual(report['preserve'], plan)
            self.assertEqual(report['files']['hacks/source.c']['status'], 'left')
            source_tree.project_tree(root)  # unchanged plan is idempotent
            (root / source_tree.PRESERVE_PLAN).write_text(json.dumps({'hacks/*.c': 'changed reason'}))
            with self.assertRaisesRegex(ValueError, 'plan changed'):
                source_tree.project_tree(root)
            source_tree.restore_tree(root)
            self.assertEqual(ordinary.read_bytes(), raw)
            self.assertEqual(source.read_bytes(), raw)

    def test_bad_or_stale_preservation_plan_fails_before_writing(self):
        for plan in ({'../outside.c': 'escape'}, {'missing/*.c': 'stale pattern'},
                     {'source.c': ''}, ['source.c']):
            with self.subTest(plan=plan), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                (root / 'debian').mkdir()
                source = root / 'source.c'
                raw = b'// Ordinary explanatory text, otherwise removable.\nint value;\n'
                source.write_bytes(raw)
                (root / source_tree.PRESERVE_PLAN).write_text(json.dumps(plan))
                with self.assertRaises(ValueError):
                    source_tree.project_tree(root)
                self.assertEqual(source.read_bytes(), raw)
                self.assertFalse((root / '.sparky-lc/source.json').exists())

    def test_preprocessor_uses_one_logical_source_identity(self):
        raw = (b'// A long ordinary comment removed before compilation of this fixture.\n'
               b'const char *file = __FILE__, *base = __BASE_FILE__;\n'
               b'const char *stamp = __TIMESTAMP__, *date = __DATE__, *time = __TIME__;\n'
               b'int line = __LINE__;\n')
        result = project.project('/fixture.c', raw, pointer=False)
        self.assertEqual(result.status, 'projected', result.reason)
        self.assertIn('same full preprocessing', result.check)

    def test_installed_header_recovers_exact_authored_source(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / 'header.h'
            raw = b'// This is the complete human explanation that needs to remain recoverable.\nint answer(void);\n'
            path.write_bytes(raw)
            os.utime(path, ns=(1000000000, 1000000000))
            source_tree.project_tree(root)
            mr = path.read_bytes()
            self.assertNotEqual(mr, raw)
            self.assertEqual(path.stat().st_mtime_ns, 1000000000)
            staged = root / 'debian/example/usr/include/header.h'
            staged.parent.mkdir(parents=True)
            staged.write_bytes(mr)
            source_tree.restore_payload(root, root / 'debian/example')
            self.assertEqual(staged.read_bytes(), raw)
            self.assertEqual(path.read_bytes(), mr)
            source_tree.restore_tree(root)
            self.assertEqual(path.read_bytes(), raw)

    def test_changed_source_and_incomplete_projection_are_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / 'source.c'
            path.write_text('// Enough ordinary explanation to remove from this fixture.\nint value;\n')
            source_tree.project_tree(root)
            path.write_text('int modified;\n')
            with self.assertRaises(ValueError):
                source_tree.restore_tree(root)
            report = root / '.sparky-lc/source.json'
            obj = json.loads(report.read_text())
            obj['qualified'] = False
            report.write_text(json.dumps(obj))
            with self.assertRaises(ValueError):
                source_tree.project_tree(root)


if __name__ == '__main__':
    unittest.main()
