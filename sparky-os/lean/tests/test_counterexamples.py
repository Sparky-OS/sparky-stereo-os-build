# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""The counterexamples found on 2026-10-09 against CGM's and K3D's handlers
(sparky-stereo-os.private research/lean-code-2026-10-09/handler-probes.json), as tests written before
the fixes: each projects the probe and checks that its consumer gets exactly what it got before."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from lean import project  # noqa: E402


def lean(path, text):
    r = project.project(path, text.encode(), 'probe', pointer=False)
    return r, (r.lean.decode() if r.lean else text)


def run(cmd, text, suffix):
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 'probe' + suffix)
        with open(p, 'w') as f:
            f.write(text)
        r = subprocess.run(cmd + [p], capture_output=True, text=True, cwd=d)
        return r.returncode, r.stdout


def cpp(text, *args):
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 'probe.cc')
        with open(p, 'w') as f:
            f.write(text)
        return subprocess.run(['g++', '-E', '-P', *args, p], capture_output=True, text=True).stdout


@unittest.skipUnless(shutil.which('g++'), 'needs g++')
class C(unittest.TestCase):
    def test_token_boundary(self):
        src = 'int/**/value = 1;\nint other = 2; // a comment\n'
        r, mr = lean('/usr/include/probe.h', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertIn('int value', mr)
        self.assertEqual(cpp(src).split(), cpp(mr).split())

    def test_line_number(self):
        src = '// prose one\n// prose two\n// prose three\nint n = __LINE__;\n'
        r, mr = lean('/usr/include/probe.h', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertIn('int n = 4;', cpp(mr))
        self.assertNotIn('prose', mr)

    def test_raw_string_blank_lines(self):
        src = '// a note long enough to be worth more than a line directive\nconst char *s = R"x(a\n\n\nb)x";\n'
        r, mr = lean('/usr/include/probe.hpp', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertIn('R"x(a\n\n\nb)x"', mr)


@unittest.skipUnless(shutil.which('bash'), 'needs bash')
class Shell(unittest.TestCase):
    def test_double_quote(self):
        src = '#!/bin/bash\n# prose\nprintf "%s\\n" "value # keep"\n'
        r, mr = lean('/usr/bin/probe', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(run(['bash'], src, '.sh'), run(['bash'], mr, '.sh'))
        self.assertEqual(run(['bash'], mr, '.sh'), (0, 'value # keep\n'))

    def test_heredoc(self):
        src = "#!/bin/sh\n# prose\ncat <<'EOF'\n# literal data\nEOF\n"
        r, mr = lean('/usr/bin/probe', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(run(['sh'], mr, '.sh'), (0, '# literal data\n'))


class Python(unittest.TestCase):
    def test_docstring_consumer(self):
        src = '# prose\ndef f():\n    "user-facing help"\n    return 1\nresult = f.__doc__\nprint(result)\n'
        r, mr = lean('/usr/lib/python3/dist-packages/probe.py', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(run([sys.executable], mr, '.py'), (0, 'user-facing help\n'))


@unittest.skipUnless(shutil.which('node') or shutil.which('nodejs'), 'needs node')
class JavaScript(unittest.TestCase):
    def test_comment_like_string(self):
        src = '// prose\nconst value = "/* literal data */";\nconsole.log(value);\n'
        r, mr = lean('/usr/share/probe/probe.js', src)
        self.assertEqual(r.status, 'projected', r.reason)
        node = shutil.which('node') or shutil.which('nodejs')
        self.assertEqual(run([node], mr, '.js'), (0, '/* literal data */\n'))


if __name__ == '__main__':
    unittest.main()
