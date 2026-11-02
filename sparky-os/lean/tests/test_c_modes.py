"""C-family files are qualified in the mode their consumer reads them in (ORDER 352a): assembler sources and
headers the assembler preprocessor reads (GCC -x assembler-with-cpp), and files whose directives this host's
GCC checks or runs in conditional groups only other targets take, where the token and directive stream every
consumer reads is proved by clang's raw lexer. Two reproducers from lanes 161 and 346d are below in miniature:
glibc's aarch64 sysdep.h (assembler immediates `#3` in macros GCC refuses as C) and OpenZFS's
vdev_raidz_math_powerpc_altivec.c (a `#pragma GCC target("altivec")` amd64 GCC runs even inside
`#if defined(__powerpc__)`)."""

import os
from pathlib import Path
import shutil
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from lean import consumers, core, lang_c, project, source_tree  # noqa: E402

LONG = 'an explanation for the people who read this file, longer than the pointer line that replaces it'
SYSDEP = f'''/* {LONG} */
#ifndef _AARCH64_SYSDEP_H
#define _AARCH64_SYSDEP_H

#ifdef __ASSEMBLER__
/* {LONG} */
#define GCSPOPM(x)      sysl    x, #3, c7, c7, #1   // pop the guarded stack
#define GCSSS1(x)       sys     #3, c7, c7, #2, x
# define ENTRY(name) .globl name; .type name,%function; name:   /* a C comment */ \\
                     .cfi_startproc
#else
/* {LONG} */
extern int __syscall_error (int err);
#endif

#endif
'''
ALTIVEC = f'''// {LONG}
#include <sys/isa_defs.h>

#if defined(__powerpc__)
#pragma GCC target("altivec")
/* {LONG} */
static int altivec_rows; /* how many rows */
#endif
'''
ASM = f'''/* {LONG} */
#include "sysdep.h"
// {LONG}
ENTRY (__start)   /* {LONG} */
        mov     x29, #0 /* a comment
                           over two lines */ add x0, x0, #1
        bl      main    // call main
        # the assembler's own comment stays: don't
        ret
'''


def P(path, text, pointer=False):
    r = project.project(path, text.encode(), 'pkg', pointer=pointer)
    return r, (r.lean.decode() if r.lean else None)


needs = unittest.skipUnless(shutil.which('gcc') and lang_c.clang(), 'Needs gcc and clang')


