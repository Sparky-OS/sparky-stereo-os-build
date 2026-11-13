#!/usr/bin/env python3
"""Small compiler-backed controls for source preparation; run in a container."""
import json
import os
from pathlib import Path
import tempfile
import unittest

from lean import lang_rust, locate, project
import prepare
import verify


class SourceControls(unittest.TestCase):
    def test_lexer_rejects_code_changes(self):
        a, changed = lang_rust.token_streams('fn main() { let a = 1; }', 'fn main() { let a = 2; }')
        with self.assertRaisesRegex(RuntimeError, 'form B'):
            prepare.assert_tokens(a, changed, a)
        with self.assertRaisesRegex(RuntimeError, 'form C'):
            prepare.assert_tokens(a, a, changed)

    def test_documentation_is_only_permitted_difference_in_c(self):
        a = '//! inner\n/// outer\nfn f() {}\n'
        b = a
        c = prepare.render_c(a)
        sa, sb, sc = lang_rust.token_streams(a, b, c)
        prepare.assert_tokens(sa, sb, sc)
        self.assertEqual(c, 'fn f() {}\n')
        with self.assertRaisesRegex(RuntimeError, 'form B'):
            prepare.assert_tokens(sa, sc, sc)

    def test_strings_notices_and_authored_empty_lines(self):
        a = '// Copyright 2026 Test\n\n// ordinary\n\n/// docs\nfn f() { let _ = r"/// data"; } // tail\n'
        c = prepare.render_c(a)
        self.assertEqual(c, '// Copyright 2026 Test\n\n\nfn f() { let _ = r"/// data"; }\n')

    def test_content_resolver_for_both_lean_forms(self):
        a = '// plain\n\n/// docs\npub fn unique() { panic!("failure"); }\n'
        b = project.render_text(a, 'rust', None, None, None, pointer=False)[0]
        c = prepare.render_c(a)
        for text in (b, c):
            line = next(i for i, value in enumerate(text.splitlines(), 1) if 'pub fn unique' in value)
            found = locate.locate(a.encode(), text.encode(), '/src/lib.rs', line, native=True)
            self.assertEqual(found.line, 4)

    def test_readers_include_sources_under_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'src/build').mkdir(parents=True)
            (root / 'src/build/input.rs').write_text('fn f() {}')
            (root / 'debian').mkdir()
            (root / 'debian/ignored.rs').write_text('not an input')
            self.assertEqual(list(prepare.entries(root)), ['src/build/input.rs'])

    def test_missing_docs_policy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'Cargo.toml').write_text('[package]\nname="sample"\nversion="0.1.0"\n')
            (root / 'lib.rs').write_text('#![deny(missing_docs)]\n/// docs\npub fn f() {}\n')
            owners, reasons = prepare.doc_policy(root, ['lib.rs'])
            self.assertEqual(owners['lib.rs'], '.')
            self.assertIn('deny/forbid(missing_docs)', reasons['.'][0])

    def test_compiler_query_macro_is_a_documentation_consumer(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'Cargo.toml').write_text('[package]\nname="sample"\nversion="0.1.0"\n')
            (root / 'lib.rs').write_text('rustc_queries! { /// text\n query sample() -> X {} }')
            _, reasons = prepare.doc_policy(root, ['lib.rs'])
            self.assertIn('rustc_queries! reads docs', reasons['.'][0])

    def test_checksum_update_rejects_wrong_original(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / '.cargo-checksum.json'
            path.write_text(json.dumps({'files': {'lib.rs': 'a'}, 'package': 'p'}))
            with self.assertRaisesRegex(RuntimeError, 'authored bytes'):
                prepare.checksum_update(root, {'lib.rs': ('x', 'b')})
            prepare.checksum_update(root, {'lib.rs': ('a', 'b')})
            self.assertEqual(json.loads(path.read_text()), {'files': {'lib.rs': 'b'}, 'package': 'p'})

    def test_checksum_reconciliation_requires_exact_reviewed_pair(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            p = root / '.cargo-checksum.json'
            p.write_text(json.dumps({'files': {'lib.rs': 'upstream'}, 'package': 'p'}))
            accepted = {'lib.rs': {'manifest_sha256': 'upstream', 'authored_sha256': 'patched'}}
            with self.assertRaisesRegex(RuntimeError, 'authored bytes'):
                prepare.checksum_update(root, {'lib.rs': ('unreviewed', 'lean')}, accepted)
            prepare.checksum_update(root, {'lib.rs': ('patched', 'lean')}, accepted)
            self.assertEqual(json.loads(p.read_text())['files']['lib.rs'], 'lean')

    def test_nested_output_is_refused_before_writing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaisesRegex(RuntimeError, 'disjoint'):
                prepare.prepare(root, root / 'nested')
            self.assertFalse((root / 'nested').exists())

    def test_guard_refuses_impossible_floor(self):
        with self.assertRaisesRegex(RuntimeError, 'space guard'):
            prepare.space(Path.cwd(), floor_gib=10**9)

    def test_inventory_detects_tampering(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'input.rs').write_text('original')
            first = prepare.inventory(root)
            (root / 'input.rs').write_text('modified')
            self.assertNotEqual(first['sha256'], prepare.inventory(root)['sha256'])

    def test_small_pipeline_and_corruption_control(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'authored'
            (root / 'src/build').mkdir(parents=True)
            (root / 'Cargo.toml').write_text('[package]\nname="sample"\nversion="0.1.0"\n')
            (root / 'src/lib.rs').write_text('// commentary\n/// function docs\npub fn f() {}\n')
            (root / 'src/build/unit.rs').write_text('// commentary\npub fn g() {}\n')
            data = '// data comment\n'
            (root / 'src/data.rs').write_text(data)
            (root / 'src/reader.rs').write_text('const INPUT: &str = include_str!("data.rs");\n')
            (root / 'src/nonutf8.rs').write_bytes(b'\xff')
            forms = Path(tmp) / 'forms'
            prepare.prepare(root, forms)
            verify.verify(root, forms)
            self.assertEqual((forms / 'B/src/lib.rs').read_text(), '/// function docs\npub fn f() {}\n')
            self.assertEqual((forms / 'C/src/lib.rs').read_text(), 'pub fn f() {}\n')
            self.assertEqual((forms / 'C/src/data.rs').read_text(), data)
            self.assertEqual((forms / 'B/src/build/unit.rs').read_text(), 'pub fn g() {}\n')
            (forms / 'C/src/lib.rs').write_text('pub fn forged() {}\n')
            with self.assertRaisesRegex(ValueError, 'changed, missing or extra'):
                verify.verify(root, forms)


if __name__ == '__main__':
    os.environ['LC_ALL'] = 'C'
    unittest.main(verbosity=2)
