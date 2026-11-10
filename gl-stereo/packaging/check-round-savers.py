#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Publication gate (ORDER 146e): a round's gl-stereo-savers must offer every saver it ships.

The receipts in gl-stereo-savers bind the hash of every saver executable, settings file and
the layer. They are only true against the XScreenSaver build they were proved on, so a round
that carries another build leaves most savers out of the person's catalogue (the published
gl-stereo 0.4.2 offered 1 of 132 against xscreensaver +stereo3d4+lc1). This gate unpacks the
round's own packages and asks the package's catalogue code (savers/catalogue.py, the code the
controller and the saver list run) which receipts it can offer, and refuses the round when any
is left out; every saver it refuses is named with the differing file and both hashes. It also
refuses a gl-stereo-savers whose Depends does not pin every XScreenSaver package it binds to
the exact version the round carries.

Usage:
  check-round-savers.py --index REPO [--suite mashtabba] [--arch amd64]   a finished tree (dists/ and pool/)
  check-round-savers.py --debs DIR [DIR...]                               loose .deb files; the newest of each package
Exit 0: all offered and pinned. Exit 1: the round is refused. Exit 2: the gate could not run
(no gl-stereo-savers, no xscreensaver package, unreadable archive): a gate that cannot look refuses too.
"""
import argparse
import gzip
import io
import json
import lzma
import re
import sys
import tarfile
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'savers'))
import catalogue as saver_catalogue  # noqa: E402

SAVERS, LAYER, SOURCE_PREFIX = 'gl-stereo-savers', 'gl-stereo', 'xscreensaver'


def _order(char):
    if char == '~':
        return -1
    if char.isdigit() or char == '':
        return 0
    return ord(char) if char.isalpha() else ord(char) + 256


def _verrevcmp(a, b):
    """dpkg's verrevcmp (Policy 5.6.12): non-digit runs by character order with ~ lowest, then digit runs as numbers."""
    i = j = 0
    while i < len(a) or j < len(b):
        while (i < len(a) and not a[i].isdigit()) or (j < len(b) and not b[j].isdigit()):
            ca = _order(a[i]) if i < len(a) else 0
            cb = _order(b[j]) if j < len(b) else 0
            if ca != cb:
                return ca - cb
            i += 1
            j += 1
        ni = nj = 0
        while i < len(a) and a[i].isdigit():
            ni, i = ni * 10 + int(a[i]), i + 1
        while j < len(b) and b[j].isdigit():
            nj, j = nj * 10 + int(b[j]), j + 1
        if ni != nj:
            return ni - nj
    return 0


def cmp_versions(a, b):
    def split(version):
        epoch, colon, rest = version.partition(':')
        if not colon:
            epoch, rest = '0', version
        upstream, dash, revision = rest.rpartition('-')
        return int(epoch), (upstream if dash else rest), (revision if dash else '')
    (ea, ua, ra), (eb, ub, rb) = split(a), split(b)
    for result in (ea - eb, _verrevcmp(ua, ub), _verrevcmp(ra, rb)):
        if result:
            return 1 if result > 0 else -1
    return 0


def ar_members(data):
    if data[:8] != b'!<arch>\n':
        raise ValueError('not a deb')
    pos = 8
    while pos + 60 <= len(data):
        name = data[pos:pos+16].decode().strip().rstrip('/')
        size = int(data[pos+48:pos+58])
        yield name, data[pos+60:pos+60+size]
        pos += 60 + size + (size & 1)


def open_tar(name, blob):
    if name.endswith('.xz'):
        blob = lzma.decompress(blob)
    elif name.endswith('.gz'):
        blob = gzip.decompress(blob)
    elif name.endswith('.zst'):
        raise ValueError('zstd member %s: not readable here' % name)
    return tarfile.open(fileobj=io.BytesIO(blob))


def deb_control(path):
    for name, blob in ar_members(Path(path).read_bytes()):
        if name.startswith('control.tar'):
            with open_tar(name, blob) as tar:
                return parse_stanza(tar.extractfile('./control' if './control' in tar.getnames() else 'control').read().decode())
    raise ValueError('%s has no control member' % path)


def deb_extract(path, root):
    for name, blob in ar_members(Path(path).read_bytes()):
        if name.startswith('data.tar'):
            with open_tar(name, blob) as tar:
                tar.extractall(root, filter='tar')
            return
    raise ValueError('%s has no data member' % path)


def deb_names(path):
    for name, blob in ar_members(Path(path).read_bytes()):
        if name.startswith('data.tar'):
            with open_tar(name, blob) as tar:
                return {'/' + member.name.lstrip('./') for member in tar.getmembers() if not member.isdir()}
    raise ValueError('%s has no data member' % path)


def parse_stanza(text):
    fields, key = {}, None
    for line in text.splitlines():
        if line[:1] in ' \t' and key:
            fields[key] += '\n' + line
        elif ':' in line:
            key, _, value = line.partition(':')
            fields[key] = value.strip()
    return fields


def from_index(repo, suite, arch):
    base = Path(repo) / 'dists' / suite / 'main' / ('binary-' + arch)
    for name, opener in (('Packages.xz', lzma.open), ('Packages.gz', gzip.open), ('Packages', open)):
        if (base / name).exists():
            text = opener(base / name, 'rt', encoding='utf-8').read() if name != 'Packages' else (base / name).read_text()
            break
    else:
        raise SystemExit('gate cannot run: no Packages index under %s' % base)
    found = {}
    for block in text.split('\n\n'):
        if not block.strip():
            continue
        fields = parse_stanza(block)
        name = fields['Package']
        if name not in found or cmp_versions(fields['Version'], found[name]['Version']) > 0:
            found[name] = dict(fields, path=Path(repo) / fields['Filename'])
    return found


