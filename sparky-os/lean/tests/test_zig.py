"""Zig (ORDER 352): each rule of lang_zig, the consumer check catching broken adapters, the payload rule for
@embedFile, and dpkg-stereo's migration of Zig files installed before lean 0.1.24.
Needs zig: LEAN_ZIG names it (or `zig` on PATH); LEAN_ZIG_CACHE keeps zig's cache between runs."""

import contextlib
import hashlib
import importlib.machinery
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from lean import core, lang_zig, locate, package, project  # noqa: E402

BIN = Path(__file__).resolve().parents[2] / 'packages/dpkg-stereo/bin/dpkg-stereo'
LONG = 'an explanation for the people who read this file, longer than the pointer line that replaces it'
SRC = f'''//! The module's documentation: a token, published by zig std.
// {LONG}
const std = @import("std"); // trailing words go, with the blanks before them

/// Doc comment of f.
//// four slashes: an ordinary comment
pub fn f() []const u8 {{
    // zig fmt: off
    const s =
        \\\\ a line // that is data
        // {LONG}
        \\\\ "two" 'q'
    ;
    //zig fmt: on
    const c = '/';
    _ = c;
    return s ++ "a // b \\" //" ++ "x";
}}

// SPDX-License-Identifier: MIT
'''


def P(path, text, pointer=False):
    r = project.project(path, text.encode(), 'pkg', pointer=pointer)
    return r, (r.lean.decode() if r.lean else None)


@unittest.skipUnless(lang_zig.zig(), 'Needs zig (LEAN_ZIG or zig on PATH)')
class Rules(unittest.TestCase):
    def test_what_goes_and_what_stays(self):
        r, out = P('/usr/lib/demo/f.zig', SRC)
        self.assertEqual(r.status, 'projected', (r.reason, r.check))
        self.assertIn("Zig's tokenizer: the same tokens", r.check)
        self.assertNotIn(LONG, out)
        self.assertNotIn('trailing words', out)
        self.assertNotIn('four slashes', out)
        self.assertIn('const std = @import("std");\n', out)
        for kept in ("//! The module's documentation", '/// Doc comment of f.', '    // zig fmt: off\n',
                     '    //zig fmt: on\n', '\\\\ a line // that is data', '\\\\ "two" \'q\'', "const c = '/';",
                     '"a // b \\" //" ++ "x"', '// SPDX-License-Identifier: MIT'):
            self.assertIn(kept, out)
        empty = lambda t: sum(1 for x in t.split('\n')[:-1] if not x.strip())  # noqa: E731
        self.assertEqual(empty(out), empty(SRC), 'the authored empty lines stay, no empty line where a comment was')
        self.assertEqual(out.count('\n'), SRC.count('\n') - 3)   # three comment-only lines

    def test_pointer_line_and_resolve_by_content(self):
        hr = SRC.encode()
        r = project.project('/usr/lib/demo/f.zig', hr, 'demo')
        self.assertEqual(r.status, 'projected', r.reason)
        lean = r.lean.decode()
        self.assertTrue(lean.startswith('// Lean Code: HR in /usr/share/doc/demo/hr/'))
        _, rendered, _ = project.render_text(SRC, 'zig', None, 'demo', '/usr/lib/demo/f.zig')
        finder = locate.Locator(hr, r.lean, '/usr/lib/demo/f.zig')
        lines = lean.split('\n')
        checked = 0
        for j in range(1, rendered.line_map.mr_line_count + 1):
            want = rendered.line_map.lines[j - 1]
            if want and lines[j - 1].strip():
                self.assertEqual(finder.find(j).line, want, lines[j - 1])
                checked += 1
        self.assertGreater(checked, 10)

    def test_comments_lighter_than_the_pointer_leave_the_file(self):
        r, _ = P('/usr/lib/demo/g.zig', 'const a = 1; // tiny\n', pointer=True)
        self.assertEqual((r.status, r.reason), ('unchanged', 'the pointer line outweighs the comments it would replace'))

    def test_src_in_code_keeps_the_file(self):
        r, _ = P('/usr/lib/demo/s.zig', f'// {LONG}\nfn f() u32 {{\n    return @src().line;\n}}\n')
        self.assertEqual(r.status, 'left')
        self.assertIn('@src()', r.reason)
        r, out = P('/usr/lib/demo/t.zig', f'// {LONG}: @src() named in a comment only\nconst a = "@src()";\n')
        self.assertEqual(r.status, 'projected', r.reason)

    def test_templates_are_left(self):
        for path in ('/usr/lib/zig/lib/init/src/main.zig', '/usr/lib/cgm-zig/lib/zig/init/build.zig',
                     '/usr/share/cargo/registry/tree-sitter-cli-0.26.11/src/templates/root.zig'):
            with self.subTest(path):
                r, _ = P(path, SRC)
                self.assertEqual(r.status, 'left')
                self.assertIn('a template', r.reason)

    def test_authored_files_zig_does_not_accept_are_retained(self):
        r, _ = P('/usr/lib/demo/u.zig', f'// {LONG}\nfn f() void {{\n    const x = 1;\n}}\n')
        self.assertEqual(r.status, 'left')
        self.assertIn('not accepted by zig ast-check', r.reason)
        self.assertFalse(r.reason.startswith('check failed:'))
        r, _ = P('/usr/lib/demo/v.zig', f'// {LONG}\tand a tab\nconst a = 1;\n')
        self.assertEqual(r.status, 'left')
        self.assertIn("tokenizer does not accept", r.reason)

    def test_without_zig_nothing_is_projected(self):
        with patch.object(lang_zig, 'zig', return_value=None):
            r, _ = P('/usr/lib/demo/f.zig', SRC)
        self.assertEqual((r.status, r.reason), ('left', 'zig unavailable; authored file retained'))

    def test_the_check_reads_line_relations_between_tokens(self):
        ok, _ = lang_zig.verify('const a = 1;\nconst b = 2;\n', 'const a = 1;\n\nconst b = 2;\n')
        self.assertTrue(ok)
        ok, why = lang_zig.verify('/// doc\nconst a = 1;\n', '/// doc\n const a = 1;\n')
        self.assertTrue(ok, why)
        ok, why = lang_zig.verify('const a = 1;\n/// doc\nconst b = 2;\n', 'const a = 1; /// doc\nconst b = 2;\n')
        self.assertFalse(ok)
        self.assertIn('different tokens', why)


