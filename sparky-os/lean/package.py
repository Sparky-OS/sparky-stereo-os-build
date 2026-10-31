# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""lc1: checked build-time payloads, separate from reversible local projections.

The control field binds a manifest to one package/version/architecture. APT authenticates
the package in the usual way; this marker is processing evidence, not another signature.
Clients read only that manifest on installation. Release verification checks every entry.
HR lives in a separate, exact-version documentation package, never in the runtime image.
"""

from __future__ import annotations

import hashlib
import functools
import json
import lzma
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat

from . import project

FIELD = 'Sparky-Lean-Code'
FORMAT = 'lc1'
SCOPE = 'qualified-installed-payload'
BASE = '/usr/share/dpkg-stereo/lc'
HR_BASE = '/usr/share/dpkg-stereo/hr'
MAX_TEXT = 4 << 20
MAX_MANIFEST = 64 << 20


class Invalid(ValueError):
    pass


class NoSpace(Invalid):
    """A write refused at a disk floor: the machine's state, not a property of the input."""


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_hash(path, algorithm='sha256'):
    h = hashlib.new(algorithm)
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def encode(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True) + '\n').encode()


def stanzas(text):
    """Deb822 fields, including continuations; reject ambiguous duplicate fields."""
    row, key = {}, None
    for line in text.splitlines() + ['']:
        if not line.strip():
            if row:
                yield row
            row, key = {}, None
        elif line[0].isspace():
            if key is None:
                raise Invalid('control continuation without a field')
            row[key] += '\n' + line
        else:
            key, sep, value = line.partition(':')
            key = key.lower()
            if not sep or key in row:
                raise Invalid('invalid or repeated control field')
            row[key] = value.strip()


def control(root):
    rows = list(stanzas((Path(root) / 'DEBIAN/control').read_text()))
    if len(rows) != 1:
        raise Invalid('expected one binary control stanza')
    return rows[0]


def set_fields(path, fields):
    lines, drop = [], False
    names = {k.lower() for k in fields}
    for line in path.read_text().splitlines():
        if line and not line[0].isspace():
            drop = line.split(':', 1)[0].lower() in names
        if not drop and line:
            lines.append(line)
    lines.extend(f'{k}: {v}' for k, v in fields.items())
    path.write_text('\n'.join(lines) + '\n')


def identity(fields):
    p, v, a = (fields.get(k, '') for k in ('package', 'version', 'architecture'))
    if not re.fullmatch(r'[a-z0-9][a-z0-9+.-]+', p) or not re.fullmatch(r'[a-z0-9][a-z0-9-]*', a):
        raise Invalid('invalid package or architecture')
    if not v or re.search(r'[\s/\x00]', v):
        raise Invalid('invalid package version')
    return p, v, a


def manifest_path(package, arch):
    identity({'package': package, 'version': '1', 'architecture': arch})
    return f'{BASE}/{package}/{arch}.json'


def hr_path(package, arch, sha):
    return f'{HR_BASE}/{package}/{arch}/{sha}.xz'


def safe_path(path):
    if not isinstance(path, str) or not path.startswith('/') or any(c in path for c in '\x00\n\r\t'):
        raise Invalid('invalid manifest path')
    if str(PurePosixPath(path)) != path or '..' in PurePosixPath(path).parts or path.startswith('//'):
        raise Invalid('noncanonical manifest path')
    return path


def metadata_target(root, path):
    """Generated metadata must not traverse a package's directory symlink."""
    target = Path(root)
    for part in PurePosixPath(safe_path(path)).parts[1:]:
        target /= part
        if target.is_symlink():
            raise Invalid('lc metadata path traverses a symlink')
    return target


@functools.lru_cache(maxsize=1)
def renderer():
    # the same digest the identity carries (project.RENDERER_FILES and every lang_*.py)
    return {'identity': project.IDENTITY, 'sha256': project.CODE_SHA256}


def entries(root):
    """Never follow directory symlinks; record links, modes and all regular payload files."""
    root = Path(root)
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs.sort()
        files.sort()
        if Path(directory) == root:
            dirs[:] = [n for n in dirs if n != 'DEBIAN']
        for name in sorted(dirs + files):
            real = Path(directory) / name
            st = real.lstat()
            if stat.S_ISDIR(st.st_mode):
                continue
            path = safe_path('/' + real.relative_to(root).as_posix())
            row = {'path': path, 'mode': stat.S_IMODE(st.st_mode)}
            if stat.S_ISLNK(st.st_mode):
                row.update(kind='symlink', target=os.readlink(real))
            elif stat.S_ISREG(st.st_mode):
                row.update(kind='file', sha256=file_hash(real), bytes=st.st_size)
            else:
                raise Invalid(f'{path}: special file needs a qualified packaging adapter')
            yield real, row


