#!/usr/bin/env python3
# link-config against a fixture apt: which sources it picks, how it reads Signed-By (a file, an inline armored key, none), and
# what it refuses. apt-cache is a stub that prints the output format of apt-cache(8) policy and depends.
import base64, json, os, subprocess, sys, tempfile, unittest
from pathlib import Path

LINK = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / 'lib' / 'link-config')

APT_CACHE = r'''#!/bin/sh
case "$1" in
policy)
	shift
	for n in "$@"; do
		case "$n" in
		ghost) continue ;;
		libfoo1)
			printf '%s:\n  Installed: (none)\n  Candidate: 2\n  Version table:\n     2 500\n        500 https://deb.example.org/debian forky/main amd64 Packages\n' "$n" ;;
		libbar1)
			printf '%s:\n  Installed: 1\n  Candidate: 1\n  Version table:\n *** 1 500\n        500 https://mm.example.org forky/non-free amd64 Packages\n        100 /var/lib/dpkg/status\n     0.9 500\n        500 https://old.example.org/ stable/main amd64 Packages\n' "$n" ;;
		libflat1)
			printf '%s:\n  Installed: (none)\n  Candidate: 3\n  Version table:\n     3 500\n        500 https://flat.example.org/repo/ /  Packages\n' "$n" ;;
		*)
			printf '%s:\n  Installed: (none)\n  Candidate: 1\n  Version table:\n     1 500\n        500 https://deb.example.org/debian forky/main amd64 Packages\n' "$n" ;;
		esac
	done ;;
depends)
	printf 'tool\n  Depends: libfoo1\n  Depends: libbar1\nlibfoo1\nlibbar1\n' ;;
esac
'''

KEY = bytes.fromhex('99010d04') + b'fixture-key-bytes'


def armored(data):
    body = base64.b64encode(data).decode()
    return '-----BEGIN PGP PUBLIC KEY BLOCK-----\n\n' + body + '\n=ABCD\n-----END PGP PUBLIC KEY BLOCK-----\n'


class LinkConfig(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='link-config-')
        t = Path(self.tmp.name)
        self.apt, self.out, self.bin = t / 'apt', t / 'out', t / 'bin'
        for d in (self.apt / 'sources.list.d', self.apt / 'trusted.gpg.d', self.out, self.bin):
            d.mkdir(parents=True)
        (self.bin / 'apt-cache').write_text(APT_CACHE)
        (self.bin / 'apt-cache').chmod(0o755)
        (t / 'plain.gpg').write_bytes(KEY)
        (self.apt / 'trusted.gpg.d' / 'a.asc').write_text(armored(KEY + b'-trusted'))

    def tearDown(self):
        self.tmp.cleanup()

    def run_link(self, *names):
        env = os.environ | {'PATH': f'{self.bin}:{os.environ["PATH"]}', 'SPARKY_FDK_APT_ETC': str(self.apt)}
        return subprocess.run([sys.executable, str(LINK), str(self.out), *(names or ('tool',))], env=env, text=True,
                              capture_output=True)

    def config(self):
        return json.loads((self.out / 'archive.json').read_text())

    def test_selects_only_the_sources_that_serve_the_build(self):
        t = Path(self.tmp.name)
        (self.apt / 'sources.list.d' / 'a.sources').write_text(
            f'Types: deb deb-src\nURIs: https://deb.example.org/debian/\nSuites: forky stable\nComponents: main contrib\n'
            f'Signed-By: {t}/plain.gpg\n\n'
            f'Types: deb\nURIs: https://mm.example.org\nSuites: forky\nComponents: main non-free\nSigned-By:\n'
            + ''.join(' ' + l + '\n' if l else ' .\n' for l in armored(KEY + b'-inline').split('\n')) + '\n'
            f'Types: deb\nURIs: https://unrelated.example.org\nSuites: x\nComponents: main\nSigned-By: {t}/plain.gpg\n')
        (self.apt / 'sources.list').write_text('deb https://old.example.org/ stable main\n')
        r = self.run_link()
        self.assertEqual(r.returncode, 0, r.stderr)
        got = {(c['uri'], c['suite']): c for c in self.config()}
        self.assertEqual(set(got), {('https://deb.example.org/debian', 'forky'), ('https://mm.example.org', 'forky')})
        self.assertEqual(got[('https://deb.example.org/debian', 'forky')]['components'], ['main'])
        self.assertEqual(got[('https://mm.example.org', 'forky')]['components'], ['non-free'])
        self.assertEqual(Path(got[('https://deb.example.org/debian', 'forky')]['keyring']).read_bytes(), KEY)
        self.assertEqual(Path(got[('https://mm.example.org', 'forky')]['keyring']).read_bytes(), KEY + b'-inline')

    def test_no_signed_by_takes_the_trusted_keyrings_and_a_flat_repository_works(self):
        (self.apt / 'sources.list').write_text(
            'deb [arch=amd64] https://deb.example.org/debian forky main\ndeb https://flat.example.org/repo/ ./\n')
        (self.apt / 'sources.list').write_text(
            'deb [arch=amd64] https://deb.example.org/debian forky main\ndeb https://flat.example.org/repo /\n')
        r = self.run_link('libfoo1', 'libflat1')
        self.assertEqual(r.returncode, 0, r.stderr)
        got = {c['uri']: c for c in self.config()}
        self.assertEqual(Path(got['https://deb.example.org/debian']['keyring']).read_bytes(), KEY + b'-trusted')
        self.assertEqual(got['https://deb.example.org/debian']['architectures'], ['amd64'])
        self.assertEqual(got['https://flat.example.org/repo']['components'], [])

    def test_refusals_say_what_and_write_nothing_usable(self):
        t = Path(self.tmp.name)
        cases = {
            'fingerprint': 'Signed-By: 0123456789ABCDEF0123456789ABCDEF01234567',
            'missing key file': f'Signed-By: {t}/absent.gpg',
            'trusted yes': f'Signed-By: {t}/plain.gpg\nTrusted: yes',
        }
        for name, extra in cases.items():
            with self.subTest(name):
                (self.apt / 'sources.list.d' / 'a.sources').write_text(
                    f'Types: deb\nURIs: https://deb.example.org/debian\nSuites: forky\nComponents: main\n{extra}\n')
                r = self.run_link('libfoo1')
                self.assertNotEqual(r.returncode, 0)
                self.assertIn('deb.example.org', r.stderr)
                self.assertFalse((self.out / 'archive.json').exists())
        (self.apt / 'sources.list.d' / 'a.sources').write_text(
            'Types: deb\nURIs: https://other.example.org\nSuites: forky\nComponents: main\n')
        r = self.run_link('libfoo1')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("none of apt's sources", r.stderr)
        r = self.run_link('ghost')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('apt knows none', r.stderr)


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0]], verbosity=2)
