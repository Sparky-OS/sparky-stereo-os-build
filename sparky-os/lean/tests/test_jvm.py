# SPDX-License-Identifier: MIT
# Copyright 2026 Daniel Campos Ramos
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from lean import core, lang_jvm, project


@unittest.skipUnless(shutil.which('javac') or os.environ.get('JAVA_HOME'), 'Needs a JDK')
class JavaProjection(unittest.TestCase):
    def test_default_package_pointer_and_resolver(self):
        text = ('// ' + 'explanatory words ' * 30 + '\nclass Demo {}\n').encode()
        r = project.project('Demo.java', text, package='demo')
        self.assertEqual(r.status, 'projected', (r.reason, r.check))
        line = next(i for i, s in enumerate(r.lean.decode().splitlines(), 1) if 'class Demo' in s)
        self.assertEqual(project.resolve(text, r.lean, 'Demo.java', 'demo', line)[0], 2)

    def projected(self, name, text):
        result = project.project(name, text.encode(), pointer=False)
        self.assertEqual(result.status, 'projected', (result.reason, result.check))
        return result.lean.decode()

    def test_literal_and_unicode_created_code(self):
        text = 'class Demo {\n // explanation \\u000a static int value = 7;\n // removable long explanation\n String s = "😀 // /* literal */";\n}\n'
        lean = self.projected('Demo.java', text)
        self.assertIn('static int value = 7', lean)
        self.assertIn('😀 // /* literal */', lean)
        self.assertIn('\\u000a', lean)
        self.assertNotIn('removable long explanation', lean)

    def test_doc_comments_and_operational_comments_unchanged(self):
        doc = '/**\n\n\n\n * @deprecated kept for processors\n */'
        text = 'class Demo {\n' + doc + '\n int old;\n /*@Nullable*/ String value;\n // removable long explanation\n}\n'
        lean = self.projected('Demo.java', text)
        self.assertIn(doc, lean)
        self.assertIn('/*@Nullable*/', lean)

    def test_invalid_unicode_fails_closed(self):
        r = project.project('Demo.java', b'class Demo { // \\uZZZZ\n}\n', pointer=False)
        self.assertEqual(r.status, 'left')

    def test_real_compiler_retains_deprecated_attribute(self):
        text = 'class Demo {\n /** @deprecated old API */ public void old() {}\n // removable long explanation\n}\n'
        lean = self.projected('Demo.java', text)
        jdk = Path(os.environ['JAVA_HOME']) / 'bin' if os.environ.get('JAVA_HOME') else None
        javac = str(jdk / 'javac') if jdk else 'javac'
        javap = str(jdk / 'javap') if jdk else 'javap'
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name, source in [('authored', text), ('mr', lean)]:
                folder = root / name
                folder.mkdir()
                (folder / 'Demo.java').write_text(source)
                subprocess.run([javac, '-g', str(folder / 'Demo.java')], capture_output=True, check=True)
                output = subprocess.check_output([javap, '-verbose', str(folder / 'Demo.class')], text=True)
                self.assertIn('Deprecated: true', output)

    def test_source_map_after_supplementary_character(self):
        text = 'class Demo {\n // removable long explanation\n String s = "😀"; /* remove this inline explanation */ int value = 7;\n}\n'
        lean = self.projected('Demo.java', text)
        line = next(i for i, s in enumerate(lean.splitlines(), 1) if 'int value' in s)
        col = lean.splitlines()[line - 1].index('int value') + 1
        got = project.resolve(text.encode(), lean.encode(), 'Demo.java', None, line, col, pointer=False)
        self.assertEqual(got, (3, text.splitlines()[2].index('int value') + 1))
        with self.assertRaises(project.StaleMr):
            project.resolve(text.encode(), lean.replace('7', '8').encode(), 'Demo.java', None, line, pointer=False)


@unittest.skipUnless(os.environ.get('LEAN_KOTLIN_CLASSPATH'), 'Needs the matching Kotlin compiler lexer')
class KotlinProjection(unittest.TestCase):
    def test_default_package_pointer(self):
        text = ('// ' + 'explanatory words ' * 30 + '\nfun main() {}\n').encode()
        r = project.project('demo.kt', text, package='demo')
        self.assertEqual(r.status, 'projected', (r.reason, r.check))

    def test_nested_comments_strings_and_template_expression(self):
        text = 'fun main() {\n // removable long explanation\n val s = "😀 /* literal */ ${run { /* real nested /* comment */ removed */ 7 }}"\n println(s)\n}\n'
        r = project.project('demo.kt', text.encode(), pointer=False)
        self.assertEqual(r.status, 'projected', (r.reason, r.check))
        self.assertIn('😀 /* literal */', r.lean.decode())
        self.assertNotIn('real nested', r.lean.decode())

    def test_newline_semantics_and_adjacency_controls(self):
        self.assertFalse(lang_jvm.verify('kotlin', 'val x = 1\n+ 2', 'val x = 1 + 2')[0])
        self.assertTrue(lang_jvm.verify('kotlin', 'val x = 1 /*\n note */ + 2', 'val x = 1  + 2')[0])
        self.assertFalse(lang_jvm.verify('kotlin', 'x?/*note*/.length', 'x?.length')[0])
        self.assertTrue(lang_jvm.verify('kotlin', 'x?/*note*/.length', 'x? .length')[0])

    def test_unterminated_nested_comment_is_refused(self):
        for text in ['fun main() {} /* unfinished', 'fun main() {} /* outer /* inner */']:
            r = project.project('demo.kt', text.encode(), pointer=False)
            self.assertEqual(r.status, 'left')
            self.assertIn('Unterminated', r.reason)

    def test_kdoc_and_raw_string_whitespace_preserved(self):
        doc = '/**\n\n\n\nExample consumed by KSP.\n*/'
        literal = '"""// literal\n\n\n\n/* data */"""'
        text = doc + '\nval text = ' + literal + '\n// removable long explanation\n'
        r = project.project('demo.kts', text.encode(), pointer=False)
        self.assertEqual(r.status, 'projected', (r.reason, r.check))
        self.assertIn(doc, r.lean.decode())
        self.assertIn(literal, r.lean.decode())


if __name__ == '__main__':
    unittest.main()