def load(marker, raw, package, version, arch):
    match = re.fullmatch(r'lc1 ([0-9a-f]{64})', marker)
    if not match or len(raw) > MAX_MANIFEST or digest(raw) != match[1]:
        raise Invalid('missing, unknown or mismatched lc marker/manifest')
    try:
        obj = json.loads(raw)
        if (obj['format'], obj['scope'], obj['package'], obj['version'], obj['architecture']) != (
                FORMAT, SCOPE, package, version, arch):
            raise Invalid('lc identity or scope mismatch')
        if (not isinstance(obj['files'], list) or not isinstance(obj['renderer']['identity'], str)
                or not obj['renderer']['identity'].startswith('lean ')
                or not re.fullmatch(r'[0-9a-f]{64}', obj['renderer']['sha256'])):
            raise Invalid('invalid lc renderer identity')
        # lc1 is the compatibility contract; a newer client must still recognize
        # a payload checked by an older renderer. Exact reconstruction is checked
        # separately by --resolve and refuses a different resulting MR.
        if obj['hr_package'] not in (None, package + '-lc-hr'):
            raise Invalid('invalid HR companion identity')
        paths = set()
        for row in obj['files']:
            path = safe_path(row['path'])
            if path in paths or path == manifest_path(package, arch):
                raise Invalid('duplicate or recursive manifest entry')
            paths.add(path)
            if row['kind'] not in ('file', 'symlink') or row['status'] not in ('projected', 'unchanged', 'left'):
                raise Invalid('invalid manifest entry')
            if not isinstance(row['mode'], int) or not 0 <= row['mode'] <= 0o7777 or not row['reason']:
                raise Invalid('invalid payload mode or missing coverage reason')
            if row['kind'] == 'file' and not re.fullmatch(r'[0-9a-f]{64}', row['sha256']):
                raise Invalid('invalid payload hash')
            if row['kind'] == 'symlink' and not isinstance(row['target'], str):
                raise Invalid('invalid symlink target')
            if row['status'] == 'projected':
                if row['kind'] != 'file' or not re.fullmatch(r'[0-9a-f]{64}', row['sha_hr']):
                    raise Invalid('invalid HR hash')
                if not row['check'] or not row['handler']:
                    raise Invalid('projection lacks consumer check')
                if obj['hr_package'] is None or not 0 <= row['bytes'] < row['bytes_hr'] <= MAX_TEXT:
                    raise Invalid('invalid projection sizes or missing HR companion')
    except (KeyError, TypeError, json.JSONDecodeError) as exc:
        raise Invalid('malformed lc manifest') from exc
    return obj


def installed(P, names=None):
    """Only read markers in dpkg's installed control records; never trust a loose JSON file."""
    out = {}
    for row in stanzas(Path(P.real('/var/lib/dpkg/status')).read_text()):
        if row.get('status') != 'install ok installed' or FIELD.lower() not in row:
            continue
        p, v, a = identity(row)
        info = f'{p}:{a}' if row.get('multi-arch') == 'same' or Path(P.real(f'/var/lib/dpkg/info/{p}:{a}.list')).exists() else p
        if names is not None and info not in names and p not in names:
            continue
        try:
            target = P.real(manifest_path(p, a))
            if os.path.islink(target):
                raise Invalid('lc manifest is a symlink')
            with open(target, 'rb') as stream:
                raw = stream.read(MAX_MANIFEST + 1)
            out[info] = load(row[FIELD.lower()], raw, p, v, a)
        except (OSError, ValueError) as exc:
            out[info] = str(exc)
    return out