@unittest.skipUnless(lang_zig.zig(), 'Needs zig (LEAN_ZIG or zig on PATH)')
class BrokenAdapters(unittest.TestCase):
    """The consumer check does not trust the adapter: each broken lexer is caught before anything is written."""

    def broken(self, lex):
        with patch.object(lang_zig, 'lex', lex):
            r, out = P('/usr/lib/demo/f.zig', SRC)
        self.assertEqual(r.status, 'left', out)
        self.assertTrue(r.reason.startswith('check failed:'), r.reason)
        return r.reason

    def test_multiline_string_lines_read_as_code(self):
        def lex(src):
            spans, pos = [], 0
            for line in src.split('\n'):
                i = line.find('//')
                if i >= 0 and '"' not in line[:i] and "'" not in line[:i]:
                    spans.append(lang_zig._comment(line[i:], pos + i, pos + len(line)))
                pos += len(line) + 1
            return spans
        self.assertIn("Zig's tokenizer reads different tokens", self.broken(lex))

    def test_doc_comments_read_as_removable(self):
        real = lang_zig.lex

        def lex(src):
            return [core.Span(s.start, s.end, core.COMMENT) if s.why.startswith('doc comment') else s for s in real(src)]
        self.assertIn("Zig's tokenizer reads different tokens", self.broken(lex))

    def test_string_literals_ignored(self):
        def lex(src):
            spans, pos = [], 0
            for line in src.split('\n'):
                i = line.find('//') if not line.lstrip().startswith('\\\\') else -1
                if i >= 0:
                    spans.append(lang_zig._comment(line[i:], pos + i, pos + len(line)))
                pos += len(line) + 1
            return spans
        self.broken(lex)


