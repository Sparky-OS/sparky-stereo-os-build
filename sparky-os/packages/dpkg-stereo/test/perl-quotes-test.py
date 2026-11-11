#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Installed upgrade proof in a disposable dpkg root (ordinary user in a container).

Usage: perl-quotes-test.py OLD_SPARKY_OS NEW_SPARKY_OS NEW_EMPTY_WORK
The old toolkit must be lean 0.1.24. Supplying it as NEW too is the red control.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import sys

old, new, work = (Path(p).resolve() for p in sys.argv[1:])
work.mkdir()
root = work / 'root'
pkg = work / 'package'
info = pkg / 'DEBIAN'
payload = pkg / 'usr/lib/perl-quote-test'
info.mkdir(parents=True)
payload.mkdir(parents=True)
header = '# outside explanation for the reader, preserved in the HR source\n' * 5
quote = 'my $pattern = qr{\n# pattern text\nabc\n}x;\nprint "abc" =~ $pattern;\n'
for name in ('quote.pl', 'edited.pl', 'held.pl'):
    (payload / name).write_text(header + quote)
(payload / 'stable.pl').write_text(header + 'print "stable";\n')
(payload / 'unsupported.pl').write_text(header + 'use Missing::Perl::Quote::Test;\n')
info.joinpath('control').write_text(
    'Package: perl-quote-test\nVersion: 1\nArchitecture: all\n'
    'Maintainer: Daniel Campos Ramos <Capitain_Jack@yahoo.com>\n'
    'Description: disposable Perl migration proof\n')
info.joinpath('md5sums').write_text(''.join(
    hashlib.md5(p.read_bytes()).hexdigest() + '  ' + str(p.relative_to(pkg)) + '\n'
    for p in sorted(payload.iterdir())))
deb = work / 'perl-quote-test_1_all.deb'
subprocess.run(['dpkg-deb', '--root-owner-group', '-b', str(pkg), str(deb)], check=True)
for path in ('var/lib/dpkg/info', 'var/lib/dpkg/updates', 'var/cache/apt/archives', 'var/log'):
    (root / path).mkdir(parents=True, exist_ok=True)
(root / 'var/lib/dpkg/status').touch()
subprocess.run(['dpkg', '--force-not-root', '--force-bad-path', '--force-script-chrootless',
                '--force-depends', '--log=' + str(root / 'var/log/dpkg.log'),
                '--root=' + str(root), '-i', str(deb)], check=True)


def ds(lib, label, *args):
    env = dict(os.environ, DPKG_STEREO_LIB=str(lib))
    r = subprocess.run(['python3', str(lib / 'packages/dpkg-stereo/bin/dpkg-stereo'),
                        '--root', str(root), *args], env=env, capture_output=True, text=True)
    (work / (label + '.log')).write_text(r.stdout + r.stderr)
    assert r.returncode == 0, (label, r.returncode, r.stdout, r.stderr)


ds(old, 'old', '--project', 'perl-quote-test')
state = root / 'var/lib/dpkg-stereo'
left = state / 'left/perl-quote-test.tsv'
assert left.read_text().count('check failed: B::Deparse prints a different program') == 3
assert (state / 'renderer-migration-0124-v1').exists()
print('PASS old renderer refuses all three quoted files', flush=True)
installed = root / 'usr/lib/perl-quote-test'
stable = (installed / 'stable.pl').read_bytes()
stable_stat = (installed / 'stable.pl').stat()
assert b'outside explanation' not in stable
edited = installed / 'edited.pl'
edited.write_text(edited.read_text() + 'print "my edit";\n')
edit_bytes = edited.read_bytes()
ds(old, 'hold', '--hold', '/usr/lib/perl-quote-test/held.pl')
held = (installed / 'held.pl').read_bytes()
unsupported = (installed / 'unsupported.pl').read_bytes()
ds(new, 'upgrade', '--repair-consumers', '--if-changed')
assert (state / 'renderer-migration-perl-quotes-0125-v1').exists(), 'new migration did not run'
assert b'outside explanation' not in (installed / 'quote.pl').read_bytes(), 'quote file still authored'
assert b'# pattern text' in (installed / 'quote.pl').read_bytes()
assert (installed / 'stable.pl').read_bytes() == stable
assert (installed / 'stable.pl').stat().st_mtime_ns == stable_stat.st_mtime_ns
assert edited.read_bytes() == edit_bytes
assert (installed / 'held.pl').read_bytes() == held
assert (installed / 'unsupported.pl').read_bytes() == unsupported
assert 'changed since its package installed it' in left.read_text()
assert 'authored script is not compiled by perl on its own' in left.read_text()
assert '/usr/lib/perl-quote-test/quote.pl' not in left.read_text()
print('PASS quote projected; stable projection, user edit, hold and unrelated refusal kept', flush=True)
rows = (state / 'records/perl-quote-test.tsv').read_text()
assert '/usr/lib/perl-quote-test/quote.pl' in rows and '/usr/lib/perl-quote-test/stable.pl' in rows
ds(new, 'verify', '--verify', 'perl-quote-test')
before = {p: (p.read_bytes(), p.stat().st_mtime_ns)
          for p in [*installed.iterdir(), state / 'records/perl-quote-test.tsv', left]}
ds(new, 'repeat', '--repair-consumers', '--if-changed')
assert all((p.read_bytes(), p.stat().st_mtime_ns) == value for p, value in before.items())
assert 'Perl quote refusals rechecked' not in (work / 'repeat.log').read_text()
print('PASS second migration is a no-op; verify passes', flush=True)
