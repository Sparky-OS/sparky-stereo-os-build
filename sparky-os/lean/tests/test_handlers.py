"""Each handler on the constructs its language makes hard, and the shared renderer's line map.
Every case projects a text and checks (a) what must be gone, (b) what must stay byte for byte, and
(c) the consumer's own verdict (the handler's check), which is also what the projection runs."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from lean import core, project  # noqa: E402


def P(path, text, pointer=False):
    r = project.project(path, text.encode(), 'pkg', pointer=pointer)
    return r, (r.lean.decode() if r.lean else None)


def run(cmd, text, suffix='', stdin=None):
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 'f' + suffix)
        with open(p, 'w') as f:
            f.write(text)
        r = subprocess.run(cmd + [p], capture_output=True, text=True, cwd=d, input=stdin, timeout=60)
        return r.returncode, r.stdout, r.stderr


class Shell(unittest.TestCase):
    SRC = r'''#!/bin/bash
# a header comment
set -e   # trailing comment
n=${#BASH_VERSION} # length, not a comment inside the braces
v=abc#def
p=${v#abc}
b=$((2#101))
echo "quoted # stays" 'single # stays' $'ansi # stays' a\#b
echo "$(echo inner # a comment inside command substitution
)"
arr=(one # a comment in an array
  two)
case $v in
  abc*) echo "case $v" ;; # after a case item
esac
cat <<EOF
# heredoc line one
	# heredoc with a tab
EOF
cat <<-'X'
	# indented heredoc
	X
long=$(cat <<'EOT'
# inside $( ) and a heredoc
EOT
)
echo cont \
  # a comment after a continuation
echo next
while read -r w; do echo "got $w"; done <<<"$(echo here-string # a comment
)"
printf '%s|%s|%s|%s|%s|%s\n' "$n" "$v" "$p" "$b" "${arr[*]}" "$long"
'''

    def test_projection_runs_the_same(self):
        r, mr = P('/usr/bin/tool', self.SRC)
        self.assertEqual(r.status, 'projected', r.reason)
        for gone in ('a header comment', 'trailing comment', 'length, not a comment', 'inside command substitution',
                     'a comment in an array', 'after a case item'):
            self.assertNotIn(gone, mr)
        for stays in ('"quoted # stays"', "'single # stays'", "$'ansi # stays'", 'a\\#b', '${#BASH_VERSION}',
                      'v=abc#def', '${v#abc}', '$((2#101))', '# heredoc line one', '\t# heredoc with a tab',
                      '\t# indented heredoc', '# inside $( ) and a heredoc'):
            self.assertIn(stays, mr)
        self.assertEqual(run(['bash'], self.SRC), run(['bash'], mr))

    def test_continuation_keeps_the_line(self):
        src = 'echo a \\\n# comment\necho b\n'
        r, mr = P('/usr/share/x/t.sh', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(run(['bash'], src), run(['bash'], mr))
        self.assertIn('echo a \\\n\necho b', mr)

    def test_word_glued_by_continuation(self):
        src = 'echo a\\\n#notacomment\n# a comment\n'
        r, mr = P('/usr/share/x/t.sh', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertIn('#notacomment', mr)
        self.assertEqual(run(['bash'], src), run(['bash'], mr))

    def test_self_reading_script_is_left(self):
        src = '#!/bin/sh\n# usage: tool [x]\nusage() { sed -n "s/^# //p" "$0"; }\nusage\n'
        r, _ = P('/usr/bin/tool', src)
        self.assertEqual(r.status, 'left')
        self.assertIn('own text', r.reason)

    def test_lineno_is_left(self):
        r, _ = P('/usr/bin/tool', '#!/bin/bash\n# x\necho $LINENO\n')
        self.assertEqual(r.status, 'left')

    def test_pointer_after_shebang_and_idempotent(self):
        r, mr = P('/usr/bin/tool', '#!/bin/sh\n# prose prose prose prose prose prose prose prose prose prose prose prose\necho hi\n',
                  pointer=True)
        self.assertEqual(r.status, 'projected', r.reason)
        lines = mr.split('\n')
        self.assertEqual(lines[0], '#!/bin/sh')
        self.assertTrue(lines[1].startswith('# ' + core.POINTER_TAG))
        self.assertIn('/usr/share/doc/pkg/hr/', lines[1])
        r2, _ = P('/usr/bin/tool', mr, pointer=True)
        self.assertEqual(r2.status, 'unchanged')

    def test_notice_is_kept(self):
        src = '#!/bin/sh\n# Copyright 2026 Someone\n# SPDX-License-Identifier: GPL-3.0-or-later\n# prose\necho hi\n'
        r, mr = P('/usr/bin/tool', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertIn('# Copyright 2026 Someone', mr)
        self.assertIn('SPDX-License-Identifier', mr)
        self.assertNotIn('# prose', mr)


class Python(unittest.TestCase):
    SRC = '''#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""Module docstring stays."""
import sys  # an import comment

TEXT = """a multi-line string
# that holds a hash line

and an empty line"""


