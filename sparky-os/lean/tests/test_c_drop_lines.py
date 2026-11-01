# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""ORDER 334 (Daniel's design, 2026-11-01): C and C++ lose their comment-only lines completely, keep their
authored empty lines and get no #line, so their lean line numbers differ from the authored ones; the
resolver finds a lean line's authored line by its content ("simple - pick the line content and search it
on the source"), and the neighbouring lean lines pick among lines of the same content."""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from lean import lang_c, project  # noqa: E402

try:
    from lean import locate      # noqa: E402
except ImportError:              # an engine before 0.1.20 (the red run) has no content resolver
    locate = None

PIN = ['-U__LINE__', '-D__LINE__=0']


def P(path, text, pointer=False):
    r = project.project(path, text.encode(), 'pkg', pointer=pointer)
    return r, (r.lean.decode() if r.lean else None)


def gcc_e(text, *args, lang='c'):
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 'f.' + ('cc' if lang == 'c++' else 'c'))
        with open(p, 'w') as f:
            f.write(text)
        os.utime(p, (0, 0))
        return subprocess.run(['gcc', '-E', '-P', '-w', '-x', lang, *args, 'f.' + ('cc' if lang == 'c++' else 'c')],
                              cwd=d, capture_output=True, text=True, check=True).stdout


def comment_only_lines(text, path='/usr/include/x.h'):
    """Authored line numbers (1-based) that hold comment text and nothing else (blanks aside)."""
    spans = lang_c.lex(text)
    buf = list(text)
    marks = [False] * len(text)
    for sp in spans:
        for k in range(sp.start, sp.end):
            marks[k] = True
            if buf[k] != '\n':
                buf[k] = ' '
    out, at = [], 0
    for n, line in enumerate(text.split('\n'), 1):
        code = ''.join(buf[at:at + len(line)]).strip()
        if not code and any(marks[at:at + len(line)]) and not code.endswith('\\'):
            out.append(n)
        at += len(line) + 1
    return out