def from_debs(folders):
    found = {}
    for folder in folders:
        for deb in sorted(Path(folder).glob('*.deb')):
            if not (deb.name.startswith(SAVERS + '_') or deb.name.startswith(LAYER + '_') or deb.name.startswith(SOURCE_PREFIX)):
                continue
            fields = deb_control(deb)
            name = fields['Package']
            if name not in found or cmp_versions(fields['Version'], found[name]['Version']) > 0:
                found[name] = dict(fields, path=deb.resolve())
    return found


def is_xscreensaver(fields):
    return fields.get('Source', '').split(' ')[0] == SOURCE_PREFIX or fields['Package'].startswith(SOURCE_PREFIX)


def pin_problems(savers, packages):
    """Every XScreenSaver package the round carries and gl-stereo-savers needs must be named with (= its version)."""
    problems, pinned = [], 0
    for item in re.split(r',\s*', savers.get('Depends', '').replace('\n', ' ')):
        for alternative in item.split('|'):
            match = re.match(r'\s*([a-z0-9.+-]+)(?::\w+)?\s*(?:\((=|>=|<=|<<|>>)\s*([^)]+)\))?', alternative)
            if not match or match.group(1) not in packages or not is_xscreensaver(packages[match.group(1)]):
                continue
            name, op, wanted = match.groups()
            carried = packages[name]['Version']
            if op != '=':
                problems.append('Depends on %s is "%s%s", not an exact version: the round carries %s' % (name, op or '', ' ' + wanted if wanted else '', carried))
            elif wanted.strip() != carried:
                problems.append('Depends on %s (= %s) but the round carries %s' % (name, wanted.strip(), carried))
            else:
                pinned += 1
    if not pinned and not problems:
        problems.append('Depends names no XScreenSaver package with an exact version')
    return problems


def unpinned_owners(entries, savers, packages, xscreensaver):
    """Packages that own a file a receipt binds must be in Depends: a pin on gl alone leaves the settings files free."""
    owners = {}
    for name in xscreensaver:
        for path in deb_names(packages[name]['path']):
            owners.setdefault(path, name)
    needed = set()
    for entry in entries:
        for path in (entry['command'][0], '/usr/share/xscreensaver/config/%s.xml' % entry['id']):
            if path in owners:
                needed.add(owners[path])
    depends = savers.get('Depends', '')
    return ['%s owns a file the receipts bind and Depends does not pin its exact version' % name
            for name in sorted(needed) if not re.search(r'(^|[ ,|])%s\s*\(= ' % re.escape(name), depends.replace('\n', ' '))]


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    where = parser.add_mutually_exclusive_group(required=True)
    where.add_argument('--index', metavar='REPO')
    where.add_argument('--debs', nargs='+', metavar='DIR')
    parser.add_argument('--suite', default='mashtabba')
    parser.add_argument('--arch', default='amd64')
    args = parser.parse_args(argv)
    try:
        packages = from_index(args.index, args.suite, args.arch) if args.index else from_debs(args.debs)
    except (OSError, ValueError, KeyError) as error:
        print('gate cannot run: %s' % error)
        return 2
    xscreensaver = sorted(name for name, fields in packages.items() if is_xscreensaver(fields) and not name.endswith('-dbgsym'))
    if SAVERS not in packages or LAYER not in packages or not xscreensaver:
        print('gate cannot run: the round needs %s, %s and the xscreensaver packages (found: %s)' % (SAVERS, LAYER, ', '.join(sorted(packages)) or 'none'))
        return 2
    savers = packages[SAVERS]
    print('gl-stereo-savers %s against xscreensaver %s' % (savers['Version'], ', '.join(sorted({packages[n]['Version'] for n in xscreensaver}))))
    refused = False
    with tempfile.TemporaryDirectory(prefix='check-round-savers-') as root:
        try:
            for name in [LAYER, SAVERS] + xscreensaver:
                deb_extract(packages[name]['path'], root)
            share = Path(root) / 'usr/share/gl-stereo'
            entries = json.loads((share / 'catalogue.json').read_text())
            inventory = json.loads((share / 'savers.json').read_text())
        except (OSError, ValueError, KeyError, tarfile.TarError, lzma.LZMAError) as error:
            print('gate cannot run: %s' % error)
            return 2
        shipped = len([entry for entry in inventory if entry.get('kind', 'hack') == 'hack'])
        gone = saver_catalogue.dropped(entries, root)
        offered = len(entries) - len(gone)
        for name, reasons in gone:
            for reason in reasons:
                print('REFUSED %s: %s' % (name, saver_catalogue.describe(reason)))
        print('catalogue: %d of %d savers can be offered (%d receipts)' % (offered, shipped, len(entries)))
        if gone or offered < shipped:
            refused = True
    for problem in pin_problems(savers, packages) + unpinned_owners(entries, savers, packages, xscreensaver):
        print('REFUSED gl-stereo-savers %s: %s' % (savers['Version'], problem))
        refused = True
    print('GATE %s' % ('REFUSES THE ROUND' if refused else 'PASSES'))
    return 1 if refused else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