def f(x):  # trailing
    """Function docstring stays."""
    # a body comment
    return x * 2  # result


data = [
    1,  # one
    # between items
    2,
]
print(f(len(TEXT)), data, f.__doc__, __doc__)
'''

    def test_projection_runs_the_same(self):
        r, mr = P('/usr/bin/tool.py', self.SRC)
        self.assertEqual(r.status, 'projected', r.reason)
        for gone in ('an import comment', '# trailing', 'a body comment', '# result', '# one', 'between items'):
            self.assertNotIn(gone, mr)
        for stays in ('#!/usr/bin/python3', '# -*- coding: utf-8 -*-', 'Module docstring stays.',
                      'Function docstring stays.', '# that holds a hash line\n\nand an empty line'):
            self.assertIn(stays, mr)
        self.assertEqual(run([sys.executable], self.SRC), run([sys.executable], mr))

    def test_getcomments_is_left(self):
        r, _ = P('/usr/lib/python3/dist-packages/m.py', '# c\nimport inspect\nprint(inspect.getcomments(inspect))\n')
        self.assertEqual(r.status, 'left')


@unittest.skipUnless(shutil.which('node'), 'needs node')
class JavaScript(unittest.TestCase):
    SRC = '''// header comment
var url = "http://example.org/a//b"; // trailing
var re = /\\/\\/ not a comment/g;
var t = `template // stays ${1 + /* inner */ 2} and /* stays */`;
var a = 1 /* inline */ + 2;
var b = a
/* multi
   line */ + 1;
var c = a /* multi
line */
c = 7
//@ sourceURL=kept.js
//: translator comment kept
console.log(url, re.source, t, a, b, c);
'''

    def test_projection_runs_the_same(self):
        r, mr = P('/usr/share/x/f.js', self.SRC)
        self.assertEqual(r.status, 'projected', r.reason)
        for gone in ('header comment', '// trailing', '/* inline */', 'multi\n   line'):
            self.assertNotIn(gone, mr)
        for stays in ('"http://example.org/a//b"', '/\\/\\/ not a comment/g', '`template // stays',
                      'and /* stays */`', '//@ sourceURL=kept.js', '//: translator comment kept'):
            self.assertIn(stays, mr)
        self.assertEqual(run(['node'], self.SRC, '.js'), run(['node'], mr, '.js'))

    def test_qml(self):
        src = '''// Copyright line? no: just prose
import QtQuick 2.15 // the import
Item {
    id: root /* id */
    // a property
    property int x: 2 /* two */ * 3
    property string s: "// not a comment"
    property var r: /a\\/b/
    function f() { return x // value
        ; }
}
'''
        r, mr = P('/usr/share/plasma/plasmoids/x/contents/ui/main.qml', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertIn('property int x: 2  * 3', mr)
        self.assertIn('"// not a comment"', mr)
        self.assertNotIn('a property', mr)


class Settings(unittest.TestCase):
    def test_systemd_continuation(self):
        src = '[Service]\n# about it\nExecStart=/bin/echo a \\\n# a comment inside the continuation\n  b\n; old style\nUser=x\n'
        r, mr = P('/usr/lib/systemd/system/x.service', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(mr, '[Service]\nExecStart=/bin/echo a \\\n  b\nUser=x\n')

    def test_desktop_column0_only(self):
        src = '[Desktop Entry]\n# a comment\n  # not a comment for GLib\nName=X\n'
        r, mr = P('/usr/share/applications/x.desktop', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(mr, '[Desktop Entry]\n  # not a comment for GLib\nName=X\n')

    def test_kconfig(self):
        src = '# defaults\n[General]\n  # indented comment\nKey=value # not a comment: KConfig has no inline comments\n'
        r, mr = P('/etc/xdg/kwinrc', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(mr, '[General]\nKey=value # not a comment: KConfig has no inline comments\n')

    def test_udev(self):
        src = '# rule comment\nACTION=="add", \\\n# inside\n  SUBSYSTEM=="x"\n'
        r, mr = P('/usr/lib/udev/rules.d/90-x.rules', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(mr, 'ACTION=="add", \\\n  SUBSYSTEM=="x"\n')

    def test_etc_default_whole_lines_only(self):
        src = '# about the file\nGRUB_TIMEOUT=5 # inline stays\nGRUB_CMDLINE_LINUX="a\n# inside the quotes stays\nb"\n'
        r, mr = P('/etc/default/grub', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(mr, 'GRUB_TIMEOUT=5 # inline stays\nGRUB_CMDLINE_LINUX="a\n# inside the quotes stays\nb"\n')


class Data(unittest.TestCase):
    def test_yaml_block_scalar(self):
        src = '# top\nkey: value # trailing\nscript: |\n  # data line\n  echo hi\nother: "quoted # stays"\n'
        r, mr = P('/usr/share/x/c.yaml', src)
        if r.reason.startswith('check failed: no YAML parser'):
            self.skipTest('no python3-yaml')
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertIn('  # data line\n', mr)
        self.assertNotIn('# top', mr)
        self.assertNotIn('# trailing', mr)
        self.assertIn('"quoted # stays"', mr)

    def test_toml_multiline(self):
        src = '# top\na = 1 # one\nb = """\n# data\n"""\nc = "x # y"\n'
        r, mr = P('/usr/share/x/c.toml', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(mr, 'a = 1\nb = """\n# data\n"""\nc = "x # y"\n')

    def test_json_left(self):
        r, _ = P('/usr/share/x/c.json', '{"a": 1}\n')
        self.assertEqual(r.status, 'left')


@unittest.skipUnless(shutil.which('gcc'), 'needs gcc')
class C(unittest.TestCase):
    SRC = '''/* Copyright 2026 Someone. Licensed under the MIT licence. */
