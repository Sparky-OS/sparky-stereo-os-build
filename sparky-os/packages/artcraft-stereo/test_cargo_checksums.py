# SPDX-License-Identifier: MIT
import hashlib
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from lean import source_tree

MODULE = runpy.run_path(str(Path(__file__).with_name('cargo-checksums.py')))


@unittest.skipUnless(shutil.which('cargo') and shutil.which('gcc'), 'Cargo and GCC required')
class VendorChecksums(unittest.TestCase):
    def test_cargo_refuses_changed_source_until_exact_projection_is_bound(self):
        for vendor in ('vendor', 'third_party/rust'):
            with self.subTest(vendor=vendor):
                self.check_vendor(vendor)

    def check_vendor(self, vendor):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            crate = root / vendor / 'fixture-0.1.0'
            (crate / 'src').mkdir(parents=True)
            (crate / 'Cargo.toml').write_text('[package]\nname="fixture"\nversion="0.1.0"\nedition="2021"\n')
            (crate / 'src/lib.rs').write_text('pub fn value() -> i32 { 7 }\n')
            c_source = crate / 'native.c'
            authored = b'// The explanatory prose stays recoverable outside compiler input.\nint value(void) { return 7; }\n'
            c_source.write_bytes(authored)
            (crate / 'build.rs').write_text(
                'fn main() { let status = std::process::Command::new("gcc")'
                '.args(["-fsyntax-only", "native.c"]).status().unwrap(); assert!(status.success()); }\n')
            files = {p.relative_to(crate).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in crate.rglob('*') if p.is_file()}
            checksum = crate / '.cargo-checksum.json'
            original = json.dumps({'files': files, 'package': 'a' * 64}).encode()
            checksum.write_bytes(original)
            (root / '.cargo').mkdir()
            (root / '.cargo/config.toml').write_text(
                f'[source.crates-io]\nreplace-with="local"\n[source.local]\ndirectory="{vendor}"\n')
            (root / 'Cargo.toml').write_text(
                '[package]\nname="check-consumer"\nversion="0.1.0"\nedition="2021"\n'
                '[dependencies]\nfixture="=0.1.0"\n')
            (root / 'src').mkdir()
            (root / 'src/main.rs').write_text('fn main() { assert_eq!(fixture::value(), 7); }\n')
            source_tree.project_tree(root)
            self.assertNotEqual(c_source.read_bytes(), authored)
            command = ['cargo', 'run', '--offline', '--quiet']
            failed = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn('checksum', failed.stderr)
            MODULE['refresh'](root, vendor)
            subprocess.run(command, cwd=root, capture_output=True, check=True)
            self.assertEqual(json.loads(checksum.read_bytes())['package'], 'a' * 64)
            MODULE['restore'](root)
            source_tree.restore_tree(root)
            self.assertEqual(checksum.read_bytes(), original)
            self.assertEqual(c_source.read_bytes(), authored)
            # A changed Rust file has no C/C++ proof and must remain a refusal.
            (crate / 'src/lib.rs').write_text('pub fn value() -> i32 { 8 }\n')
            with self.assertRaisesRegex(ValueError, 'without matching projection'):
                MODULE['refresh'](root, vendor)
            self.assertEqual(checksum.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
