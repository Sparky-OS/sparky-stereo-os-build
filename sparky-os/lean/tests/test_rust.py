"""Rust (ORDER 533): each rule of lang_rust, the consumer check catching a broken adapter, a red case for every
kind of comment that is data, compiled programs whose output differs only where the rule predicts, and the
content resolver finding a lean line in the authored text.
The compiler cases need rustc: LEAN_RUSTC names it (or `rustc` on PATH); rustdoc and readelf for two of them."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from lean import consumers, core, lang_rust, locate, project, source_tree  # noqa: E402

RUSTC = lang_rust.rustc()
LONG = 'an explanation for the people who read this file, longer than the pointer line that replaces it'
SRC = f'''//! The crate's documentation: an inner doc attribute.
// {LONG}
use std::fmt; // trailing words go, with the blanks before them

/// Doc comment of f: an outer doc attribute.
//// four slashes: an ordinary comment
pub fn f<'a>(x: &'a str) -> String {{
    /* a block /* with a nested block */ comment */
    let s = "a // b \\" /* c */"; /* between */ let c = '"';
    let r = r#"raw // "quoted" /* text */"#;

    /** an outer block doc comment */
    let q = '\\''; let slash = b'/';
    /**/ /***/ format!("{{s}}{{c}}{{r}}{{q}}{{slash}}{{x}}")
}}
'''


def naive(text):
    """A broken adapter: removes every comment the lexer finds, doc comments and notices included."""
    spans = [core.Span(sp.start, sp.end, core.COMMENT) if sp.kind == core.KEEP and sp.why != 'interpreter line' else sp
             for sp in lang_rust.lex(text)]
    return core.render(text, spans, lang_rust.joiner, keep_empty_after=lang_rust.keep_empty_after,
                       collapse_blank=False, drop_lines=True).text


def lean_of(text):
    return project.render_text(text, 'rust', None, None, None, pointer=False)[0]


class Lexer(unittest.TestCase):
    def test_comments_literals_and_doc_forms(self):
        kinds = [(sp.kind, SRC[sp.start:sp.end]) for sp in lang_rust.lex(SRC)]
        self.assertEqual([t for k, t in kinds if k == core.COMMENT], [
            f'// {LONG}', '// trailing words go, with the blanks before them', '//// four slashes: an ordinary comment',
            '/* a block /* with a nested block */ comment */', '/* between */', '/**/', '/***/'])
        self.assertEqual([t for k, t in kinds if k == core.KEEP], [
            "//! The crate's documentation: an inner doc attribute.", '/// Doc comment of f: an outer doc attribute.',
            '/** an outer block doc comment */'])
        self.assertEqual([t for k, t in kinds if k == core.LITERAL], [
            '"a // b \\" /* c */"', "'\"'", 'r#"raw // "quoted" /* text */"#', "'\\''", "'/'",
            '"{s}{c}{r}{q}{slash}{x}"'])

    def test_a_lifetime_is_not_a_character_literal(self):
        text = "fn g<'a, 'b: 'a>(x: &'a u8, y: &'b u8) -> &'a u8 { 'l: loop { break 'l; } x } // gone\n"
        self.assertEqual([text[sp.start:sp.end] for sp in lang_rust.lex(text)], ['// gone'])

    def test_raw_strings_byte_strings_and_raw_identifiers(self):
        text = 'let a = br##"x "# // y"##; let b = cr"//"; let r#type = b"//"; let e = "\\\\"; // gone\n'
        spans = lang_rust.lex(text)
        self.assertEqual([text[sp.start:sp.end] for sp in spans if sp.kind == core.COMMENT], ['// gone'])
        self.assertEqual(len([sp for sp in spans if sp.kind == core.LITERAL]), 4)

    def test_an_interpreter_line_stays_and_an_inner_attribute_is_code(self):
        text = '#!/usr/bin/env -S cargo // not a comment\n#![allow(dead_code)] // gone\nfn main() {}\n'
        self.assertEqual(lean_of(text), '#!/usr/bin/env -S cargo // not a comment\n#![allow(dead_code)]\nfn main() {}\n')
        self.assertEqual(lean_of('#![allow(dead_code)] // gone\n'), '#![allow(dead_code)]\n')

    def test_notices_stay(self):
        text = '// Copyright 2026 Example\n// SPDX-License-Identifier: MIT\n// words\nfn main() {}\n'
        self.assertEqual(lean_of(text), '// Copyright 2026 Example\n// SPDX-License-Identifier: MIT\nfn main() {}\n')

    def test_unterminated_text_is_refused_by_name(self):
        for text, what in (('/* open', 'block comment'), ('let s = "open', 'string literal'), ('r#"open"', 'raw string')):
            with self.subTest(text), self.assertRaisesRegex(ValueError, what):
                lang_rust.lex(text)

    def test_frontmatter_is_left(self):
        self.assertIn('frontmatter', lang_rust.refuse('#!/usr/bin/env cargo\n---\n[dependencies]\n---\nfn main() {}\n'))
        self.assertIsNone(lang_rust.refuse(SRC))


class Render(unittest.TestCase):
    def test_comment_only_lines_go_empty_lines_stay_no_directive(self):
        lean = lean_of(SRC)
        self.assertEqual(lean, '''//! The crate's documentation: an inner doc attribute.
use std::fmt;

/// Doc comment of f: an outer doc attribute.
pub fn f<'a>(x: &'a str) -> String {
    let s = "a // b \\" /* c */";   let c = '"';
    let r = r#"raw // "quoted" /* text */"#;

    /** an outer block doc comment */
    let q = '\\''; let slash = b'/';
        format!("{s}{c}{r}{q}{slash}{x}")
}
''')
        self.assertEqual(lean.count('\n\n'), SRC.count('\n\n'))          # the authored empty lines, no more, no fewer
        self.assertNotIn('#line', lean)
        self.assertFalse([sp for sp in lang_rust.lex(lean) if sp.kind == core.COMMENT])

    def test_a_block_comment_between_tokens_is_one_space(self):
        self.assertEqual(lean_of('fn main() { let a = 1/* x */+/* y */2; let _ = a; }\n'),
                         'fn main() { let a = 1 + 2; let _ = a; }\n')

    def test_a_block_comment_over_lines_with_code_after_it(self):
        self.assertEqual(lean_of('fn a() {} /* one\n two */ fn b() {}\n'), 'fn a() {}   fn b() {}\n')


class Consumers(unittest.TestCase):
    def test_installed_rust_is_left_and_a_build_input_is_read(self):
        key, _, why = consumers.choose('/usr/share/cargo/registry/x-1.0.0/src/lib.rs', b'')
        self.assertIsNone(key)
        self.assertIn('.cargo-checksum.json', why)
        self.assertEqual(consumers.choose('/src/lib.rs', b'', native=True)[0], 'rust')
        installed = project.project('/usr/src/x/lib.rs', SRC.encode())
        self.assertEqual((installed.status, installed.lean), ('left', None))

    def test_include_str_targets(self):
        text = ('const A: &str = include_str!("../data/a.rs");\nconst B: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/b"));\n'
                '// include_str!("not/code.rs")\nconst C: &str = "include_str!(\\"x\\")";\n')
        self.assertEqual(lang_rust.embedded('/crate/src/lib.rs', text), [
            ('/crate/data/a.rs', 'read as data by include_str! in /crate/src/lib.rs'),
            ('/crate/src/', 'read as data by include_bytes! in /crate/src/lib.rs (a computed path)')])

    def test_position_uses_are_named(self):
        text = ('fn a() -> u32 { line!() } // line!() in a comment\nconst S: &str = "column!()";\n'
                '#[track_caller]\nfn b() { let _ = std::panic::Location::caller(); }\nfn c() -> u32 { column ! () }\n')
        self.assertEqual(lang_rust.lines(text), [1, 3, 4, 5])

    def test_source_readers(self):
        hashes = 'const F: &[&str] = &["src/lib.rs"];\nfn main() { for f in F { let _ = std::fs::read_to_string(f); } }\n'
        self.assertIn('names Rust source paths', lang_rust.source_reader('build.rs', hashes))
        writes = ('fn main() { let t = std::fs::read_to_string("locales/en.json").unwrap();\n'
                  ' std::fs::write(std::path::Path::new(&std::env::var("OUT_DIR").unwrap()).join("generated.rs"), t).unwrap(); }\n')
        self.assertIsNone(lang_rust.source_reader('build.rs', writes))
        self.assertIn('parse_file', lang_rust.source_reader('build.rs', 'fn main() { syn::parse_file("x").unwrap(); }\n'))
        macro = 'pub fn m(i: TokenStream) -> TokenStream { let _ = i.into_iter().next().unwrap().span().source_text(); i }\n'
        self.assertIn('source text of its caller', lang_rust.source_reader('src/lib.rs', macro, macro=True))
        self.assertIsNone(lang_rust.source_reader('src/lib.rs', '// span.source_text()\nfn x() {}\n', macro=True))


class Resolver(unittest.TestCase):
    def test_a_lean_line_is_found_in_the_authored_text(self):
        lean = lean_of(SRC)
        hr, mr = SRC.encode(), lean.encode()
        authored, projected = SRC.split('\n'), lean.split('\n')
        for needle in ('use std::fmt;', "pub fn f<'a>(x: &'a str) -> String {", 'let r = r#"raw', "let q = '\\''"):
            lean_line = next(k for k, line in enumerate(projected) if needle in line) + 1
            want = next(k for k, line in enumerate(authored) if needle in line) + 1
            self.assertNotEqual(lean_line, want)
            self.assertEqual(locate.locate(hr, mr, '/src/lib.rs', lean_line, native=True).line, want, needle)
        with self.assertRaises(locate.Unresolved):                      # an installed Rust file has no reader
            locate.locate(hr, mr, '/usr/src/x/lib.rs', 2)

    def test_repeated_content_is_told_apart_by_its_neighbours(self):
        text = ('fn a() {\n    // one\n    step();\n}\n\nfn b() {\n    // two\n    // three\n    step();\n}\n')
        lean = lean_of(text)
        self.assertEqual(lean, 'fn a() {\n    step();\n}\n\nfn b() {\n    step();\n}\n')
        self.assertEqual(locate.locate(text.encode(), lean.encode(), '/src/lib.rs', 2, native=True).line, 3)
        self.assertEqual(locate.locate(text.encode(), lean.encode(), '/src/lib.rs', 6, native=True).line, 9)


def run(cmd, cwd, **kw):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=600, **kw)


def build(work, name, text, *flags):
    """Compile `text` as src/main.rs under a fixed path and return the program's path."""
    src = Path(work) / name / 'src'
    src.mkdir(parents=True, exist_ok=True)
    (src / 'main.rs').write_text(text)
    r = run([RUSTC, '--edition', '2021', '-o', 'prog', 'src/main.rs', *flags], src.parent)
    if r.returncode != 0:
        raise AssertionError(f'{name} does not compile:\n{r.stderr}')
    return src.parent / 'prog'