#ifndef X_H
#define X_H
// a long explanation of the header, line one, which goes on for a while
// a long explanation of the header, line two, which goes on for a while
#define LONG_MACRO(a) ((a) + \\
                       1) // trailing
#if 0
// inside a skipped group, long enough to shift lines
// inside a skipped group, long enough to shift lines
#endif
static const int line_here = __LINE__;
// continued comment \\
   still the comment
int big = 1'000'000; // digit separators
#error don't stop here
/* fall through */
#endif
'''

    def test_lines_and_tokens(self):
        src = self.SRC.replace("#error don't stop here\n", '')
        r, mr = P('/usr/include/x.hpp', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertIn('Copyright 2026 Someone', mr)
        self.assertIn('/* fall through */', mr)
        self.assertNotIn('a long explanation', mr)
        self.assertNotIn('still the comment', mr)
        with tempfile.TemporaryDirectory() as d:
            outs = []
            for name, text in (('a.cc', src), ('b.cc', mr)):
                p = os.path.join(d, name)
                open(p, 'w').write(text + 'int main() { return line_here; }\n')
                outs.append(subprocess.run(['g++', '-E', '-P', p], capture_output=True, text=True).stdout)
            self.assertIn('line_here = 12', outs[0].replace(' ', ' '))
            self.assertEqual(' '.join(outs[0].split()), ' '.join(outs[1].split()))

    def test_objects_identical_with_debug_info(self):
        src = 'int f(int x) {\n  // why\n  // and why again, at length, so the line moves\n  return x + __LINE__;\n}\n'
        r, mr = P('/usr/src/x/f.c', src)
        self.assertEqual(r.status, 'projected', r.reason)
        with tempfile.TemporaryDirectory() as d:
            objs = []
            for text in (src, mr):
                open(os.path.join(d, 'f.c'), 'w').write(text)
                subprocess.run(['gcc', '-O2', '-g', '-c', 'f.c', '-o', 'f.o'], cwd=d, check=True)
                objs.append(open(os.path.join(d, 'f.o'), 'rb').read())
            self.assertEqual(objs[0], objs[1])


class LineMap(unittest.TestCase):
    def test_map_points_at_authored_lines(self):
        src = '#!/bin/sh\n# one, a comment long enough to pay for the pointer line on its own\n# two\necho a\n\n\n\n# three\necho b # trailing\n'
        r, mr = P('/usr/bin/t', src, pointer=True)
        self.assertEqual(r.status, 'projected', r.reason)
        lines = mr.split('\n')
        k = lines.index('echo b')
        sl, sc = project.resolve(src.encode(), r.lean, '/usr/bin/t', 'pkg', k + 1, 1)
        self.assertEqual(sl, 9)
        with self.assertRaises(core.MrLineMapRefusal):
            project.resolve(src.encode(), r.lean, '/usr/bin/t', 'pkg', 2, 1)   # the pointer line

    def test_stale_mr_is_refused(self):
        src = '#!/bin/sh\n# one\necho a\n'
        r, _ = P('/usr/bin/t', src + '# a longer comment that is worth removing here, long enough for the pointer\n', pointer=True)
        with self.assertRaises(project.StaleMr):
            project.resolve((src + '# another comment\necho changed\n').encode(), r.lean, '/usr/bin/t', 'pkg', 3)

    def test_comment_only_edit_resolves_against_its_own_text(self):
        long = '# a long trailing comment that is worth removing, long enough to pay for the pointer\n'
        a = '#!/bin/sh\n# one\necho a\n' + long
        b = '#!/bin/sh\n# one\n# a new comment line\n# and another one\necho a\n' + long
        ra, _ = P('/usr/bin/t', a, pointer=True)
        rb, _ = P('/usr/bin/t', b, pointer=True)
        self.assertEqual(ra.lean, rb.lean)
        k = ra.lean.decode().split('\n').index('echo a') + 1
        self.assertEqual(project.resolve(a.encode(), ra.lean, '/usr/bin/t', 'pkg', k)[0], 3)
        self.assertEqual(project.resolve(b.encode(), rb.lean, '/usr/bin/t', 'pkg', k)[0], 5)


if __name__ == '__main__':
    unittest.main()