@needs
class Modes(unittest.TestCase):
    def test_sysdep_header_both_consumers(self):
        """Read by C (its #else group) and by the assembler (its __ASSEMBLER__ group): GCC refuses the C reading
        only inside conditional groups, clang's raw lexer proves the C stream, GCC proves the assembler one."""
        r, out = P('/usr/include/sysdep.h', SYSDEP)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertIn('clang raw lexer (c): same tokens and directives', r.check)
        self.assertIn('GCC refuses only directives inside conditional groups', r.check)
        self.assertIn('GCC (assembler-with-cpp): same tokens and directives', r.check)
        self.assertNotIn(LONG, out)
        self.assertNotIn('pop the guarded stack', out)
        self.assertIn('sysl    x, #3, c7, c7, #1\n', out)
        self.assertRegex(out, r'name:\s+\\\n\s+\.cfi_startproc')   # the continuation stays one logical line

    def test_altivec_source_for_another_architecture(self):
        r, out = P('/usr/src/zfs-2.4.4/module/zfs/vdev_raidz_math_powerpc_altivec.c', ALTIVEC)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertIn('clang raw lexer (c): same tokens and directives', r.check)
        self.assertRegex(r.check, r"attribute .target. argument .altivec. is unknown")
        self.assertIn('#pragma GCC target("altivec")\n', out)
        self.assertNotIn('how many rows', out)

    def test_assembler_source(self):
        r, out = P('/usr/src/demo/start.S', ASM)
        self.assertEqual((r.status, r.variant), ('projected', 'asm'), r.reason)
        self.assertTrue(r.check.startswith('GCC (assembler-with-cpp): same tokens and directives'), r.check)
        self.assertNotIn(LONG, out)
        self.assertNotIn('call main', out)
        self.assertIn("# the assembler's own comment stays: don't\n", out)
        # a removed comment is one space for the assembler preprocessor: the statement keeps its line
        self.assertRegex(out, r'mov     x29, #0\s+add x0, x0, #1\n')

    def test_lowercase_s_is_no_preprocessor_input(self):
        self.assertEqual(consumers.choose('/usr/src/demo/start.s', b'nop\n')[0], None)
        self.assertEqual(consumers.choose('/usr/src/demo/start.S', b'nop\n')[:2], ('c', 'asm'))
        self.assertEqual(consumers.choose('/usr/src/demo/start.sx', b'nop\n')[:2], ('c', 'asm'))

    def test_a_refusal_outside_conditional_groups_still_stops(self):
        text = f'/* {LONG} */\n#define 3x 1\nint a;\n'      # neither GCC mode reads it, at the top level
        r, _ = P('/usr/include/bad.h', text)
        self.assertEqual(r.status, 'left')
        self.assertTrue(r.reason.startswith('check failed: GCC could not read the authored file'), r.reason)
        self.assertIn('macro names must be identifiers', r.reason)

    def test_an_assembler_only_header_without_guards(self):
        """No __ASSEMBLER__ test, a refused macro at the top level: GCC reads it only as assembler, so it is the
        assembler preprocessor's input (both modes tried, the passing one recorded), and clang proves C's stream."""
        text = f'/* {LONG} */\n#define ENTRY(x) .globl x; x: mov r0, #0\n'
        r, out = P('/usr/include/machine/asm.h', text)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertIn('GCC reads it only as assembler-with-cpp', r.check)
        self.assertIn('GCC (assembler-with-cpp)', r.check)

    def test_include_guard_is_no_conditional_evidence(self):
        text = f'/* {LONG} */\n#ifndef X_H\n#define X_H\n#define BAD(x) sys #3, x\n#endif\n'
        self.assertEqual(lang_c.conditional_lines(text), set())
        r, _ = P('/usr/include/x.h', text.replace('sys #3', 'sys @3'))
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertTrue(r.check.startswith('GCC: same tokens and directives'), r.check)

    def test_without_clang_the_lexical_mode_stops(self):
        with patch.object(lang_c, 'clang', return_value=None):
            r, _ = P('/usr/src/zfs/altivec.c', ALTIVEC)
        self.assertEqual(r.status, 'left')
        self.assertIn('clang unavailable', r.reason)
        self.assertTrue(r.reason.startswith('check failed:'))

    def test_plain_c_keeps_its_render_and_check(self):
        """A file GCC reads as C with no assembler evidence renders and checks exactly as before."""
        text = f'int a; /* {LONG}\n over two lines */ int b;\n'
        r, out = P('/usr/include/plain.h', text)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(out, 'int a;\n int b;\n')          # the 0.1.20 form: one line break, the blank after it kept
        self.assertTrue(r.check.startswith('GCC: same tokens and directives'), r.check)


@needs
class BrokenRenders(unittest.TestCase):
    """The consumer checks do not trust the renderer."""

    def test_a_split_assembler_line_is_caught(self):
        with patch.object(lang_c, 'joiner_for', lambda src, spans, asm=False: (lambda s, a, b: '\n')):
            r, _ = P('/usr/src/demo/start.S', ASM)
        self.assertEqual(r.status, 'left')
        self.assertIn('different lines', r.reason)

    def test_removed_native_comment_is_caught(self):
        real = lang_c.lex

        def lex(src):
            spans = real(src)
            k = src.index("# the assembler's")
            spans.append(core.Span(k, src.index('\n', k), core.COMMENT))
            return sorted(spans, key=lambda s: s.start)
        with patch.object(lang_c, 'lex', lex):
            r, _ = P('/usr/src/demo/start.S', ASM)
        self.assertEqual(r.status, 'left')
        self.assertTrue(r.reason.startswith('check failed:'), r.reason)

    def test_lexical_mode_catches_a_changed_token(self):
        ok, why = lang_c.lexical(ALTIVEC, ALTIVEC.replace('altivec_rows', 'altivec_row'), 'c')
        self.assertFalse(ok)
        self.assertIn('different tokens', why)
        ok, why = lang_c.lexical(ALTIVEC, ALTIVEC.replace('#pragma GCC', '#  pragma GCC'), 'c')
        self.assertTrue(ok, why)
        ok, why = lang_c.lexical('#if A\nx\n#endif\n', '#if A x\n#endif\n', 'c')
        self.assertFalse(ok)
        self.assertIn('different directives', why)


class SourceTree(unittest.TestCase):
    def test_capital_s_is_in_the_c_plan(self):
        self.assertIn('.S', source_tree.EXTENSIONS['c'])
        self.assertNotIn('.s', source_tree.EXTENSIONS['c'])


if __name__ == '__main__':
    unittest.main()