@unittest.skipUnless(shutil.which('gcc'), 'needs gcc')
class Form(unittest.TestCase):
    SRC = ('// Line one explains the file at length, so a projection that drops it moves every line.\n'
           '#include <stddef.h> /* a trailing note */\n'
           '/* a block comment\n'
           '   over three lines */\n'
           '\n'
           'int a = __LINE__; /* inline, then code: */ int b = __LINE__;\n'
           'int c = 1; /* a comment that holds\n'
           '   two line breaks\n'
           '   */ int d = __LINE__;\n'
           '#define TWO /* a comment inside the directive\n'
           '   that goes on */ 2\n'
           '#if TWO == 2 /* still the directive\n'
           '   */ && 1\n'
           'int e = __LINE__;\n'
           '#endif\n'
           'int f = TWO; /* not a directive: the # below follows code on its logical line\n'
           '   */ # define NOT_A_DIRECTIVE\n'
           '// a line comment continued \\\n'
           '   by a backslash\n'
           'int g = __LINE__;\n'
           'int h = /* spliced \\\n   inside a comment */ __LINE__;\n'
           '#define SUM(x, y) \\\n'
           '  ((x) /* first */ + \\\n'
           '   (y)) // second\n'
           'int i = SUM(__LINE__, 0);\n'
           'const char *s = R"raw(// kept\n/* kept */\n)raw"; int j = __LINE__;\n'
           '\n\n\n'
           '// a closing comment\n'
           'int k = __LINE__;\n')

    def test_comment_only_lines_go_and_the_authored_empty_lines_stay(self):
        r, mr = P('/usr/include/lines.h', self.SRC)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertNotRegex(mr, r'(?m)^[ \t]*#[ \t]*line\b')
        dropped = comment_only_lines(self.SRC)
        self.assertEqual(mr.count('\n'), self.SRC.count('\n') - len(dropped) - 3)   # and 3 joined lines
        # every empty lean line is an authored empty line: 1 after the block comment, 3 before the last comment
        self.assertEqual(mr.split('\n').count(''), self.SRC.split('\n').count(''))
        self.assertIn('#define TWO   2\n', mr)                   # a directive's comment: one space
        self.assertIn('#if TWO == 2   && 1\n', mr)
        self.assertIn('int f = TWO;   # define NOT_A_DIRECTIVE\n', mr)   # still no directive
        self.assertIn('int c = 1;\n int d = __LINE__;\n', mr)    # code before and after: two lines
        self.assertIn('R"raw(// kept\n/* kept */\n)raw"', mr)
        self.assertNotIn('three lines', mr)
        self.assertNotIn('backslash', mr)

    def test_the_compiler_sees_the_same_tokens_and_line_follows_the_lean_lines(self):
        src = self.SRC.replace('# define NOT_A_DIRECTIVE', 'NOT_A_DIRECTIVE')
        r, mr = P('/usr/include/lines.h', src, pointer=True)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(gcc_e(src, *PIN).split(), gcc_e(mr, *PIN).split())
        flat = ' '.join(gcc_e(mr).split())
        lean = mr.split('\n')
        for var in 'abdegk':
            at = next(n for n, line in enumerate(lean, 1) if re.search(rf'\bint {var} = __LINE__', line))
            self.assertIn(f'int {var} = {at};', flat, var)
        self.assertIn('__LINE__', r.check)            # the check names a file whose own code reads line numbers

    def test_a_comment_line_that_ends_a_continuation_takes_its_backslash(self):
        src = ('#define M(x) \\\n  (x) \\\n  // the last line of the macro is a comment\n'
               'int d = M(1);\n'
               '#define N(x) \\\n/* a continued comment line */ \\\n  (x)\nint e = N(2);\n')
        r, mr = P('/usr/include/m.h', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(mr, '#define M(x) \\\n  (x)\nint d = M(1);\n#define N(x) \\\n  (x)\nint e = N(2);\n')
        self.assertEqual(gcc_e(src).split(), gcc_e(mr).split())

    def test_the_check_refuses_changed_tokens_and_added_line_control(self):
        src = '// explanation\nint a = __LINE__;\n\nint b = __LINE__;\n#define X 1 /* a\n b */ + 2\nint v = X;\n'
        r, mr = P('/usr/src/x/t.c', src)
        self.assertEqual(mr, 'int a = __LINE__;\n\nint b = __LINE__;\n#define X 1   + 2\nint v = X;\n')
        self.assertTrue(lang_c.verify(src, mr)[0])
        self.assertFalse(lang_c.verify(src, mr.replace('#define X 1   + 2', '#define X 1\n + 2'))[0])
        self.assertFalse(lang_c.verify(src, mr.replace('\nint b', '\n#line 4\nint b'))[0])
        self.assertFalse(lang_c.verify(src, mr.replace('int v = X;', 'int v = X + 0;'))[0])
        self.assertIn('__LINE__', lang_c.verify(src, mr)[1])
        quiet = src.replace('__LINE__', '7')
        self.assertNotIn('line numbers', lang_c.verify(quiet, P('/usr/src/x/t.c', quiet)[1])[1])

    def test_objects_stay_the_same_outside_debug_line_information(self):
        src = 'int f(int x) {\n  // why\n  // and why again, at length, so the line moves\n  return x + 1;\n}\n'
        r, mr = P('/usr/src/x/f.c', src)
        self.assertEqual(r.status, 'projected', r.reason)
        with tempfile.TemporaryDirectory() as d:
            objs = {}
            for name, text in (('a', src), ('b', mr)):
                open(os.path.join(d, 'f.c'), 'w').write(text)
                for flags in ('-O2', '-O2 -g'):
                    subprocess.run(['gcc', *flags.split(), '-c', 'f.c', '-o', 'f.o'], cwd=d, check=True)
                    if '-g' in flags:
                        subprocess.run(['objcopy', '--strip-debug', 'f.o'], cwd=d, check=True)
                    objs[name, flags] = open(os.path.join(d, 'f.o'), 'rb').read()
            self.assertEqual(objs['a', '-O2'], objs['b', '-O2'])
            self.assertEqual(objs['a', '-O2 -g'], objs['b', '-O2 -g'])

    def test_renderer_identity_names_the_form(self):
        self.assertRegex(project.IDENTITY, r'^lean [0-9.]+ \(collapse-blank,pointer,c-drop-lines\) code [0-9a-f]{16}$')


@unittest.skipUnless(shutil.which('gcc'), 'needs gcc')
class Resolve(unittest.TestCase):
    def assertResolvesEveryLine(self, path, src, pointer=True):
        """Every lean line with code resolves by content to the line the render's own map gives."""
        self.assertIsNotNone(locate, 'no content resolver (lean.locate)')
        r, mr = P(path, src, pointer=pointer)
        self.assertEqual(r.status, 'projected', r.reason)
        _, rendered, _ = project.render_text(src, r.handler, r.variant or None, 'pkg', path, pointer)
        L = locate.Locator(src.encode(), r.lean, path)
        hows = []
        for j, line in enumerate(mr.split('\n')[:rendered.line_map.mr_line_count], 1):
            want = rendered.line_map.lines[j - 1]
            if want == 0:
                with self.assertRaises(locate.Unresolved):
                    L.find(j)
                continue
            got = L.find(j)
            if line.strip():
                self.assertEqual(got.line, want, (j, line))
            else:
                self.assertEqual(src.split('\n')[got.line - 1].strip(), '', (j, got))
            hows.append(got.how.split(' ')[0])
        return r, mr, hows

    def test_lines_after_removed_comment_blocks(self):
        src = ('/* a header comment\n   over three lines\n   that the lean form drops */\n'
               '#include <stddef.h>\n'
               '// one\n// two\n// three\n'
               'static int first(void) { return 1; }\n'
               '\n'
               '/*\n * a function comment\n */\n'
               'static int second(int x) /* trailing */\n{\n    return x;\n}\n')
        _, mr, hows = self.assertResolvesEveryLine('/usr/include/blocks.h', src)
        self.assertNotIn('three', mr)
        self.assertIn('unique', hows)

    def test_repeated_lines_are_told_apart_by_their_neighbours(self):
        block = ('static int f{n}(int x)\n{{\n    // why this branch\n    if (x)\n        return 0;\n'
                 '    /* and why this one */\n    return 0;\n}}\n\n')
        src = ''.join(block.format(n=n) for n in range(4))
        r, mr, hows = self.assertResolvesEveryLine('/usr/include/rep.h', src)
        self.assertGreater(mr.count('        return 0;'), 1)
        self.assertIn('neighbours', hows)
        lean = mr.split('\n')
        third = [j for j, line in enumerate(lean, 1) if line == '    return 0;'][2]
        self.assertEqual(locate.locate(src.encode(), r.lean, '/usr/include/rep.h', third).line,
                         src.split('\n').index('    return 0;', 2 * 9) + 1)

    def test_columns_after_a_removed_inline_comment(self):
        src = '// note\nint a = /* an inline explanation of the value below */ 42;\nint b = 7; /* trailing */\n'
        r, mr = P('/usr/src/x/c.c', src)
        self.assertIsNotNone(locate)
        lean = mr.split('\n')
        col = lean[0].index('42') + 1
        got = locate.locate(src.encode(), r.lean, '/usr/src/x/c.c', 1, col)
        self.assertEqual((got.line, got.col), (2, src.split('\n')[1].index('42') + 1))
        self.assertEqual(project.resolve(src.encode(), r.lean, '/usr/src/x/c.c', 'pkg', 1, col, pointer=False),
                         (2, src.split('\n')[1].index('42') + 1))

    def test_older_forms_resolve_too(self):
        """A lean file of engine 0.1.19 (every line kept) or 0.1.15 (#line after a removed run)."""
        self.assertIsNotNone(locate)
        src = '// one\n// two\nint a; /* x\n y */ int b;\nint c;\n'
        kept = '\n\nint a;\n int b;\nint c;\n'
        joined = '#line 3\nint a; int b;\nint c;\n'
        self.assertEqual(locate.locate(src.encode(), kept.encode(), '/x.h', 3).line, 3)
        self.assertEqual(locate.locate(src.encode(), kept.encode(), '/x.h', 4).line, 4)
        got = locate.locate(src.encode(), joined.encode(), '/x.h', 2, joined.split('\n')[1].index('int b') + 1)
        self.assertEqual((got.line, got.col), (4, src.split('\n')[3].index('int b') + 1))
        self.assertEqual(locate.locate(src.encode(), joined.encode(), '/x.h', 3).line, 5)
        with self.assertRaises(locate.Unresolved):
            locate.locate(src.encode(), joined.encode(), '/x.h', 1)          # the #line the engine wrote

    def test_the_pointer_and_a_changed_line_are_refused_by_name(self):
        self.assertIsNotNone(locate)
        src = ('// a long explanation, long enough to pay for the pointer line above it, and then some more\n'
               '// so that the lean file is the shorter one\nint a;\n')
        r, mr = P('/usr/include/p.h', src, pointer=True)
        self.assertTrue(mr.startswith('// Lean Code:'))
        with self.assertRaisesRegex(locate.Unresolved, 'pointer line'):
            locate.locate(src.encode(), r.lean, '/usr/include/p.h', 1)
        self.assertEqual(locate.locate(src.encode(), r.lean, '/usr/include/p.h', 2).line, 3)
        with self.assertRaisesRegex(locate.Unresolved, 'in no authored line'):
            locate.locate(src.encode(), r.lean.replace(b'int a;', b'int z;'), '/usr/include/p.h', 2)


if __name__ == '__main__':
    unittest.main()
