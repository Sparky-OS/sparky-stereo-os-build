# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from lean import project, source_tree


@unittest.skipUnless(shutil.which('gcc'), 'GCC required')
class SourceBuildTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('javac'), 'JDK required')
    def test_java_opt_in_compiles_recovers_and_resolves(self):
        import subprocess
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'debian').mkdir()
            source = root / 'Demo.java'
            raw = (b'// Explanation removed before compilation, retained for humans.\n'
                   b'class Demo {\n /** @deprecated use another method */\n'
                   b' static int old() { return 7; }\n}\n')
            source.write_bytes(raw)
            (root / source_tree.LANGUAGE_PLAN).write_text('["java"]')
            source_tree.project_tree(root)
            mr = source.read_bytes()
            self.assertNotEqual(mr, raw)
            line = next(i for i, text in enumerate(mr.decode().splitlines(), 1)
                        if 'return 7' in text)
            self.assertEqual(project.resolve(raw, mr, '/Demo.java', None,
                                            line, pointer=False)[0], 4)
            subprocess.run(['javac', '-g:none', str(source)], check=True, capture_output=True)
            compiled = (root / 'Demo.class').read_bytes()
            source_tree.restore_tree(root)
            self.assertEqual(source.read_bytes(), raw)
            subprocess.run(['javac', '-g:none', str(source)], check=True, capture_output=True)
            self.assertEqual((root / 'Demo.class').read_bytes(), compiled)

    def test_language_plan_is_explicit_and_lexer_failure_is_not_qualified(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'debian').mkdir()
            (root / 'Demo.java').write_text('// an explanation\nclass Demo {}\n')
            source_tree.project_tree(root)
            report = root / '.sparky-lc/source.json'
            self.assertEqual(json.loads(report.read_text())['files'], {})
            (root / source_tree.LANGUAGE_PLAN).write_text('["java"]')
            with self.assertRaisesRegex(ValueError, 'language plan changed'):
                source_tree.project_tree(root)
            report.unlink()
            failure = project.Result(path='/Demo.java', status='left',
                                     reason='the java reader could not read it: no JDK')
            with patch.object(project, 'project', return_value=failure):
                with self.assertRaisesRegex(ValueError, 'no JDK'):
                    source_tree.project_tree(root)
            self.assertFalse(json.loads(report.read_text()).get('qualified', False))

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

    def test_explicit_payload_layout_distinguishes_empty_headers(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'debian').mkdir()
            originals = {'include/empty.h': b'',
                         'arch/x86/include/asm/exec.h': b'// Architecture explanation for humans.\n',
                         'scripts/empty.c': b'// Different commentary for the build tools.\n'}
            for name, raw in originals.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
            source_tree.project_tree(root)
            staging = root / 'debian/headers'
            for name in originals:
                path = staging / 'usr/src/linux-headers-example' / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((root / name).read_bytes())
            generated = staging / 'usr/src/linux-headers-example/include/generated.h'
            generated.write_bytes(b'')
            with self.assertRaisesRegex(ValueError, 'Ambiguous authored mapping'):
                source_tree.restore_payload(root, staging)
            (root / source_tree.PAYLOAD_SOURCE_PLAN).write_text(
                json.dumps({'/usr/src/linux-headers-example': '.'}))
            source_tree.restore_payload(root, staging)
            for name, raw in originals.items():
                self.assertEqual((staging / 'usr/src/linux-headers-example' / name).read_bytes(), raw)
            self.assertEqual(generated.read_bytes(), b'')
            source_tree.restore_payload(root, staging)  # exact authored bytes stay idempotent
            target = staging / 'usr/src/linux-headers-example/arch/x86/include/asm/exec.h'
            target.write_bytes(b'int changed;\n')
            with self.assertRaisesRegex(ValueError, 'Mapped source copy changed'):
                source_tree.restore_payload(root, staging)

    def test_payload_layout_rejects_escaping_paths(self):
        for plan in ({'/usr/include': '../outside'}, {'relative': '.'},
                     {'/usr/../include': '.'}, ['/usr/include']):
            with self.subTest(plan=plan), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                (root / 'debian').mkdir()
                (root / 'header.h').write_bytes(b'// Human explanation\nint value;\n')
                source_tree.project_tree(root)
                (root / source_tree.PAYLOAD_SOURCE_PLAN).write_text(json.dumps(plan))
                with self.assertRaises(ValueError):
                    source_tree.restore_payload(root, root / 'debian/staging')


if __name__ == '__main__':
    unittest.main()
