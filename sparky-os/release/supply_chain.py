"""Shared reader for the SPDX bill of materials and the SLSA provenance tools (ORDER 394).

It reads what the edition already records and invents nothing:
  - a published repository tree (dists/<suite>/main Packages and Sources, and the pool),
  - or that tree with a round's cohort laid over it (cohort.list, one .deb or .dsc path per line),
  - each .deb's control file, its debian/copyright and its Lean Code record
    (/usr/share/dpkg-stereo/lc/<package>/<arch>.json),
  - each source package's .dsc,
  - the .buildinfo files that exist beside builds.
Only the Python standard library and license_expression (SPDX licence list) are used.
"""
import base64
import functools
import gzip
import hashlib
import io
import json
import lzma
import os
import re
import tarfile
import zlib
from pathlib import Path

TOOL_VERSION = '0.1.0'
LC_JSON = re.compile(r'^\./?usr/share/dpkg-stereo/lc/([^/]+)/([^/]+)\.json$')

# DEP-5 short names (Debian copyright-format 1.0, "License specification") to SPDX identifiers.
# A name that is not here becomes a LicenseRef with the text the copyright file gives; nothing is guessed.
DEP5_TO_SPDX = {
    'apache-2.0': 'Apache-2.0', 'apache-2': 'Apache-2.0', 'artistic-2.0': 'Artistic-2.0', 'artistic-1.0': 'Artistic-1.0',
    'agpl-3': 'AGPL-3.0-only', 'agpl-3+': 'AGPL-3.0-or-later',
    'bsd-2-clause': 'BSD-2-Clause', 'bsd-3-clause': 'BSD-3-Clause', 'bsd-4-clause': 'BSD-4-Clause',
    'bsl-1.0': 'BSL-1.0', 'cc0-1.0': 'CC0-1.0', 'cc-by-3.0': 'CC-BY-3.0', 'cc-by-4.0': 'CC-BY-4.0',
    'cc-by-sa-3.0': 'CC-BY-SA-3.0', 'cc-by-sa-4.0': 'CC-BY-SA-4.0', 'expat': 'MIT', 'mit': 'MIT', 'isc': 'ISC',
    'gfdl-1.2': 'GFDL-1.2-only', 'gfdl-1.2+': 'GFDL-1.2-or-later', 'gfdl-1.3': 'GFDL-1.3-only', 'gfdl-1.3+': 'GFDL-1.3-or-later',
    'gpl-1': 'GPL-1.0-only', 'gpl-1+': 'GPL-1.0-or-later', 'gpl-2': 'GPL-2.0-only', 'gpl-2+': 'GPL-2.0-or-later',
    'gpl-3': 'GPL-3.0-only', 'gpl-3+': 'GPL-3.0-or-later',
    'lgpl-2': 'LGPL-2.0-only', 'lgpl-2+': 'LGPL-2.0-or-later', 'lgpl-2.1': 'LGPL-2.1-only', 'lgpl-2.1+': 'LGPL-2.1-or-later',
    'lgpl-3': 'LGPL-3.0-only', 'lgpl-3+': 'LGPL-3.0-or-later',
    'mpl-1.1': 'MPL-1.1', 'mpl-2.0': 'MPL-2.0', 'ofl-1.1': 'OFL-1.1', 'unlicense': 'Unlicense', 'zlib': 'Zlib',
    'python-2.0': 'Python-2.0', 'psf-2': 'Python-2.0', 'x11': 'X11', 'curl': 'curl', 'libpng': 'Libpng',
}
# "License: X with NAME exception" (DEP-5): the exception names that have an SPDX identifier.
DEP5_EXCEPTIONS = {
    'qt gpl exception': None, 'classpath': 'Classpath-exception-2.0', 'gcc runtime library': 'GCC-exception-3.1',
    'font': 'Font-exception-2.0', 'autoconf': 'Autoconf-exception-3.0', 'bison': 'Bison-exception-2.2',
}