class EmbeddedFiles(unittest.TestCase):
    def test_targets(self):
        text = ('const a = @embedFile("data/a.txt");\nconst name = "b.sh";\nconst b = @embedFile(name);\n'
                'const c = @embedFile(other.path);\n// const d = @embedFile("comment.txt");\n'
                'const e = "@embedFile(\\"string.txt\\")";\n')
        got = lang_zig.embedded('/usr/lib/demo/src/x.zig', text)
        self.assertEqual([t for t, _ in got], ['/usr/lib/demo/src/data/a.txt', '/usr/lib/demo/src/b.sh',
                                               '/usr/lib/demo/src/'])
        self.assertIn('a computed path', got[2][1])
        readers = project.read_as_data({'/usr/lib/demo/src/x.zig': text.encode()},
                                       ['/usr/lib/demo/src/x.zig', '/usr/lib/demo/src/y.zig', '/usr/lib/demo/z.zig'])
        self.assertIn('/usr/lib/demo/src/y.zig', readers)
        self.assertNotIn('/usr/lib/demo/src/x.zig', readers)
        self.assertNotIn('/usr/lib/demo/z.zig', readers)

    @unittest.skipUnless(lang_zig.zig(), 'Needs zig (LEAN_ZIG or zig on PATH)')
    def test_package_payload_keeps_what_another_file_embeds(self):
        """std/zig/perf_test.zig embeds ../os.zig: os.zig is perf_test's data, so it stays as authored, and so
        does a shell script a Zig file embeds, which the shell adapter would project otherwise."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d) / 'stage'
            (root / 'DEBIAN').mkdir(parents=True)
            (root / 'DEBIAN/control').write_text('Package: zdemo\nVersion: 1\nArchitecture: all\n'
                                                'Maintainer: E <e@example.org>\nDescription: z\n')
            lib = root / 'usr/lib/zdemo/std'
            (lib / 'zig').mkdir(parents=True)
            (lib / 'os.zig').write_text(SRC)
            (lib / 'mem.zig').write_text(SRC)
            (lib / 'zig/perf_test.zig').write_text('const source = @embedFile("../os.zig");\n'
                                                   'const script = @embedFile("../tool.sh");\n'
                                                   f'// {LONG}\npub const all = source ++ script;\n')
            script = '#!/bin/sh\n' + f'# {LONG}\n' * 3 + 'echo hi\n'
            (lib / 'tool.sh').write_text(script)
            (lib / 'other.sh').write_text(script)
            obj = package.prepare(root, Path(d) / 'hr')
        rows = {r['path']: r for r in obj['files']}
        for path in ('/usr/lib/zdemo/std/os.zig', '/usr/lib/zdemo/std/tool.sh'):
            self.assertEqual(rows[path]['status'], 'left')
            self.assertEqual(rows[path]['reason'], 'read as data by @embedFile in /usr/lib/zdemo/std/zig/perf_test.zig')
        for path in ('/usr/lib/zdemo/std/mem.zig', '/usr/lib/zdemo/std/other.sh', '/usr/lib/zdemo/std/zig/perf_test.zig'):
            self.assertEqual(rows[path]['status'], 'projected', rows[path]['reason'])


def load_client(lib):
    loader = importlib.machinery.SourceFileLoader('dpkg_stereo_zig_test', str(BIN))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    client = importlib.util.module_from_spec(spec)
    loader.exec_module(client)
    return client


@unittest.skipUnless(lang_zig.zig(), 'Needs zig (LEAN_ZIG or zig on PATH)')
class InstalledMigration(unittest.TestCase):
    """A package of another distribution installed before lean 0.1.24: its Zig and assembler files were never
    projected (no adapter), a C file for another architecture was left as "check failed" by GCC, and its embedded
    file was projected by the shell adapter. The migration examines that package once: the Zig, assembler and C
    files are projected, the embedded file gets its original back and is left with the reason; then it stays idle."""

    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='test-zig-mig-')
        self.addCleanup(self.work.cleanup)
        self.base = Path(self.work.name)
        self.client = load_client(None)

    def plain_deb(self, name, files):
        tree = self.base / f'tree-{name}'
        (tree / 'DEBIAN').mkdir(parents=True)
        sums = []
        for path, text in files.items():
            f = tree / path.lstrip('/')
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text(text)
            f.chmod(0o755 if text.startswith('#!') else 0o644)
            sums.append(f'{hashlib.md5(text.encode()).hexdigest()}  {path.lstrip("/")}\n')
        (tree / 'DEBIAN/md5sums').write_text(''.join(sums))
        (tree / 'DEBIAN/control').write_text(f'Package: {name}\nVersion: 1\nArchitecture: all\n'
                                            'Maintainer: Example <dev@example.org>\nDescription: fixture\n')
        deb = self.base / f'{name}_1_all.deb'
        subprocess.run(['dpkg-deb', '--root-owner-group', '-b', str(tree), str(deb)], check=True,
                       stdout=subprocess.DEVNULL)
        return deb

    def test_zig_files_projected_once_embedded_file_restored(self):
        script = '#!/bin/sh\n' + f'# {LONG}\n' * 3 + 'echo hi\n'
        files = {'/usr/share/zdemo/src/root.zig': SRC,
                 '/usr/share/zdemo/src/embeds.zig': f'// {LONG}\npub const s = @embedFile("data.sh");\n',
                 '/usr/share/zdemo/src/data.sh': script,
                 '/usr/share/zdemo/src/templates/new.zig': SRC,
                 '/usr/share/zdemo/src/start.S': f'/* {LONG} */\n        nop     // {LONG}\n',
                 '/usr/share/zdemo/src/altivec.c': f'// {LONG}\n#if defined(__powerpc__)\n#pragma GCC target("altivec")\n'
                                                   'static int rows;\n#endif\n'}
        deb = self.plain_deb('zdemo', files)
        root = self.base / 'system'
        (root / 'var/lib/dpkg/info').mkdir(parents=True)
        (root / 'var/lib/dpkg/status').touch()
        (root / 'var/cache/apt/archives').mkdir(parents=True)
        subprocess.run(['dpkg', '--force-not-root', '--force-bad-path', '--force-script-chrootless', f'--root={root}',
                        '-i', str(deb)], check=True, capture_output=True,
                       env={**os.environ, 'DPKG_STEREO_DISABLE': '1', 'DPKG_STEREO_NO_PROJECT': '1'})
        subprocess.run(['cp', str(deb), str(root / 'var/cache/apt/archives/')], check=True)
        client = self.client
        P = client.Paths(str(root))
        # the engine before 0.1.24: no Zig adapter, no embed rule; the shell script is projected
        old_choose = project.consumers.choose

        def choose_0123(path, data):
            if path.endswith(('.zig', '.S')):
                return None, None, 'no qualified adapter for this consumer'
            return old_choose(path, data)
        old_verify = project.consumers.lang_c.verify

        def verify_0123(original, lean, interpreter='c'):
            if 'altivec' in original:
                return False, 'GCC could not read the authored file'
            return old_verify(original, lean, interpreter)
        with patch.object(project.consumers, 'choose', choose_0123), \
                patch.object(project.consumers.lang_c, 'verify', verify_0123), \
                patch.object(project, 'read_as_data', lambda texts, paths: {}), \
                patch.object(client, 'migrate_qualified', lambda *a, **k: 0), \
                client.Lock(P), contextlib.redirect_stdout(io.StringIO()):
            client.project_packages(P, [], 1)
        self.assertIn('/usr/share/zdemo/src/data.sh', client.Records(P))
        self.assertNotIn('/usr/share/zdemo/src/root.zig', client.Records(P))
        self.assertTrue(client.Records(P, 'left')['/usr/share/zdemo/src/altivec.c']['reason'].startswith(
            'check failed: GCC could not read the authored file'))
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(client.repair_consumers(P), 0)
        self.assertIn('files lean 0.1.24 qualifies first: 1 packages examined', out.getvalue())
        records, left = client.Records(P), client.Records(P, 'left')
        self.assertEqual(records['/usr/share/zdemo/src/root.zig']['handler'], 'zig')
        self.assertEqual(records['/usr/share/zdemo/src/embeds.zig']['handler'], 'zig')
        self.assertEqual((records['/usr/share/zdemo/src/start.S']['handler'], records['/usr/share/zdemo/src/start.S']['variant']),
                         ('c', 'asm'))
        self.assertEqual(records['/usr/share/zdemo/src/altivec.c']['handler'], 'c')
        self.assertNotIn('/usr/share/zdemo/src/altivec.c', left)
        self.assertNotIn('/usr/share/zdemo/src/data.sh', records)
        self.assertEqual((root / 'usr/share/zdemo/src/data.sh').read_text(), script)
        self.assertEqual(left['/usr/share/zdemo/src/data.sh']['reason'],
                         'read as data by @embedFile in /usr/share/zdemo/src/embeds.zig')
        self.assertIn('a template', left['/usr/share/zdemo/src/templates/new.zig']['reason'])
        self.assertEqual((root / 'usr/share/zdemo/src/templates/new.zig').read_text(), SRC)
        self.assertTrue(Path(P.state('renderer-migration-0124-v1')).exists())
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.verify(P, [], True), 0)
        with contextlib.redirect_stdout(io.StringIO()) as out, \
                patch.object(client, 'project_packages', side_effect=AssertionError('migration ran twice')):
            self.assertEqual(client.repair_consumers(P), 0)


if __name__ == '__main__':
    unittest.main()
