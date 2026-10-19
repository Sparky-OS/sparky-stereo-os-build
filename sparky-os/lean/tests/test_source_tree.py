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