class ReadError(Exception):
    pass

# The build record lean/buildrecord.py writes beside the .deb files (ORDER 394b). This reader is separate from the
# writer on purpose: the tools run outside the build container and check what the writer promised.
RECORD_SUFFIX = '.sparky-build.json'
RECORD_FORMAT = 'sparky-build-record/1'
RECORD_HOST_FACTS = ('recipeCommit', 'builderImage', 'invocationId', 'startedOn')
_RECORD_SHAPES = {
    'recipeCommit': re.compile(r'^[0-9a-f]{40}$'),
    'builderImage': re.compile(r'^sha256:[0-9a-f]{64}$'),
    'invocationId': re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),
    'startedOn': re.compile(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'),
    'finishedOn': re.compile(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'),
}


def read_build_record(path):
    """Parse and validate a build record. A fact is either present and well formed or named under "unrecorded";
    a record that is neither is damaged and is refused (ReadError), never read as if the fact were absent."""
    try:
        obj = json.loads(Path(path).read_text(encoding='utf-8'))
    except (OSError, ValueError) as exc:
        raise ReadError(f'{path}: {exc}')
    if not isinstance(obj, dict) or obj.get('format') != RECORD_FORMAT:
        raise ReadError(f'{path}: not a {RECORD_FORMAT} record')
    for key in ('source', 'version', 'buildArchitecture', 'finishedOn', 'debs', 'files', 'unrecorded'):
        if key not in obj:
            raise ReadError(f'{path}: the record lacks "{key}"')
    unrecorded = obj['unrecorded']
    if not isinstance(unrecorded, list) or not all(isinstance(u, str) for u in unrecorded):
        raise ReadError(f'{path}: "unrecorded" is not a list of names')
    for key in RECORD_HOST_FACTS:
        if key in obj and key in unrecorded:
            raise ReadError(f'{path}: "{key}" is both recorded and unrecorded')
        if key not in obj and key not in unrecorded:
            raise ReadError(f'{path}: "{key}" is neither recorded nor listed as unrecorded (damaged record)')
    for key, shape in _RECORD_SHAPES.items():
        if key in obj and not (isinstance(obj[key], str) and shape.match(obj[key])):
            raise ReadError(f'{path}: "{key}" is not well formed: {obj[key]!r}')
    if 'recipeCommit' in obj and not isinstance(obj.get('recipeDirty'), bool):
        raise ReadError(f'{path}: "recipeDirty" is missing beside "recipeCommit"')
    if not obj['debs'] or not all(isinstance(r, dict) and re.match(r'^[0-9a-f]{64}$', str(r.get('sha256', ''))) for r in obj['debs']):
        raise ReadError(f'{path}: "debs" lacks the sha256 of the packages')
    return obj


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def parse_deb822(text):
    """deb822 paragraphs as dicts; multi-line values keep their lines joined by newline ('.' lines are empty)."""
    out, cur, key = [], {}, None
    for line in text.split('\n'):
        if not line.strip():
            if cur:
                out.append(cur)
            cur, key = {}, None
            continue
        if line[0] in ' \t':
            if key is None:
                raise ReadError('continuation line without a field: %r' % line[:60])
            s = line[1:]
            cur[key] += '\n' + ('' if s.strip() == '.' else s)
        else:
            if ':' not in line:
                raise ReadError('not a deb822 line: %r' % line[:60])
            key, val = line.split(':', 1)
            cur[key] = val.strip()
    if cur:
        out.append(cur)
    return out


def strip_pgp(text):
    if text.startswith('-----BEGIN PGP SIGNED MESSAGE-----'):
        body = text.split('\n\n', 1)[1]
        body = body.split('\n-----BEGIN PGP SIGNATURE-----', 1)[0]
        return re.sub(r'(?m)^- ', '', body)
    return text


class _Slice(io.RawIOBase):
    """A read-only window onto part of a file (an ar member)."""

    def __init__(self, f, off, size):
        self.f, self.off, self.size, self.pos = f, off, size, 0

    def readable(self):
        return True

    def readinto(self, b):
        n = min(len(b), self.size - self.pos)
        if n <= 0:
            return 0
        self.f.seek(self.off + self.pos)
        data = self.f.read(n)
        b[:len(data)] = data
        self.pos += len(data)
        return len(data)


def _ar_members(f):
    if f.read(8) != b'!<arch>\n':
        raise ReadError('not an ar archive')
    while True:
        hdr = f.read(60)
        if not hdr:
            return
        if len(hdr) < 60 or hdr[58:60] != b'`\n':
            raise ReadError('bad ar header')
        name = hdr[:16].decode().strip().rstrip('/')
        size = int(hdr[48:58])
        start = f.tell()
        yield name, start, size
        f.seek(start + size + (size & 1))


def _open_tar(f, off, size, name):
    raw = io.BufferedReader(_Slice(f, off, size))
    if name.endswith('.xz'):
        stream = lzma.LZMAFile(raw)
    elif name.endswith('.gz'):
        stream = gzip.GzipFile(fileobj=raw)
    elif name.endswith('.zst'):
        from compression import zstd
        stream = zstd.ZstdFile(raw)
    elif name.endswith('.tar'):
        stream = raw
    else:
        raise ReadError('unknown member compression: ' + name)
    return tarfile.open(fileobj=stream, mode='r|')


def read_deb(path):
    """Facts from one .deb: control fields, copyright file (text or symlink target), Lean Code record."""
    facts = {'control': None, 'copyright': None, 'copyright_link': None, 'lc': None}
    with open(path, 'rb') as f:
        for name, off, size in _ar_members(f):
            if name.startswith('control.tar'):
                with _open_tar(f, off, size, name) as t:
                    for m in t:
                        if m.name.lstrip('./') == 'control':
                            facts['control'] = parse_deb822(t.extractfile(m).read().decode('utf-8'))[0]
            elif name.startswith('data.tar'):
                pkg = facts['control']['Package'] if facts['control'] else None
                if pkg is None:
                    raise ReadError('data member before control member')
                cr = './usr/share/doc/%s/copyright' % pkg
                dd = './usr/share/doc/%s' % pkg
                with _open_tar(f, off, size, name) as t:
                    for m in t:
                        n = m.name if m.name.startswith('./') else './' + m.name
                        if n == dd and m.issym():   # dbgsym packages: the whole doc directory points at the package they debug
                            facts['copyright_link'] = m.linkname.rstrip('/') + '/copyright'
                        elif n == cr:
                            if m.issym():
                                facts['copyright_link'] = m.linkname
                            elif m.isfile():
                                facts['copyright'] = t.extractfile(m).read().decode('utf-8', 'replace')
                        elif m.isfile() and LC_JSON.match(n):
                            blob = t.extractfile(m).read()
                            facts['lc'] = {'sha256': hashlib.sha256(blob).hexdigest(), 'doc': json.loads(blob)}
    if facts['control'] is None:
        raise ReadError('no control file in ' + str(path))
    return facts


def summarise_lc(lc):
    """The Lean Code record reduced to what the documents carry (counts, renderer, digest of the inputs)."""
    if not lc:
        return None
    d = lc['doc']
    counts = {}
    inputs = []
    for e in d.get('files', []):
        counts[e.get('status', '?')] = counts.get(e.get('status', '?'), 0) + 1
        if e.get('status') == 'projected':
            inputs.append('%s\t%s\t%s' % (e['path'], e.get('sha_hr', ''), e['sha256']))
    r = d.get('renderer') or {}
    return {
        'format': d.get('format'), 'scope': d.get('scope'), 'renderer': r.get('identity'),
        'renderer_sha256': r.get('sha256'), 'hr_package': d.get('hr_package'), 'files': counts,
        'record_sha256': lc['sha256'],
        'projected_inputs_sha256': hashlib.sha256('\n'.join(sorted(inputs)).encode()).hexdigest() if inputs else None,
    }


@functools.lru_cache(maxsize=1)
def _licensing():
    from license_expression import get_spdx_licensing
    return get_spdx_licensing()   # building it takes seconds: once per run


def _spdx_id_ok(expr):
    _licensing().parse(expr, validate=True)


def _licref(name):
    return 'LicenseRef-' + re.sub(r'[^A-Za-z0-9.-]+', '-', name).strip('-')


def _split_top(expr, word):
    """Split on ' word ' outside nothing (DEP-5 has no parentheses); a comma before the word is kept as a marker."""
    return re.split(r'\s+%s\s+' % word, expr, flags=re.I)


def dep5_expression(synopsis, texts, refs):
    """Debian copyright-format 1.0, 'License specification': 'and' binds tighter than 'or' unless preceded by a comma.
    Returns an SPDX expression; unknown short names become LicenseRef-* recorded in refs."""
    def one(name):
        name = name.strip().rstrip(',').strip()
        m = re.match(r'^(.*?)\s+with\s+(.*?)\s+exception$', name, re.I)
        base, exc = (m.group(1), m.group(2)) if m else (name, None)
        spdx = DEP5_TO_SPDX.get(base.lower())
        if spdx is None and base.startswith('LicenseRef-'):   # already an SPDX reference (KDE's copyright files write them)
            ref = _licref(base[len('LicenseRef-'):])
            refs.setdefault(ref, {'name': base, 'text': texts.get(base) or
                                  'The copyright file names this licence "%s" and gives no text for it.' % base})
            return ref if exc is None else ref
        if spdx is None:   # an identifier of the SPDX licence list written as it is (case-insensitive)
            try:
                sym = _licensing().parse(base, validate=True)
                text = str(sym)
                if sym is not None and ((' ' not in text and not sym.is_exception) or re.fullmatch(r'\S+ WITH \S+', text)):
                    spdx = text   # a bare exception identifier is not a licence: it stays a LicenseRef
            except Exception:
                spdx = None
        if spdx:
            try:
                _spdx_id_ok(spdx)
            except Exception:
                spdx = None
        if spdx and exc is None:
            return spdx
        if spdx and DEP5_EXCEPTIONS.get(exc.lower()):
            return '%s WITH %s' % (spdx, DEP5_EXCEPTIONS[exc.lower()])
        ref = _licref(name)
        refs.setdefault(ref, {'name': name, 'text': texts.get(name) or texts.get(base) or
                              'The copyright file names this licence "%s" and gives no text for it.' % name})
        return ref

    def group(e):
        ors = []
        for part in _split_top(e, 'or'):
            ands = [one(a) for a in _split_top(part, 'and')]
            ors.append(ands[0] if len(ands) == 1 else '(' + ' AND '.join(ands) + ')')
        return ors[0] if len(ors) == 1 else '(' + ' OR '.join(ors) + ')'

    syn = ' '.join(synopsis.split())
    m = re.search(r',\s+(and|or)\s+', syn, re.I)
    if m:   # the comma lowers the priority of the conjunction after it
        left, op, right = syn[:m.start()], m.group(1), syn[m.end():]
        parts = [group(left), group(right)]
        return '(' + (' AND ' if op.lower() == 'and' else ' OR ').join(parts) + ')'
    return group(syn)


def licences_from_copyright(text):
    """(format, declared SPDX expression or None, refs) from a debian/copyright file."""
    refs = {}
    if text is None:
        return 'missing', None, refs
    try:
        paras = parse_deb822(re.sub(r'(?m)^#.*\n', '', text))
    except ReadError:
        return 'free-form', None, refs
    if not paras or 'Format' not in paras[0] or 'copyright-format' not in paras[0]['Format']:
        return 'free-form', None, refs
    texts, syns = {}, []
    for p in paras:
        lic = p.get('License')
        if not lic:
            continue
        first, _, rest = lic.partition('\n')
        if 'Files' not in p and rest.strip():
            texts[first.strip()] = rest.strip()
        elif first.strip():
            syns.append(first.strip())
    # a stand-alone License stanza only carries text; the Files stanzas say which licences apply
    exprs = []
    for s in syns:
        e = dep5_expression(s, texts, refs)
        if e not in exprs:
            exprs.append(e)
    if not exprs:
        return 'dep5-no-licence', None, refs
    return 'dep5', ' AND '.join(sorted(exprs)) if len(exprs) > 1 else exprs[0], refs


def classify_origin(ctl, siblings_origin=None):
    """Origin of a package from the metadata it carries; the basis is returned with it."""
    ver, om = ctl['Version'], ctl.get('Original-Maintainer', '')
    omn = re.sub(r'\s*<[^>]*>', '', om).strip()
    ours = bool(re.search(r'\+(stereo3d|lc1|sparky|dmo)|\+stereo', ver)) or 'lc1' in ctl.get('Sparky-Lean-Code', '')
    if 'dmo' in ver or 'deb-multimedia' in om:
        return 'deb-multimedia', 'version or Original-Maintainer names deb-multimedia', omn
    if om:
        if re.search(r'pijanowski|sparkylinux|sparky', om, re.I):
            return 'sparkylinux', 'Original-Maintainer is SparkyLinux', omn
        return 'debian', 'Original-Maintainer is a Debian maintainer: the edition modifies a Debian package', omn
    if siblings_origin:
        return siblings_origin[0], siblings_origin[1] + ' (same source as a package that names its origin)', siblings_origin[2]
    return 'edition', 'no Original-Maintainer: built from the edition\'s own source or from upstream\'s; metadata cannot tell which', ''


def _origin_pass(pkgs):
    by_src = {}
    for p in pkgs:
        if p['control'].get('Original-Maintainer'):
            by_src.setdefault((p['source'], p['source_version']), classify_origin(p['control']))
    for p in pkgs:
        p['origin'], p['origin_basis'], p['original_maintainer'] = classify_origin(p['control'], by_src.get((p['source'], p['source_version'])))


def _source_of(ctl):
    s = ctl.get('Source', ctl['Package'])
    m = re.match(r'^(\S+)\s*\((.+)\)$', s)
    return (m.group(1), m.group(2)) if m else (s, ctl['Version'])


class Inventory:
    def __init__(self):
        self.packages = []       # one dict per binary package file
        self.sources = {}        # (name, version) -> dict
        self.notes = []          # facts the documents report (replacements, missing sources, mismatches)

    @staticmethod
    def raw_facts(path, cache=None):
        """The facts one .deb holds, read once and kept in the cache (the reading is the slow part)."""
        path = Path(path)
        st = path.stat()
        key = '%s|%d|%d' % (path, st.st_size, st.st_mtime_ns)
        hit = cache.get(key) if cache is not None else None
        if hit is not None and hit.get('v') != 2:
            hit = None   # recorded by an older reader
        if hit is None:
            sha = sha256_file(path)
            facts = read_deb(path)
            hit = {'v': 2, 'sha256': sha, 'size': st.st_size, 'control': facts['control'], 'copyright_link': facts['copyright_link'],
                   'copyright_z': base64.b64encode(zlib.compress(facts['copyright'].encode())).decode() if facts['copyright'] is not None else None,
                   'lc': summarise_lc(facts['lc'])}
            if cache is not None:
                cache[key] = hit
        return hit

    def add_deb(self, path, cache=None, rel_filename=None, index_sha=None):
        path = Path(path)
        hit = self.raw_facts(path, cache)
        text = zlib.decompress(base64.b64decode(hit['copyright_z'])).decode() if hit['copyright_z'] is not None else None
        hit = dict(hit)
        hit['licence_format'], hit['licence'], hit['licence_refs'] = licences_from_copyright(text)
        if index_sha is not None and index_sha != hit['sha256']:
            raise ReadError('%s: the repository index says sha256 %s, the file is %s' % (path, index_sha, hit['sha256']))
        ctl = hit['control']
        sname, sver = _source_of(ctl)
        p = dict(hit)
        p.pop('copyright_z', None)
        p.update({'path': str(path), 'filename': path.name, 'pool_filename': rel_filename, 'source': sname, 'source_version': sver})
        self.packages.append(p)
        return p

    def finish(self):
        _origin_pass(self.packages)
        by_dir = {}
        for p in self.packages:
            by_dir.setdefault((p['source'], p['source_version']), []).append(p)
        for p in self.packages:   # a symlinked copyright file resolves to a sibling of the same source and version
            if p['licence_format'] == 'missing' and p['copyright_link']:
                tgt = p['copyright_link'].replace('..', '').strip('/').split('/')
                want = tgt[-2] if len(tgt) >= 2 else None
                for q in by_dir[(p['source'], p['source_version'])]:
                    if q['control']['Package'] == want and q['licence_format'] not in ('missing',):
                        p['licence_format'], p['licence'], p['licence_refs'] = 'via symlink to ' + want, q['licence'], q['licence_refs']
                        break
        self.packages.sort(key=lambda p: (p['control']['Package'], p['control']['Architecture'], p['control']['Version']))


def read_dsc(path):
    path = Path(path)
    text = path.read_text(encoding='utf-8', errors='replace')
    d = parse_deb822(strip_pgp(text))[0]
    files = []
    for line in d.get('Checksums-Sha256', '').split('\n'):
        if line.strip():
            h, size, name = line.split()
            files.append({'name': name, 'size': int(size), 'sha256': h})
    return {'name': d['Source'], 'version': d['Version'], 'format': d.get('Format'), 'files': files, 'dsc_path': str(path),
            'dsc_sha256': sha256_file(path), 'homepage': d.get('Homepage'), 'vcs': {k: v for k, v in d.items() if k.startswith('Vcs-')},
            'binary': d.get('Binary'), 'maintainer': d.get('Maintainer'), 'original_maintainer': d.get('Original-Maintainer')}


def read_packages_index(tree, suite='mashtabba'):
    """(Filename, SHA256, path) of every binary package the tree's Packages files list, in a stable order."""
    base = Path(tree) / 'dists' / suite / 'main'
    out = {}
    for arch_dir in sorted(base.glob('binary-*')):
        for name, op in (('Packages.xz', lzma.open), ('Packages.gz', gzip.open), ('Packages', open)):
            f = arch_dir / name
            if f.exists():
                with op(f, 'rt', encoding='utf-8') as fh:
                    for p in parse_deb822(fh.read()):
                        out[p['Filename']] = p['SHA256']
                break
    return out


def find_dsc(name, version, dirs):
    v = version.split(':', 1)[-1]
    want = '%s_%s.dsc' % (name, v)
    for d in dirs:
        c = Path(d) / want
        if c.is_file():
            return c
    return None


def build_inventory(tree, cohort_list=None, suite='mashtabba', cache=None, workers=4):
    """The tree's packages, with the cohort's laid over them (a cohort package replaces the tree's for the same
    package and architecture)."""
    inv = Inventory()
    tree = Path(tree)
    index = read_packages_index(tree, suite)
    if not index:
        raise ReadError('no Packages index under %s/dists/%s/main' % (tree, suite))
    entries = [Path(l.strip()) for l in Path(cohort_list).read_text().splitlines() if l.strip()] if cohort_list else []
    if cache is not None and workers > 1:
        from concurrent.futures import ThreadPoolExecutor
        todo = [tree / fn for fn in index] + [e for e in entries if e.suffix == '.deb']
        with ThreadPoolExecutor(workers) as ex:
            list(ex.map(lambda f: Inventory.raw_facts(f, cache), todo))
        cache.save()
    for fn, sha in index.items():
        inv.add_deb(tree / fn, cache, rel_filename=fn, index_sha=sha)
    source_dirs = {str(tree / Path(fn).parent) for fn in index}
    if cohort_list:
        for e in entries:
            if e.suffix == '.deb':
                new = inv.add_deb(e, cache)
                key = (new['control']['Package'], new['control']['Architecture'])
                old = [p for p in inv.packages[:-1] if (p['control']['Package'], p['control']['Architecture']) == key]
                for o in old:
                    inv.packages.remove(o)
                    inv.notes.append('cohort %s %s replaces published %s' % (new['control']['Package'], new['control']['Version'], o['control']['Version']))
                new['pool_filename'] = None
            elif e.suffix == '.dsc':
                source_dirs.add(str(e.parent))
        for e in entries:
            for sub in ('', 'source', 'sources', '../source'):
                source_dirs.add(str((e.parent / sub).resolve()))
    inv.finish()
    for p in inv.packages:
        k = (p['source'], p['source_version'])
        if k not in inv.sources:
            dsc = find_dsc(k[0], k[1], sorted(source_dirs))
            inv.sources[k] = read_dsc(dsc) if dsc else None
            if dsc is None:
                inv.notes.append('no .dsc found for source %s %s' % k)
    return inv


class Cache:
    """Facts per file, kept in one JSON file so a rerun does not decompress the pool again."""

    def __init__(self, path):
        self.path, self.d = Path(path), {}
        if self.path.exists():
            self.d = json.loads(self.path.read_text())

    def get(self, k):
        return self.d.get(k)

    def __setitem__(self, k, v):
        self.d[k] = v

    def save(self):
        tmp = self.path.with_suffix('.tmp')
        tmp.write_text(json.dumps(self.d, sort_keys=True))
        os.replace(tmp, self.path)


def verify_served(publish_dir, round_name, fetch, keyring):
    """The round's served supply-chain files are the signed local ones (ORDER 394b). `fetch(relative)` returns the bytes the
    server gives for a path below the web root; `keyring` is a gpgv keyring with the repository key. Checks: every name in
    SHA256SUMS, its .asc and every file it lists served as sbom/ROUND/NAME with the local bytes, sbom/latest/SHA256SUMS the same,
    the signature valid, every file equal to the hash SHA256SUMS gives. Raises ReadError on the first difference."""
    import subprocess
    publish = Path(publish_dir).resolve()
    if not re.fullmatch(r'[A-Za-z0-9._-]+', round_name):
        raise ReadError('bad round name %r' % round_name)
    rows = []
    for line in (publish / 'SHA256SUMS').read_text().splitlines():
        if line.strip():
            digest, _, name = line.partition('  ')
            if not re.fullmatch(r'[0-9a-f]{64}', digest) or not name or '/' in name or name.startswith('.'):
                raise ReadError('SHA256SUMS: bad line %r' % line)
            rows.append((digest, name))
    if not rows:
        raise ReadError('SHA256SUMS lists no file')
    for digest, name in rows:
        if sha256_file(publish / name) != digest:
            raise ReadError('%s differs from SHA256SUMS' % name)
    sig = subprocess.run(['gpgv', '--keyring', str(keyring), str(publish / 'SHA256SUMS.asc'), str(publish / 'SHA256SUMS')],
                         capture_output=True, text=True)
    if sig.returncode != 0:
        raise ReadError('SHA256SUMS.asc does not verify: ' + sig.stderr.strip())
    for name in ['SHA256SUMS', 'SHA256SUMS.asc'] + [n for _, n in rows]:
        for where in ('sbom/%s/%s' % (round_name, name), 'sbom/latest/%s' % name):
            if fetch(where) != (publish / name).read_bytes():
                raise ReadError('the served %s is not the signed file %s' % (where, name))
    return {'round': round_name, 'files': [n for _, n in rows], 'sha256sums': sha256_file(publish / 'SHA256SUMS')}
