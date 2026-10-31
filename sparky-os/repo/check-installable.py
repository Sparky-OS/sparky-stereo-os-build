#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/31
# Copyright 2026 under the GNU GPL3 License
"""check-installable.py: can every package of the edition's repository tree be installed, today,
on a fresh Sparky Stereo OS, from the archives the edition uses (ORDER 317)?

A package of ours can become uninstallable after we published it, without any change on our side:
Debian testing moves a library to a new soname (kdenlive 26.08.1-1+stereo3d5+lc1 depends on
libkddockwidgets-qt6-3, which left testing for libkddockwidgets-qt6-4), drops a package, or
replaces an exact-version ABI. This tool finds those packages before a person meets them.

For every binary package in the tree's indexes (every architecture, dbgsym and lc-hr companions
included) it asks:
  apt     apt-get --simulate install NAME:ARCH=VERSION from an empty dpkg status, with the archives
          and the apt policy an installed edition has (the solver a person's machine runs; the verdict);
  static  which Depends or Pre-Depends relation, reachable from the package, nothing in the
          archives satisfies (the cause, named; with the likely successor of a vanished library);
  dose    Debian's dose-debcheck (dose-distcheck), when it is installed: a complete search over the
          same indexes, with its own explanation (apt's solver can give up where a solution exists).
The engines run in that order; dose is used when dose-debcheck is on PATH, unless --engines says otherwise.

Archives: the signed public sources of SPARKY_LC_ARCHIVE_CONFIG (Debian forky, deb-multimedia forky,
SparkyLinux core and tiamat; sparky-os/lean/archive.md describes the file), and, in the nvidia profile,
NVIDIA's CUDA repository as sparky-stereo-hardware sets it up (its URL, key checksum and pin are read
from that package's sources). The tree itself is read through its dists only: its Release is checked
against its own InRelease and key (sparky-stereo-repo.asc in the tree), its indexes against the
Release, and a copy of the indexes in scratch is what apt reads (nothing in pool/ is copied or linked).
Policy: the preferences.d files of the tree's sparky-stereo-apt, sparky-stereo-hardware and
sparky-stereo-nvidia-driver-lock and of SparkyLinux's sparky-apt (read from the packages themselves),
and in the nvidia profile the CUDA pin of the hardware setup.

Profiles: base (every install), nvidia (base plus the CUDA repository at 1002, what the hardware setup
adds on a machine with an NVIDIA card), arm64 (the arm64 packages, in an arm64 universe).
A package fails a profile when the apt engine says it cannot be installed there.

Output (--report DIR): installable.tsv (one row per package and profile that fails), summary.txt,
apt/ (the solver's words for each failure), dose-PROFILE.yaml, metadata.json (sources, signed index
hashes, policy files and their hashes, versions of apt and dose).
Exit status: 0 in --mode report (the publication's report); in --mode refuse, 1 when a failing
package is not listed in --known (package<TAB>version or *<TAB>reason), so a known, explained failure
does not stop every publication while it waits for its rebuild.

Usage: check-installable.py TREE [--codename mashtabba] [--archive-config JSON] [--scratch DIR]
         [--report DIR] [--profiles base,nvidia,arm64] [--engines apt,static,dose] [--jobs 4]
         [--unsigned] [--mode report|refuse] [--known FILE] [--only NAME[,NAME...]]
  --unsigned: the tree's indexes were just written by publish-tree.sh and Release is not signed yet;
              read them as they are (the publisher's own files of this run).
Settings: SPARKY_LC_ARCHIVE_CONFIG, SPARKY_LC_SCRATCH (scratch defaults to its installable/ folder).
Floors: 2 GiB free on scratch and 12 GiB on / (raise with --min-free-gib and --root-min-free-gib).
"""
import argparse
import concurrent.futures
import fnmatch
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPARKY_OS = HERE.parent
HARDWARE = SPARKY_OS / 'packages' / 'sparky-stereo-hardware'
POLICY_PACKAGES = ('sparky-stereo-apt', 'sparky-stereo-hardware', 'sparky-stereo-nvidia-driver-lock')
COMPANIONS = ('-dbgsym', '-lc-hr')
ORIGIN = 'Sparky Stereo OS'
CUDA_BASE = None


class Stop(Exception):
    pass


# Debian version ordering (Debian Policy 5.6.12), as publish-tree.sh orders versions.
def _order(c):
    if c == '~':
        return -1
    if c.isalpha():
        return ord(c)
    return ord(c) + 256


def _cmp_part(a, b):
    while a or b:
        i = 0
        while i < len(a) and not a[i].isdigit():
            i += 1
        j = 0
        while j < len(b) and not b[j].isdigit():
            j += 1
        pa, pb = a[:i], b[:j]
        a, b = a[i:], b[j:]
        for k in range(max(len(pa), len(pb))):
            ca = _order(pa[k]) if k < len(pa) else 0
            cb = _order(pb[k]) if k < len(pb) else 0
            if ca != cb:
                return -1 if ca < cb else 1
        i = 0
        while i < len(a) and a[i].isdigit():
            i += 1
        j = 0
        while j < len(b) and b[j].isdigit():
            j += 1
        na, nb = int(a[:i] or 0), int(b[:j] or 0)
        a, b = a[i:], b[j:]
        if na != nb:
            return -1 if na < nb else 1
    return 0


def _split(v):
    epoch = 0
    if ':' in v:
        e, v = v.split(':', 1)
        epoch = int(e)
    rev = ''
    if '-' in v:
        v, rev = v.rsplit('-', 1)
    return epoch, v, rev


def vercmp(x, y):
    ex, ux, rx = _split(x)
    ey, uy, ry = _split(y)
    if ex != ey:
        return -1 if ex < ey else 1
    return _cmp_part(ux, uy) or _cmp_part(rx, ry)