@unittest.skipUnless(RUSTC, 'rustc required (LEAN_RUSTC or PATH)')
class Compiler(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory(prefix='lean-rust-test-')
        self.work = self.dir.name

    def tearDown(self):
        self.dir.cleanup()

    def test_the_consumer_check_accepts_the_render_and_catches_broken_adapters(self):
        lean = lean_of(SRC)
        ok, detail = lang_rust.verify(SRC, lean)
        self.assertTrue(ok, detail)
        self.assertIn("rustc's lexer", detail)
        self.assertIsNone(lang_rust.authored_refusal(SRC))
        ok, detail = lang_rust.verify(SRC, naive(SRC))                   # doc comments removed: other tokens
        self.assertFalse(ok)
        self.assertIn('different tokens', detail)
        ok, _ = lang_rust.verify(SRC, lean.replace('"a // b \\" /* c */"', '"a "'))   # a string read as a comment
        self.assertFalse(ok)
        ok, _ = lang_rust.verify('fn main() { let a = 1/* x */- -2; let _ = a; }\n', 'fn main() { let a = 1--2; let _ = a; }\n')
        self.assertFalse(ok)                                             # a comment removed without its space joins tokens
        self.assertIn('does not accept', lang_rust.authored_refusal('fn main() { let s = "open; }\n'))
        result = project.project('/src/lib.rs', SRC.encode(), package='native-build', pointer=False, native=True)
        self.assertEqual((result.status, result.lean.decode()), ('projected', lean))

    def test_plain_comments_change_nothing_a_program_prints_or_runs(self):
        text = ('// ' + LONG + '\nfn main() {\n    // ' + LONG + '\n    let v = vec![1u32, 2, 3]; /* inline */ let s: u32 = v.iter().sum();\n'
                '    // ' + LONG + '\n    println!("sum {s}");\n}\n')
        a, b = build(self.work, 'authored', text), build(self.work, 'lean', lean_of(text))
        self.assertEqual(run([str(a)], self.work).stdout, 'sum 6\n')
        self.assertEqual(run([str(b)], self.work).stdout, 'sum 6\n')

    def test_position_values_name_lean_lines_and_the_resolver_maps_them_back(self):
        text = ('// one\n// two\nfn main() {\n    // three\n    println!("line {}", line!());\n'
                '    // four\n    let v: Vec<u32> = Vec::new();\n    println!("{}", v[3]);\n}\n')
        lean = lean_of(text)
        a, b = build(self.work, 'authored', text), build(self.work, 'lean', lean)
        ra, rb = run([str(a)], self.work), run([str(b)], self.work)
        self.assertEqual((ra.stdout, rb.stdout), ('line 5\n', 'line 2\n'))      # three comment lines above it are gone
        self.assertEqual((ra.returncode, rb.returncode), (101, 101))
        pa, pb = (re.search(r'panicked at src/main\.rs:(\d+):(\d+):', r.stderr) for r in (ra, rb))
        self.assertEqual((pa.group(1), pb.group(1)), ('8', '4'))
        self.assertEqual(pa.group(2), pb.group(2))                       # no comment before it on its line: the column stays
        for lean_line, authored_line in ((2, 5), (4, 8)):
            self.assertEqual(locate.locate(text.encode(), lean.encode(), '/src/main.rs', lean_line, native=True).line, authored_line)
        # apart from the numbers the rule predicts, the two programs say the same
        same = [re.sub(r'main\.rs:\d+', 'main.rs:N', re.sub(r"'main' \(\d+\)", "'main'", r.stderr)) for r in (ra, rb)]
        self.assertEqual(same[0], same[1])

    def test_doc_comments_are_program_data(self):
        # how a derive such as clap's reads a doc comment: as the #[doc = "..."] attribute it is
        text = ('macro_rules! help { ($(#[doc = $d:expr])* fn $n:ident) => { const HELP: &[&str] = &[$($d),*]; fn $n() {} } }\n'
                '// ' + LONG + '\nhelp! {\n    /// Prints the answer.\n    /// Twice.\n    fn answer\n}\n'
                'fn main() { answer(); println!("{}", HELP.join("|")); }\n')
        lean = lean_of(text)
        self.assertIn('/// Prints the answer.', lean)
        a, b = build(self.work, 'authored', text), build(self.work, 'lean', lean)
        self.assertEqual(run([str(a)], self.work).stdout, ' Prints the answer.| Twice.\n')
        self.assertEqual(run([str(b)], self.work).stdout, ' Prints the answer.| Twice.\n')
        red = build(self.work, 'naive', naive(text))                     # red: the help text is gone
        self.assertEqual(run([str(red)], self.work).stdout, '\n')

    def test_missing_docs_fails_a_build_without_its_doc_comments(self):
        text = '#![deny(missing_docs)]\n//! A crate.\n// ' + LONG + '\n/// A function.\npub fn f() {}\n'
        for name, body, want in (('authored', text, 0), ('lean', lean_of(text), 0), ('naive', naive(text), 1)):
            src = Path(self.work) / name
            src.mkdir()
            (src / 'lib.rs').write_text(body)
            r = run([RUSTC, '--edition', '2021', '--crate-type', 'lib', '--emit', 'metadata', 'lib.rs'], src)
            self.assertEqual(r.returncode, want, f'{name}: {r.stderr}')
        self.assertIn('missing documentation', r.stderr)

    @unittest.skipUnless(shutil.which('rustdoc'), 'rustdoc required')
    def test_documentation_tests_still_run(self):
        text = ('//! A crate.\n// ' + LONG + '\n/// Adds one.\n///\n/// ```\n/// assert_eq!(doc::inc(1), 2);\n/// ```\n'
                'pub fn inc(x: u32) -> u32 { x + 1 } // trailing\n')
        counts = []
        for name, body in (('authored', text), ('lean', lean_of(text)), ('naive', naive(text))):
            src = Path(self.work) / name
            src.mkdir()
            (src / 'lib.rs').write_text(body)
            r = run([RUSTC, '--edition', '2021', '--crate-type', 'lib', '--crate-name', 'doc', 'lib.rs'], src)
            self.assertEqual(r.returncode, 0, r.stderr)
            r = run(['rustdoc', '--edition', '2021', '--test', '--crate-name', 'doc', '-L', '.', 'lib.rs'], src)
            counts.append(re.search(r'test result: ok\. (\d+) passed', r.stdout).group(1))
        self.assertEqual(counts, ['1', '1', '0'])                        # red: without the doc comment no test is left

    def tree(self, files, languages=('rust',)):
        root = Path(self.work) / 'tree'
        for name, body in files.items():
            (root / name).parent.mkdir(parents=True, exist_ok=True)
            (root / name).write_text(body)
        (root / 'debian').mkdir(exist_ok=True)
        (root / source_tree.LANGUAGE_PLAN).write_text(json.dumps(sorted(languages)))
        return root

    def report(self, root):
        return json.loads((root / '.sparky-lc/source.json').read_text())

    def test_a_file_read_with_include_str_stays_authored(self):
        data = '// ' + LONG + '\nfn unused() {}\n'
        main = '// ' + LONG + '\nconst DATA: &str = include_str!("data.rs");\nfn main() { println!("{}", DATA.len()); }\n'
        root = self.tree({'Cargo.toml': '[package]\nname = "t"\n', 'src/main.rs': main, 'src/data.rs': data})
        source_tree.project_tree(root)
        rows = self.report(root)['files']
        self.assertEqual(rows['src/main.rs']['status'], 'projected')
        self.assertEqual(rows['src/data.rs']['status'], 'left')
        self.assertIn('read as data by include_str!', rows['src/data.rs']['reason'])
        self.assertEqual((root / 'src/data.rs').read_text(), data)
        r = run([RUSTC, '--edition', '2021', '-o', 'prog', 'src/main.rs'], root)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(run([str(root / 'prog')], root).stdout, f'{len(data)}\n')
        (root / 'src/data.rs').write_text(lean_of(data))                 # red: the data projected too
        run([RUSTC, '--edition', '2021', '-o', 'prog', 'src/main.rs'], root)
        self.assertNotEqual(run([str(root / 'prog')], root).stdout, f'{len(data)}\n')
        (root / 'src/data.rs').write_text(data)
        source_tree.restore_tree(root)
        self.assertEqual((root / 'src/main.rs').read_text(), main)

    def test_a_crate_whose_build_script_reads_its_sources_stays_authored(self):
        # the generator counts the comment lines of src/lib.rs, as the kernel's Kbuild cuts at `// Cut here.`
        script = ('fn main() { let t = std::fs::read_to_string("src/lib.rs").unwrap();\n'
                  '    let n = t.lines().filter(|l| l.trim_start().starts_with("//")).count();\n'
                  '    std::fs::write("generated.rs", format!("pub const MARKS: usize = {n};\\n")).unwrap(); }\n')
        lib = '// Cut here.\n// ' + LONG + '\ninclude!("../generated.rs");\nfn main() { println!("{}", MARKS); }\n'
        other = '// ' + LONG + '\npub fn other() {}\n'
        root = self.tree({'reader/Cargo.toml': '[package]\nname = "reader"\n', 'reader/build.rs': script, 'reader/src/lib.rs': lib,
                          'plain/Cargo.toml': '[package]\nname = "plain"\n', 'plain/src/lib.rs': other})
        source_tree.project_tree(root)
        rows = self.report(root)['files']
        self.assertEqual(rows['plain/src/lib.rs']['status'], 'projected')
        self.assertEqual(rows['reader/src/lib.rs']['status'], 'left')
        self.assertIn("build script reads Rust source text", rows['reader/src/lib.rs']['reason'])

        def generated(body):
            (root / 'reader/src/lib.rs').write_text(body)
            for cmd in ([RUSTC, '--edition', '2021', '-o', 'build-script', 'build.rs'], ['./build-script'],
                        [RUSTC, '--edition', '2021', '-o', 'prog', 'src/lib.rs'], ['./prog']):
                r = run(cmd, root / 'reader')
                self.assertEqual(r.returncode, 0, r.stderr)
            return r.stdout
        self.assertEqual(generated(lib), '2\n')
        self.assertEqual(generated(lean_of(lib)), '0\n')                 # red: the generator's input, projected

    def test_a_macro_that_reads_its_callers_source_stops_the_projection_until_reviewed(self):
        macro = ('extern crate proc_macro;\nuse proc_macro::TokenStream;\n#[proc_macro]\npub fn text(i: TokenStream) -> TokenStream {\n'
                 '    let s = i.into_iter().next().and_then(|t| t.span().source_text()).unwrap_or_default();\n'
                 '    format!("{:?}", s).parse().unwrap()\n}\n')
        files = {'mac/Cargo.toml': '[package]\nname = "mac"\n[lib]\nproc-macro = true\n', 'mac/src/lib.rs': macro,
                 'app/Cargo.toml': '[package]\nname = "app"\n', 'app/src/main.rs': '// ' + LONG + '\nfn main() {}\n'}
        root = self.tree(files)
        with self.assertRaisesRegex(ValueError, r"Procedural macros that read their callers' source text.*mac: mac/src/lib.rs calls source_text"):
            source_tree.project_tree(root)
        self.assertFalse((root / '.sparky-lc/source.json').exists())
        self.assertEqual((root / 'app/src/main.rs').read_text(), files['app/src/main.rs'])
        (root / source_tree.RUST_READERS_PLAN).write_text(json.dumps({'mac': 'no crate of this tree calls text!()'}))
        source_tree.project_tree(root)
        self.assertEqual(self.report(root)['files']['app/src/main.rs']['status'], 'projected')

    def test_the_report_names_the_files_that_read_their_position(self):
        root = self.tree({'Cargo.toml': '[package]\nname = "t"\n',
                          'src/main.rs': '// ' + LONG + '\nfn main() { println!("{}", line!()); }\n',
                          'src/quiet.rs': '// ' + LONG + '\npub fn quiet() {}\n'})
        source_tree.project_tree(root)
        self.assertEqual(self.report(root)['position_lines'], {'src/main.rs': [2]})

    def test_rust_is_projected_only_under_a_language_plan(self):
        root = self.tree({'Cargo.toml': '[package]\nname = "t"\n', 'src/main.rs': '// ' + LONG + '\nfn main() {}\n',
                          'src/c.c': '/* ' + LONG + ' */\nint f(void) { return 1; }\n'}, languages=('c',))
        source_tree.project_tree(root)
        self.assertEqual(sorted(self.report(root)['files']), ['src/c.c'])

    @unittest.skipUnless(shutil.which('readelf'), 'readelf required')
    def test_machine_code_is_the_same_and_only_line_tables_and_locations_move(self):
        text = ('// ' + LONG + '\n#[inline(never)]\nfn work(v: &[u32]) -> u32 {\n    // ' + LONG + '\n    let mut s = 0u32;\n'
                '    for x in v { s = s.wrapping_mul(31).wrapping_add(*x); } // trailing\n    s\n}\n'
                'fn main() { println!("{}", work(&[1, 2, 3])); }\n')
        flags = ('-C', 'opt-level=2', '-C', 'debuginfo=2', '-C', 'codegen-units=1', '--remap-path-prefix', f'{self.work}=/w')
        a = build(self.work, 'authored', text, *flags)
        b = build(self.work, 'lean', lean_of(text), '--remap-path-prefix', f'{self.work}/lean=/w/authored', *flags)

        def section(prog, name):
            r = run(['readelf', '--hex-dump=' + name, str(prog)], self.work)
            self.assertEqual(r.returncode, 0, r.stderr)
            return r.stdout.split('\n', 2)[2]
        self.assertEqual(section(a, '.text'), section(b, '.text'))
        self.assertTrue(section(a, '.text'))
        self.assertNotEqual(section(a, '.debug_line'), section(b, '.debug_line'))


if __name__ == '__main__':
    unittest.main()