def prepare(root, hr_root=None, *, documentation=False):
    """Final staging step, before md5sums/dpkg-deb. Never run against an installed root.

    Failure leaves an unmarked disposable staging tree. Rebuild the staging tree to retry.
    documentation=True is reserved for our generated HR companion (it contains only docs).
    """
    root = Path(root).resolve()
    fields = control(root)
    p, v, a = identity(fields)
    mp = metadata_target(root, manifest_path(p, a))
    if root == Path('/') or (root / 'var/lib/dpkg/status').exists():
        raise Invalid('prepare requires a disposable package staging tree')
    if FIELD.lower() in fields or mp.exists():
        raise Invalid('already marked; use a fresh staging tree, never project MR again')
    if not documentation and hr_root is None:
        raise Invalid('an HR companion staging directory is required')
    hr = Path(hr_root).resolve() if hr_root is not None else None
    if hr and (hr == root or root in hr.parents or hr in root.parents or hr.exists()):
        raise Invalid('HR staging directory must be new and separate')
    rows, originals = [], []
    for real, row in entries(root):
        path = row['path']
        row.update(status='left', reason='symlink: retained')
        if row['kind'] == 'file':
            if documentation:
                if not (path.startswith(HR_BASE + '/') or path.startswith('/usr/share/doc/')):
                    raise Invalid('HR companion may contain only documentation')
                row['reason'] = 'authored documentation: retained'
            elif real.stat().st_nlink > 1:
                row['reason'] = 'hardlinked payload: retained'
            elif row['bytes'] == 0 or row['bytes'] > MAX_TEXT:
                row['reason'] = 'empty' if row['bytes'] == 0 else 'larger than 4 MiB'
            else:
                data = real.read_bytes()
                if b'\0' in data[:8192]:
                    row['reason'] = 'binary'
                else:
                    r = project.project(path, data, p)
                    row.update(status=r.status, reason=r.reason, handler=r.handler, variant=r.variant)
                    # Failed qualification is a build failure, not permission to stamp a broken pass.
                    if r.reason.startswith(('check failed:', 'not stable under', 'adapter error:')):
                        raise Invalid(f'{path}: {r.reason}')
                    if r.status == 'projected':
                        st = real.stat()
                        originals.append((r.sha_in, data))
                        real.write_bytes(r.lean)
                        os.utime(real, ns=(st.st_atime_ns, st.st_mtime_ns))
                        row.update(sha256=r.sha_out, bytes=r.bytes_out, sha_hr=r.sha_in,
                                   bytes_hr=r.bytes_in, check=r.check)
        rows.append(row)
    if originals:
        (hr / 'DEBIAN').mkdir(parents=True)
        for sha, data in originals:
            dest = hr / hr_path(p, a, sha).lstrip('/')
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(lzma.compress(data, preset=9))
        source = fields.get('source', f'{p} ({v})')
        multi = '\nMulti-Arch: same' if a != 'all' else ''
        (hr / 'DEBIAN/control').write_text(
            f'Package: {p}-lc-hr\nVersion: {v}\nArchitecture: {a}\nSource: {source}{multi}\n'
            f'Maintainer: {fields["maintainer"]}\nSection: doc\nPriority: optional\n'
            f'Description: Authored text for the lc1 build of {p}\n'
            ' Exact original text for Lean Code documentation and source-location resolution.\n')
        for key in ('homepage', 'bugs'):
            if key in fields:
                set_fields(hr / 'DEBIAN/control', {key.title(): fields[key]})
        copyright_file = root / f'usr/share/doc/{p}/copyright'
        if copyright_file.is_file():
            dest = hr / f'usr/share/doc/{p}-lc-hr/copyright'
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(copyright_file, dest)
        prepare(hr, documentation=True)
    obj = {'format': FORMAT, 'scope': SCOPE, 'package': p, 'version': v, 'architecture': a,
           'renderer': renderer(), 'files': rows, 'hr_package': f'{p}-lc-hr' if originals else None}
    raw = encode(obj)
    mp.parent.mkdir(parents=True, exist_ok=True)
    mp.write_bytes(raw)
    set_fields(root / 'DEBIAN/control', {FIELD: f'{FORMAT} {digest(raw)}'})
    if p != 'dpkg-stereo':
        existing = fields.get('breaks', '')
        set_fields(root / 'DEBIAN/control', {'Breaks': (existing + ', ' if existing else '') + 'dpkg-stereo (<< 0.1.6)'})
    # Canonical checksums are calculated from MR, including configuration. dpkg itself
    # establishes conffile baselines from the unpacked MR at installation.
    sums = []
    size = 0
    for real, row in entries(root):
        if row['kind'] == 'file':
            sums.append(f'{file_hash(real, "md5")}  {row["path"][1:]}\n')
            size += (row['bytes'] + 1023) // 1024
    (root / 'DEBIAN/md5sums').write_text(''.join(sorted(sums)))
    set_fields(root / 'DEBIAN/control', {'Installed-Size': str(size)})
    return obj


def check_tree(root):
    root = Path(root)
    fields = control(root)
    p, v, a = identity(fields)
    mp = manifest_path(p, a)
    target = metadata_target(root, mp)
    if target.is_symlink():
        raise Invalid('lc manifest is a symlink')
    raw = target.read_bytes()
    obj = load(fields.get(FIELD.lower(), ''), raw, p, v, a)
    expected = {r['path']: r for r in obj['files']}
    actual = {r['path']: r for _, r in entries(root) if r['path'] != mp}
    if set(actual) != set(expected):
        raise Invalid('payload paths changed after lc processing')
    for path, row in actual.items():
        if any(expected[path].get(k) != val for k, val in row.items()):
            raise Invalid(f'{path}: payload changed after lc processing')
    sums = {}
    for line in (root / 'DEBIAN/md5sums').read_text().splitlines():
        sha, sep, path = line.partition('  ')
        if not sep or not re.fullmatch(r'[0-9a-f]{32}', sha) or '/' + path in sums:
            raise Invalid('invalid package md5sums')
        sums[safe_path('/' + path)] = sha
    regular = {path for path, row in actual.items() if row['kind'] == 'file'} | {mp}
    if set(sums) != regular:
        raise Invalid('package md5sums do not cover the final MR payload')
    for path, sha in sums.items():
        if file_hash(root / path[1:], 'md5') != sha:
            raise Invalid(f'{path}: md5sums were not finalized after LC')
    return obj