def satisfies(version, op, wanted):
    if op is None:
        return True
    c = vercmp(version, wanted)
    return {'<<': c < 0, '<=': c <= 0, '=': c == 0, '>=': c >= 0, '>>': c > 0, '<': c <= 0, '>': c >= 0}[op]


def stanzas(text):
    for block in text.split('\n\n'):
        fields, key = {}, None
        for line in block.split('\n'):
            if not line:
                continue
            if line[0] in ' \t' and key:
                fields[key] += '\n' + line
            elif ':' in line:
                key, value = line.split(':', 1)
                fields[key] = value.strip()
        if fields:
            yield fields, block


REL = re.compile(r'^\s*([a-z0-9][a-z0-9+.-]*)(?::([a-z0-9-]+))?\s*(?:\(\s*(<<|<=|=|>=|>>|<|>)\s*([^)\s]+)\s*\))?\s*(?:\[[^]]*\])?\s*(?:<[^>]*>\s*)*$')


def relations(text):
    """Depends-style field: a list of clauses, each a list of (name, archqual, op, version)."""
    out = []
    for clause in (text or '').replace('\n', ' ').split(','):
        alts = []
        for alt in clause.split('|'):
            if not alt.strip():
                continue
            m = REL.match(alt)
            # An unparsable relation (an unexpanded substvar, say) is kept as a name nothing provides.
            alts.append(m.groups() if m else (alt.strip(), None, None, None))
        if alts:
            out.append(alts)
    return out


def show(rel):
    name, qual, op, ver = rel
    return name + (':' + qual if qual else '') + (' (%s %s)' % (op, ver) if op else '')


def free(path):
    st = os.statvfs(path)
    return st.f_bavail * st.f_frsize


def digest(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def run(args, env=None, cwd=None, check=True, timeout=900):
    proc = subprocess.run(args, env=env, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    if check and proc.returncode:
        raise Stop('%s failed (%d):\n%s' % (' '.join(map(str, args)), proc.returncode, (proc.stdout + proc.stderr)[-4000:]))
    return proc


def tree_release(tree, codename, unsigned, scratch):
    """The tree's Release fields and its verified index files, read only through dists/."""
    dists = tree / 'dists' / codename
    release = dists / 'Release'
    if unsigned:
        fields = dict(next(stanzas(release.read_text()))[0]) if release.is_file() else {}
        indexes = sorted(p for p in (dists / 'main').glob('binary-*/Packages') if p.is_file())
        if not indexes:
            raise Stop('no indexes in ' + str(dists / 'main'))
        return fields, indexes, {'signature': 'not checked (--unsigned: the publisher wrote these indexes in this run)'}
    key = tree / 'sparky-stereo-repo.asc'
    keyring = scratch / 'tree-key.gpg'
    keyring.unlink(missing_ok=True)
    home = scratch / 'gnupg'
    home.mkdir(mode=0o700, exist_ok=True)
    run(['gpg', '--homedir', str(home), '--batch', '--yes', '--dearmor', '-o', str(keyring), str(key)])
    verify = run(['gpgv', '--keyring', str(keyring), '--output', str(scratch / 'tree-InRelease.txt'), str(dists / 'InRelease')])
    signed = (scratch / 'tree-InRelease.txt').read_text()
    if signed != release.read_text():
        raise Stop('dists/%s/Release differs from the text its InRelease signs' % codename)
    run(['gpgv', '--keyring', str(keyring), str(dists / 'Release.gpg'), str(release)])
    fields = next(stanzas(signed))[0]
    sums = {}
    for line in fields.get('SHA256', '').splitlines():
        parts = line.split()
        if len(parts) == 3:
            sums[parts[2]] = (parts[0], int(parts[1]))
    indexes = []
    for rel, (h, size) in sorted(sums.items()):
        if re.fullmatch(r'main/binary-[a-z0-9]+/Packages', rel):
            path = dists / rel
            if path.stat().st_size != size or digest(path) != h:
                raise Stop('index differs from the signed Release: ' + str(path))
            indexes.append(path)
    if not indexes:
        raise Stop('the signed Release names no uncompressed binary Packages index')
    return fields, indexes, {'signature': 'InRelease and Release.gpg verified with ' + str(key),
                             'key_sha256': digest(key), 'gpgv': verify.stderr.strip().splitlines()[-1:]}


def policy_files(tree, index_entries, scratch):
    """preferences.d files of the edition's policy packages, read from the tree's own .debs."""
    out = {}
    for name in POLICY_PACKAGES:
        found = [e for e in index_entries if e['Package'] == name]
        if not found:
            raise Stop('the tree has no %s: its apt policy cannot be read' % name)
        best = max(found, key=lambda e: _Key(e['Version']))
        deb = tree / best['Filename']
        if deb.stat().st_size != int(best['Size']) or digest(deb) != best['SHA256']:
            raise Stop('pool file differs from its index: ' + str(deb))
        out.update(preferences_from_deb(deb, name + ' ' + best['Version']))
    return out


class _Key:
    def __init__(self, v):
        self.v = v

    def __lt__(self, other):
        return vercmp(self.v, other.v) < 0


def preferences_from_deb(deb, label):
    data = subprocess.run(['dpkg-deb', '--fsys-tarfile', str(deb)], capture_output=True, check=True).stdout
    out = {}
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for member in tar.getmembers():
            path = member.name.lstrip('./')
            if member.isfile() and path.startswith('etc/apt/preferences.d/'):
                out[Path(path).name] = (tar.extractfile(member).read().decode(), label)
    return out


def cuda_setup():
    """URL, key checksum and pin of the CUDA repository, as sparky-stereo-hardware's setup writes them."""
    actions = (HARDWARE / 'lib' / 'actions.sh').read_text()
    key = (HARDWARE / 'share' / 'cuda-key.sh').read_text()
    m_base = re.search(r'^\s*local base=(https://\S+)$', actions, re.M)
    m_sum = re.search(r'^CUDA_KEY_SHA256=([0-9a-f]{64})$', key, re.M)
    m_pin = re.search(r'cat >"\$pin" <<\'EOF\' \|\| return 1\n(.*?)\nEOF\n', actions, re.S)
    m_name = re.search(r'local pin="\$ROOT/etc/apt/preferences\.d/([^"]+)"', actions)
    if not (m_base and m_sum and m_pin and m_name):
        raise Stop('cannot read the CUDA repository setup from ' + str(HARDWARE))
    return m_base.group(1), m_sum.group(1), m_pin.group(1) + '\n', m_name.group(1)


class Universe:
    """One apt state: the public archives, the tree's copied indexes, the edition's policy."""

    def __init__(self, name, base, arches, sources, cuda, tree_fields, tree_indexes, codename, prefs):
        self.name, self.base, self.arches = name, base, arches
        self.native = arches[0]
        self.env = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LC_ALL': 'C.UTF-8', 'LANGUAGE': 'C',
                    'DEBIAN_FRONTEND': 'noninteractive', 'HOME': str(base), 'APT_CONFIG': str(base / 'apt.conf')}
        for d in ('etc/parts', 'etc/sources.list.d', 'etc/preferences.d', 'etc/auth.conf.d', 'etc/trusted.gpg.d',
                  'state/lists/partial', 'cache/archives/partial', 'log', 'keys', 'policy'):
            (base / d).mkdir(parents=True, exist_ok=True)
        (base / 'state/status').write_text('')
        for f in ('etc/apt.conf', 'etc/preferences'):
            (base / f).write_text('')
        for old in (base / 'etc/preferences.d').iterdir():
            old.unlink()
        lines = []
        archs = ','.join(arches)
        for i, source in enumerate(sources):
            keyfile = base / 'keys' / ('archive-%d.gpg' % i)
            shutil.copyfile(source['keyring'], keyfile)
            opts = 'arch=%s signed-by=%s' % (archs, keyfile)
            if source.get('check_valid_until', True) is False:
                opts += ' check-valid-until=no'
            lines.append('deb [%s] %s %s %s\n' % (opts, source['uri'].rstrip('/'), source['suite'], ' '.join(source['components'])))
        if cuda:
            lines.append('deb [arch=%s signed-by=%s] %s/ /\n' % (archs, cuda, CUDA_BASE))
        # The tree's indexes, copied with a Release that carries the tree's own Origin, so the
        # edition's pins (o=Sparky Stereo OS) apply as on an installed system.
        local = base / 'edition'
        if local.exists():
            shutil.rmtree(local)
        dists = local / 'dists' / codename
        for index in tree_indexes:
            target = dists / 'main' / index.parent.name / 'Packages'
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(index, target)
        rel = ['Origin: ' + tree_fields.get('Origin', ORIGIN), 'Label: ' + tree_fields.get('Label', ORIGIN),
               'Suite: ' + tree_fields.get('Suite', 'testing'), 'Codename: ' + codename,
               'Architectures: ' + ' '.join(sorted({p.parent.name[len('binary-'):] for p in tree_indexes})),
               'Components: main', 'SHA256:']
        for index in tree_indexes:
            target = dists / 'main' / index.parent.name / 'Packages'
            rel.append(' %s %16d main/%s/Packages' % (digest(target), target.stat().st_size, index.parent.name))
        (dists / 'Release').write_text('\n'.join(rel) + '\n')
        lines.append('deb [arch=%s trusted=yes] file:%s %s main\n' % (archs, local, codename))
        (base / 'etc/sources.list').write_text(''.join(lines))
        self.prefs = {}
        for fname, (text, label) in sorted(prefs.items()):
            (base / 'etc/preferences.d' / fname).write_text(text)
            self.prefs[fname] = {'from': label, 'sha256': hashlib.sha256(text.encode()).hexdigest()}
        options = {
            'Dir::Etc': base / 'etc', 'Dir::Etc::main': 'apt.conf', 'Dir::Etc::parts': 'parts',
            'Dir::Etc::sourcelist': 'sources.list', 'Dir::Etc::sourceparts': 'sources.list.d',
            'Dir::Etc::preferences': 'preferences', 'Dir::Etc::preferencesparts': 'preferences.d',
            'Dir::Etc::netrc': 'auth.conf', 'Dir::Etc::netrcparts': 'auth.conf.d', 'Dir::Etc::trusted': 'trusted.gpg',
            'Dir::Etc::trustedparts': 'trusted.gpg.d', 'Dir::State': base / 'state',
            'Dir::State::status': base / 'state/status', 'Dir::State::extended_states': base / 'state/extended_states',
            'Dir::Cache': base / 'cache', 'Dir::Cache::pkgcache': base / 'cache/pkgcache.bin',
            'Dir::Cache::srcpkgcache': base / 'cache/srcpkgcache.bin', 'Dir::Log': base / 'log',
            'APT::Architecture': self.native, 'APT::Install-Recommends': 'false', 'APT::Install-Suggests': 'false',
            'APT::Get::List-Cleanup': 'false', 'APT::Get::AllowUnauthenticated': 'false',
            'Acquire::AllowInsecureRepositories': 'false', 'Acquire::AllowDowngradeToInsecureRepositories': 'false',
            'Acquire::Languages': 'none', 'Acquire::IndexTargets::deb::Contents-deb::DefaultEnabled': 'false',
            'Acquire::Retries': '2', 'Acquire::https::Timeout': '60', 'APT::Sandbox::User': str(os.getuid()),
            'Debug::NoLocking': 'true',
        }
        conf = ''.join('%s "%s";\n' % (k, v) for k, v in options.items())
        conf += 'APT::Architectures { %s };\n' % ' '.join('"%s";' % a for a in arches)
        (base / 'apt.conf').write_text(conf)

    def apt(self, args, check=True, timeout=900):
        return run(args, env=self.env, cwd=self.base, check=check, timeout=timeout)

    def update(self):
        self.apt(['apt-get', '-q', '-o', 'APT::Update::Error-Mode=any', 'update'])
        self.apt(['apt-cache', 'gencaches'])

    def targets(self):
        """(list file, origin, architecture) of every Packages index apt read."""
        meta = self.apt(['apt-get', 'indextargets', 'Identifier: Packages']).stdout
        result = []
        for fields, _ in stanzas(meta):
            path = Path(fields.get('Filename', ''))
            if not path.is_file():
                continue
            result.append((path, fields.get('Origin', ''), fields.get('Architecture', ''), fields.get('Label', ''),
                           fields.get('Repo-URI', '')))
        return result

    def simulate(self, name, arch, version):
        spec = '%s=%s' % (name, version) if arch == 'all' else '%s:%s=%s' % (name, arch, version)
        p = self.apt(['apt-get', '--simulate', '-q', '--no-install-recommends', 'install', spec], check=False, timeout=300)
        return p.returncode == 0, (p.stdout + p.stderr)


DOSE_FIELDS = ('Package', 'Version', 'Architecture', 'Multi-Arch', 'Essential', 'Source',
               'Pre-Depends', 'Depends', 'Conflicts', 'Breaks', 'Provides')


def dose_stanza(fields):
    # Only what installability reads, each on one line: dose-debcheck refuses a relation folded over several lines
    # (SparkyLinux's sunflower) and an Installed-Size with a unit (both on 31 Oct 2026), which apt accepts.
    return '\n'.join('%s: %s' % (k, ' '.join(fields[k].split())) for k in DOSE_FIELDS if k in fields)


def read_list(path):
    name = str(path)
    if name.endswith(('.xz', '.lz4', '.gz', '.zst', '.bz2')):
        return subprocess.run(['/usr/lib/apt/apt-helper', 'cat-file', name], capture_output=True, text=True, check=True).stdout
    return path.read_text(errors='replace')


class Pins:
    """The negative records of the edition's apt policy, for the static engine and dose.
    apt applies the whole policy itself; these two engines only leave out what apt would never install."""

    def __init__(self, prefs):
        self.records = []
        for fname in sorted(prefs):
            for fields, _ in stanzas(prefs[fname][0]):
                if 'Package' not in fields or 'Pin' not in fields:
                    continue
                try:
                    prio = int(fields.get('Pin-Priority', '0'))
                except ValueError:
                    continue
                self.records.append((fields['Package'].split(), fields['Pin'].strip(), prio))

    @staticmethod
    def _name(patterns, name):
        for p in patterns:
            if p.startswith('/') and p.endswith('/') and len(p) > 1:
                if re.search(p[1:-1], name):
                    return True
            elif fnmatch.fnmatchcase(name, p):
                return True
        return False

    @staticmethod
    def _pin(pin, entry):
        kind, _, value = pin.partition(' ')
        value = value.strip()
        if kind == 'release':
            for part in value.split(','):
                k, _, v = part.strip().partition('=')
                field = {'o': 'origin', 'l': 'label', 'a': 'suite', 'n': 'codename', 'c': 'component'}.get(k)
                if field != 'origin':
                    return False
                if entry['_origin'] != v:
                    return False
            return True
        if kind == 'origin':
            return entry['_host'] == value.strip('"')
        if kind == 'version':
            if value.startswith('/') and value.endswith('/'):
                return re.search(value[1:-1], entry['Version']) is not None
            return fnmatch.fnmatchcase(entry['Version'], value)
        return False

    def blocked(self, entry):
        specific = [r for r in self.records if r[0] != ['*']]
        general = [r for r in self.records if r[0] == ['*']]
        for names, pin, prio in specific:
            if self._name(names, entry['Package']) and self._pin(pin, entry):
                return prio < 0
        for names, pin, prio in general:
            if self._pin(pin, entry):
                return prio < 0
        return False


class Index:
    def __init__(self, native, foreign):
        self.native, self.foreign = native, foreign
        self.by_name, self.provides = {}, {}
        self.entries = []
        self._cache = {}
        self.blocked = {}

    def add(self, fields, origin, host, from_tree, text):
        e = dict(fields)
        e['_origin'], e['_host'], e['_tree'], e['_text'] = origin, host, from_tree, text
        self.entries.append(e)
        self.by_name.setdefault(e['Package'], []).append(e)
        for alts in relations(e.get('Provides', '')):
            for name, _, op, ver in alts:
                self.provides.setdefault(name, []).append((e, ver if op == '=' else None))

    def arch_ok(self, e, from_arch, qual):
        a = e.get('Architecture')
        want = self.native if from_arch == 'all' else from_arch
        ma = e.get('Multi-Arch', 'no')
        if qual == 'any':
            return a in (want, 'all') or ma == 'allowed'
        if qual == 'native':
            return a in (self.native, 'all')
        if qual:
            return a == qual
        return a in (want, 'all') or ma == 'foreign'

    def satisfiers(self, rel, from_arch):
        key = (rel, from_arch)
        if key not in self._cache:
            self._cache[key] = self._satisfiers(rel, from_arch)
        return self._cache[key]

    def _satisfiers(self, rel, from_arch):
        name, qual, op, ver = rel
        out = [e for e in self.by_name.get(name, ()) if self.arch_ok(e, from_arch, qual) and satisfies(e['Version'], op, ver)]
        for e, pver in self.provides.get(name, ()):
            if not self.arch_ok(e, from_arch, qual):
                continue
            if op is None or (pver is not None and satisfies(pver, op, ver)):
                out.append(e)
        return out

    def missing(self, root):
        """Relations reachable from root that nothing satisfies; each with the path that reaches it."""
        found, seen = [], set()
        queue = [(root, [])]
        while queue:
            e, path = queue.pop(0)
            key = (e['Package'], e['Architecture'], e['Version'])
            if key in seen:
                continue
            seen.add(key)
            arch = e['Architecture']
            for field in ('Pre-Depends', 'Depends'):
                for alts in relations(e.get(field, '')):
                    options = []
                    for rel in alts:
                        options = self.satisfiers(rel, arch)
                        if options:
                            break
                    if not options:
                        found.append((path + [e['Package']], field, ' | '.join(show(r) for r in alts), alts))
                        continue
                    best = max(options, key=lambda x: (x['_tree'], _Key(x['Version'])))
                    queue.append((best, path + [e['Package']]))
        return found

    def successor(self, name):
        """A library whose name differs only in its soname or t64 suffix: the likely transition."""
        m = re.fullmatch(r'(.+?)(\d+(?:\.\d+)*)(t64)?((?:-[a-z]+)*)', name)
        if not m:
            return []
        stem, tail = m.group(1), m.group(4)
        out = set()
        for other in self.by_name:
            if other == name or not other.startswith(stem):
                continue
            mo = re.fullmatch(re.escape(stem) + r'(\d+(?:\.\d+)*)(t64)?' + re.escape(tail), other)
            if mo:
                src = self.by_name[other][0].get('Source', other).split()[0]
                vers = sorted({x['Version'] for x in self.by_name[other]}, key=_Key)
                out.add('%s %s (source %s)' % (other, vers[-1], src))
        return sorted(out)


def classify(index, alts):
    names = [a[0] for a in alts]
    present = [n for n in names if n in index.by_name or n in index.provides]
    if not present and any(n in index.blocked for n in names):
        return 'blocked by the policy', '; '.join(
            '%s: the edition blocks %s, and the tree has no build of it for this architecture' % (
                n, ', '.join(sorted(index.blocked[n])[:4])) for n in names if n in index.blocked)
    if not present:
        succ = [s for n in names for s in index.successor(n)]
        if succ:
            return 'library transition', 'gone from every archive; successor: ' + '; '.join(succ)
        return 'gone', 'no package or Provides of that name in any archive'
    have = []
    for n in present:
        vers = sorted({e['Version'] + ' ' + e['Architecture'] + ' (' + (e['_origin'] or '?') + ')'
                       for e in index.by_name.get(n, ())})
        prov = sorted({'%s provides %s' % (e['Package'], v or 'unversioned') for e, v in index.provides.get(n, ())})
        have.append('%s: %s' % (n, '; '.join(vers + prov) or 'blocked by the policy'))
    if any(a[2] == '=' for a in alts):
        return 'exact version gone', ' / '.join(have)
    return 'version or architecture unavailable', ' / '.join(have)


def dose_run(native, foreign, fg, bg, out, only):
    args = ['dose-debcheck', '--deb-native-arch=' + native, '-e', '-f', '--summary']
    if foreign:
        args.append('--deb-foreign-archs=' + ','.join(foreign))
    for f in fg:
        args += ['--fg', str(f)]
    for b in bg:
        args += ['--bg', str(b)]
    if only:
        args.append('--checkonly=' + ','.join(only))
    p = subprocess.run(args, capture_output=True, text=True, timeout=3600)
    out.write_text(p.stdout + ('\n# stderr\n' + p.stderr if p.stderr else ''))
    # dose-debcheck returns 1 when broken packages were found, 64 on a usage or input error.
    if p.returncode not in (0, 1):
        raise Stop('dose-debcheck failed (%d): %s' % (p.returncode, p.stderr[-2000:]))
    broken = {}
    current = None
    for line in p.stdout.splitlines():
        m = re.match(r'^ *-? *package: (\S+)$', line)
        if m and line.lstrip().startswith(('- package:', 'package:')) and not line.startswith('      '):
            current = {'package': m.group(1)}
            continue
        if current is None:
            continue
        m = re.match(r'^ *(version|architecture|status): (\S+)', line)
        if m and m.group(1) not in current:
            current[m.group(1)] = m.group(2)
            if m.group(1) == 'status' and current.get('status') == 'broken':
                name = current['package'].split(':')[0]
                broken.setdefault((name, current.get('architecture', ''), current.get('version', '')), [])
            continue
        m = re.match(r'^ *(unsat-dependency|unsat-conflict|depchain|conflict): ?(.*)$', line)
        if m and current.get('status') == 'broken':
            name = current['package'].split(':')[0]
            broken[(name, current.get('architecture', ''), current.get('version', ''))].append(line.strip())
    return broken, p.returncode


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('tree')
    ap.add_argument('--codename', default='mashtabba')
    ap.add_argument('--archive-config', default=os.environ.get('SPARKY_LC_ARCHIVE_CONFIG'))
    ap.add_argument('--scratch')
    ap.add_argument('--report')
    ap.add_argument('--profiles', default='base,nvidia,arm64')
    ap.add_argument('--engines')
    ap.add_argument('--jobs', type=int, default=4)
    ap.add_argument('--unsigned', action='store_true')
    ap.add_argument('--mode', choices=('report', 'refuse'), default='report')
    ap.add_argument('--known')
    ap.add_argument('--only')
    ap.add_argument('--min-free-gib', type=int, default=2)
    ap.add_argument('--root-min-free-gib', type=int, default=12)
    a = ap.parse_args()
    if not a.archive_config:
        raise Stop('set SPARKY_LC_ARCHIVE_CONFIG or pass --archive-config (sparky-os/lean/archive.md)')
    scratch = Path(a.scratch or (os.environ.get('SPARKY_LC_SCRATCH') and Path(os.environ['SPARKY_LC_SCRATCH']) / 'installable') or '')
    if not str(scratch) or str(scratch) == '.':
        raise Stop('set SPARKY_LC_SCRATCH or pass --scratch')
    scratch = scratch.resolve()
    scratch.mkdir(parents=True, exist_ok=True)
    if free(scratch) < (a.min_free_gib << 30) + (1 << 30) or free('/') < (a.root_min_free_gib << 30):
        raise Stop('not enough space: scratch %.1f GiB (floor %d + 1 for the indexes), / %.1f GiB (floor %d)' % (
            free(scratch) / 2**30, a.min_free_gib, free('/') / 2**30, a.root_min_free_gib))
    engines = (a.engines or ('apt,static,dose' if shutil.which('dose-debcheck') else 'apt,static')).split(',')
    if 'dose' in engines and not shutil.which('dose-debcheck'):
        raise Stop('dose-debcheck is not installed (package dose-distcheck)')
    report = Path(a.report).resolve() if a.report else scratch / ('report-' + time.strftime('%Y%m%dT%H%M%S'))
    if report.exists():
        shutil.rmtree(report)
    (report / 'apt').mkdir(parents=True)
    tree = Path(a.tree).resolve()
    sources = json.loads(Path(a.archive_config).read_text())
    if not isinstance(sources, list) or not sources:
        raise Stop('the archive configuration must be a nonempty JSON list (sparky-os/lean/archive.md)')
    for s in sources:
        if set(s) - {'uri', 'suite', 'components', 'keyring', 'check_valid_until'}:
            raise Stop('unknown archive source field in ' + a.archive_config)
        if not s['uri'].startswith(('https://', 'file:')):
            raise Stop('archive requires an explicit public HTTPS or file URI: ' + s['uri'])

    tree_fields, tree_indexes, tree_trust = tree_release(tree, a.codename, a.unsigned, scratch)
    tree_entries = []
    for index in tree_indexes:
        for fields, text in stanzas(index.read_text(errors='replace')):
            tree_entries.append(fields)
    prefs = policy_files(tree, tree_entries, scratch)
    tree_arches = sorted({e['Architecture'] for e in tree_entries})
    only = set(a.only.split(',')) if a.only else None

    profiles = [p for p in a.profiles.split(',') if p]
    for p in profiles:
        if p not in ('base', 'nvidia', 'arm64'):
            raise Stop('unknown profile ' + p)
    if 'arm64' in profiles and 'arm64' not in tree_arches:
        profiles.remove('arm64')
    global CUDA_BASE
    CUDA_BASE, cuda_sum, cuda_pin, cuda_pin_name = cuda_setup()

    meta = {'tree': str(tree), 'tree_release_date': tree_fields.get('Date', ''), 'tree_trust': tree_trust,
            'archive_config': a.archive_config, 'sources': sources, 'engines': engines, 'profiles': {},
            'apt': run(['apt-get', '--version']).stdout.splitlines()[0],
            'dose': run(['dose-debcheck', '--version']).stdout.strip() if 'dose' in engines else None,
            'started': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}
    rows, failures, checked, failed_in = [], {}, {}, {}
    sparky_apt = None
    for profile in profiles:
        arches = ['arm64'] if profile == 'arm64' else [x for x in ('amd64', 'i386') if x in tree_arches or x == 'amd64']
        base = scratch / ('state-' + profile)
        if base.exists():
            for sub in ('etc', 'keys', 'edition', 'policy', 'cache'):
                shutil.rmtree(base / sub, ignore_errors=True)
        base.mkdir(parents=True, exist_ok=True)
        cuda_key = None
        p_prefs = dict(prefs)
        if profile == 'nvidia':
            cuda_key = base / 'keys' / 'cuda-archive-keyring.gpg'
            (base / 'keys').mkdir(parents=True, exist_ok=True)
            deb = base / 'keys' / 'cuda-keyring.deb'
            run(['curl', '--fail', '--location', '--silent', '--show-error', '--max-time', '120', '-o', str(deb),
                 CUDA_BASE + '/cuda-keyring_1.1-1_all.deb'])
            if digest(deb) != cuda_sum:
                raise Stop('CUDA keyring checksum differs from sparky-stereo-hardware share/cuda-key.sh')
            data = subprocess.run(['dpkg-deb', '--fsys-tarfile', str(deb)], capture_output=True, check=True).stdout
            with tarfile.open(fileobj=io.BytesIO(data)) as tar:
                cuda_key.write_bytes(tar.extractfile('./usr/share/keyrings/cuda-archive-keyring.gpg').read())
            p_prefs[cuda_pin_name] = (cuda_pin, 'sparky-stereo-hardware lib/actions.sh setup_nvidia')
        # SparkyLinux's own policy comes from its sparky-apt package, fetched through the same signed state.
        u = Universe(profile, base, arches, sources, cuda_key, tree_fields, tree_indexes, a.codename, p_prefs)
        u.update()
        if sparky_apt is None:
            fetch = base / 'policy'
            u.apt(['apt-get', '-q', 'download', 'sparky-apt'], timeout=300)
            for f in base.glob('sparky-apt_*.deb'):
                f.rename(fetch / f.name)
            debs = sorted(fetch.glob('sparky-apt_*.deb'))
            if not debs:
                raise Stop('could not fetch SparkyLinux sparky-apt')
            sparky_apt = preferences_from_deb(debs[-1], 'sparky-apt ' + debs[-1].name.split('_')[1])
        if sparky_apt:
            for fname, value in sparky_apt.items():
                (base / 'etc/preferences.d' / fname).write_text(value[0])
                u.prefs[fname] = {'from': value[1], 'sha256': hashlib.sha256(value[0].encode()).hexdigest()}
            p_prefs.update(sparky_apt)
            u.apt(['apt-cache', 'gencaches'])
        lists = u.targets()
        pins = Pins(p_prefs)
        index = Index(u.native, arches[1:])
        bg_files = []
        tree_text = {}
        for path, origin, arch, label, base_uri in lists:
            from_tree = base_uri.rstrip('/') == 'file:' + str(base / 'edition')
            host = re.sub(r'^[a-z]+://([^/]*)/.*$', r'\1', base_uri) if '://' in base_uri else ''
            kept = []
            for fields, text in stanzas(read_list(path)):
                if 'Package' not in fields:
                    continue
                e = {'Package': fields['Package'], 'Version': fields['Version'], '_origin': origin, '_host': host}
                if not from_tree and pins.blocked(e):
                    index.blocked.setdefault(fields['Package'], set()).add(
                        '%s %s (%s)' % (fields['Version'], fields.get('Architecture', '?'), origin or '?'))
                    continue
                index.add(fields, origin, host, from_tree, text)
                kept.append(dose_stanza(fields))
            if from_tree:
                tree_text.setdefault(arch, []).extend(kept)
            else:
                f = report / ('bg-%s-%d.Packages' % (profile, len(bg_files)))
                f.write_text('\n\n'.join(kept) + '\n')
                bg_files.append(f)
        meta['profiles'][profile] = {'architectures': arches, 'policy': u.prefs,
                                     'sources.list': (base / 'etc/sources.list').read_text(),
                                     'lists': [{'file': p.name, 'origin': o, 'architecture': ar, 'sha256': digest(p)}
                                               for p, o, ar, _, _ in lists]}
        want = [e for e in index.entries if e['_tree'] and e['Architecture'] in arches + ['all']
                and (profile != 'arm64' or e['Architecture'] == 'arm64')]
        if profile == 'arm64':
            want = [e for e in want if e['Architecture'] == 'arm64']
        if only:
            want = [e for e in want if e['Package'] in only]
        for e in want:
            checked.setdefault((e['Package'], e['Version'], e['Architecture']), set()).add(profile)
        print('[%s] %d archives indexed, %d packages of the tree to check' % (profile, len(lists), len(want)), flush=True)

        results, derived = {}, {}
        keys = {(e['Package'], e['Architecture'], e['Version']) for e in want}

        def parent_of(e):
            # A dbgsym or lc-hr companion whose one dependency is its own package at its own version installs
            # exactly when that package does: apt is asked once, for the package.
            if not e['Package'].endswith(COMPANIONS) or e.get('Pre-Depends'):
                return None
            rels = relations(e.get('Depends', ''))
            if len(rels) != 1 or len(rels[0]) != 1:
                return None
            name, qual, op, ver = rels[0][0]
            if op != '=' or ver != e['Version'] or qual:
                return None
            arch = e['Architecture']
            for cand in index.by_name.get(name, ()):
                key = (cand['Package'], cand['Architecture'], cand['Version'])
                if (cand['_tree'] and cand['Version'] == ver and key in keys
                        and cand['Architecture'] in (arch, 'all', u.native if arch == 'all' else arch)):
                    return key
            return None
        for e in want:
            parent = parent_of(e)
            if parent:
                derived[(e['Package'], e['Architecture'], e['Version'])] = parent
        direct = [e for e in want if (e['Package'], e['Architecture'], e['Version']) not in derived]
        if 'apt' in engines:
            print('[%s] apt asked for %d packages; %d dbgsym and lc-hr companions follow their package' % (
                profile, len(direct), len(derived)), flush=True)
        if 'apt' in engines:
            with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.jobs)) as pool:
                futs = {pool.submit(u.simulate, e['Package'], e['Architecture'], e['Version']): e for e in direct}
                for fut in concurrent.futures.as_completed(futs):
                    e = futs[fut]
                    ok, text = fut.result()
                    results[(e['Package'], e['Architecture'], e['Version'])] = ok
                    if not ok:
                        name = '%s_%s_%s.log' % (profile, e['Package'], e['Architecture'])
                        (report / 'apt' / name).write_text(text)
            for key, parent in derived.items():
                results[key] = results[parent]
        dose = {}
        if 'dose' in engines:
            fg = []
            for arch, texts in sorted(tree_text.items()):
                f = report / ('fg-%s-%s.Packages' % (profile, arch))
                f.write_text('\n\n'.join(texts) + '\n')
                fg.append(f)
            # dose checks the whole foreground in seconds; --only filters its answer, as --checkonly misses
            # Architecture: all packages named without an architecture.
            dose, _ = dose_run(u.native, arches[1:], fg, bg_files, report / ('dose-%s.yaml' % profile), None)
        for f in bg_files + list(report.glob('fg-%s-*.Packages' % profile)):
            f.unlink()
        for e in sorted(want, key=lambda x: (x['Package'], x['Architecture'])):
            key = (e['Package'], e['Architecture'], e['Version'])
            apt_ok = results.get(key)
            dose_key = next((k for k in dose if k[0] == e['Package'] and k[2] == e['Version']
                             and k[1] in (e['Architecture'], '')), None)
            dose_ok = None if 'dose' not in engines else dose_key is None
            missing = index.missing(e) if 'static' in engines else []
            static_ok = None if 'static' not in engines else not missing
            failed = apt_ok is False or (apt_ok is None and (dose_ok is False or static_ok is False))
            if not failed and dose_ok is not False and static_ok is not False:
                continue
            causes = []
            for path, field, rel, alts in missing:
                cls, detail = classify(index, alts)
                causes.append('%s: %s %s [%s: %s]' % (' > '.join(path), field, rel, cls, detail))
            if not causes and apt_ok is False and key in derived:
                causes.append('apt: installs only with %s %s %s, which fails' % derived[key])
            elif not causes and apt_ok is False:
                text = (report / 'apt' / ('%s_%s_%s.log' % (profile, e['Package'], e['Architecture']))).read_text()
                lines = [ln.strip() for ln in text.splitlines()
                         if ' : ' in ln or ln.startswith(('E:', 'Error:')) or 'conflict' in ln.lower()]
                causes.append('apt: ' + ' / '.join(lines[:6]))
            companion = e['Package'].endswith(COMPANIONS)
            rows.append({'profile': profile, 'package': e['Package'], 'version': e['Version'],
                         'architecture': e['Architecture'], 'source': e.get('Source', e['Package']).split()[0],
                         'companion': companion,
                         'apt': {True: 'ok', False: 'FAIL', None: '-'}[apt_ok] + (' (as %s)' % derived[key][0] if key in derived else ''),
                         'static': {True: 'ok', False: 'FAIL', None: '-'}[static_ok],
                         'dose': {True: 'ok', False: 'FAIL', None: '-'}[dose_ok],
                         'dose_reasons': dose.get(dose_key, [])[:8] if dose_key else [],
                         'causes': causes})
            if failed:
                failures.setdefault((e['Package'], e['Version']), []).append(profile)
                failed_in.setdefault((e['Package'], e['Version'], e['Architecture']), set()).add(profile)

    known = {}
    if a.known:
        for line in Path(a.known).read_text().splitlines():
            if line.strip() and not line.startswith('#'):
                parts = line.split('\t')
                known[(parts[0], parts[1] if len(parts) > 1 else '*')] = parts[2] if len(parts) > 2 else ''
    unexplained = sorted(k for k in failures if k not in known and (k[0], '*') not in known)

    with open(report / 'installable.tsv', 'w') as out:
        out.write('profile\tpackage\tversion\tarchitecture\tsource\tcompanion\tapt\tstatic\tdose\tcauses\tdose_reasons\n')
        for r in rows:
            out.write('\t'.join([r['profile'], r['package'], r['version'], r['architecture'], r['source'],
                                 'yes' if r['companion'] else 'no', r['apt'], r['static'], r['dose'],
                                 ' || '.join(r['causes']), ' | '.join(r['dose_reasons'])]) + '\n')
    disagree = [r for r in rows if len({r['apt'].split()[0], r['static'], r['dose']} - {'-'}) > 1]
    lines = ['Installability of %s (%s), %s' % (tree, tree_fields.get('Date', 'unsigned'), meta['started']),
             'engines: %s; profiles: %s' % (','.join(engines), ','.join(profiles)),
             'packages that cannot be installed: %d (%d without their dbgsym and lc-hr companions)' % (
                 len(failures), len([k for k in failures if not k[0].endswith(COMPANIONS)])),
             'engines that disagree: %d' % len(disagree), '']
    def category(key):
        bad, all_ = failed_in.get(key, set()), checked.get(key, set())
        if bad == all_:
            return 'fails everywhere it applies'
        if bad == {'base'} and 'nvidia' in all_:
            return "installs only with NVIDIA's CUDA repository (the hardware setup adds it on NVIDIA machines)"
        if bad == {'nvidia'}:
            return "breaks with NVIDIA's CUDA repository and its pin"
        return 'fails in ' + ','.join(sorted(bad))
    counts = {}
    for key in failed_in:
        counts[category(key)] = counts.get(category(key), 0) + 1
    lines[3:3] = ['  %d: %s' % (n, c) for c, n in sorted(counts.items())]
    by_source = {}
    for r in rows:
        if (r['package'], r['version']) in failures:
            by_source.setdefault(r['source'], {}).setdefault((r['package'], r['version'], r['architecture']), []).append(r)
    for src in sorted(by_source):
        lines.append('source %s' % src)
        for (pkg, ver, arch), rs in sorted(by_source[src].items()):
            key = (pkg, ver, arch)
            lines.append('  %s %s %s: %s%s' % (pkg, ver, arch, category(key), ' (companion)' if pkg.endswith(COMPANIONS) else ''))
            if not pkg.endswith(COMPANIONS):
                for c in rs[0]['causes'][:4]:
                    lines.append('    ' + c)
    if disagree:
        lines += ['', 'engines that disagree (profile package version arch apt static dose):']
        lines += ['  %s %s %s %s %s %s %s' % (r['profile'], r['package'], r['version'], r['architecture'], r['apt'], r['static'], r['dose'])
                  for r in disagree]
    if a.mode == 'refuse':
        lines += ['', 'not in the known list (%s): %d' % (a.known or 'none', len(unexplained))]
        lines += ['  %s %s' % k for k in unexplained]
    (report / 'summary.txt').write_text('\n'.join(lines) + '\n')
    meta['finished'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    meta['failures'] = len(failures)
    (report / 'metadata.json').write_text(json.dumps(meta, indent=2, default=str) + '\n')
    print('\n'.join(lines))
    print('report: ' + str(report))
    if a.mode == 'refuse' and unexplained:
        return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Stop as e:
        print('check-installable: ' + str(e), file=sys.stderr)
        sys.exit(2)
