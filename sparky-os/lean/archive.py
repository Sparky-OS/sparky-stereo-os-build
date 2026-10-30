# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Signed archive inputs for the link gate, without installing packages.

APT solves the exact supplied .debs against an empty status database. Its early
APT_CONFIG bootstrap excludes workstation configuration, hooks and credentials.
Only the signed indexes, hash-verified archive bytes and explicit local inputs
can contribute files to the execution root. No maintainer scripts are run.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import time
import subprocess
import tarfile
import tempfile
from urllib.parse import unquote, urlsplit
from urllib.request import urlopen

from . import package


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def fields(text):
    result = {}
    key = None
    for line in text.splitlines():
        if line.startswith((' ', '\t')) and key:
            result[key] += '\n' + line
        elif ':' in line:
            key, value = line.split(':', 1)
            result[key] = value.strip()
    return result


def control(deb):
    run = subprocess.run(['dpkg-deb', '-f', str(deb)], capture_output=True, text=True)
    if run.returncode:
        raise package.Invalid(f'{deb}: invalid Debian archive: {run.stderr.strip()}')
    obj = fields(run.stdout)
    for key in ('Package', 'Version', 'Architecture'):
        if not obj.get(key):
            raise package.Invalid(f'{deb}: missing {key}')
    return obj


def identity(obj):
    return tuple(obj[k] for k in ('Package', 'Version', 'Architecture'))


def rooted(root, name, follow=True):
    """Resolve archive symlinks as the future root sees them, never on the host."""
    pending = list(PurePosixPath(name).parts)
    parts = []
    links = 0
    while pending:
        item = pending.pop(0)
        if item == '//':
            raise package.Invalid(f'ambiguous double-slash archive anchor: {name}')
        if item in ('/', '.', ''):
            continue
        if item == '..':
            if not parts:
                raise package.Invalid(f'archive path escapes root: {name}')
            parts.pop()
            continue
        path = root.joinpath(*parts, item)
        if not path.is_relative_to(root):
            raise package.Invalid(f'archive path escapes root: {name}')
        if path.is_symlink() and (pending or follow):
            links += 1
            if links > 40:
                raise package.Invalid(f'archive symlink cycle: {name}')
            target = os.readlink(path)
            if target.startswith('/'):
                parts = []
            pending = list(PurePosixPath(target).parts) + pending
        else:
            parts.append(item)
    return root.joinpath(*parts)


class UnmodeledDiversion(package.Invalid):
    """A preinst outside the bounded grammar cannot authorize a redirect."""


def static_diversions(deb, obj):
    """Read a bounded, complete preinst grammar, never execute shell code.

    Debian Policy's package diversion exempts the declaring package. Only an
    unconditional install/upgrade loop or direct commands with literal paths
    are understood here;
    arbitrary maintainer-script effects remain outside this data-only root.
    """
    proc = subprocess.Popen(['dpkg-deb', '--ctrl-tarfile', str(deb)], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    script = None
    try:
        with tarfile.open(fileobj=proc.stdout, mode='r|') as tar:
            for member in tar:
                name = PurePosixPath(member.name)
                if name.is_absolute() or '..' in name.parts:
                    raise package.Invalid(f'{deb}: unsafe control member {member.name}')
                if name != PurePosixPath('preinst'):
                    continue
                if (member.name not in ('preinst', './preinst') or script is not None or not member.isreg()
                        or not member.mode & 0o111 or member.size > 65536):
                    raise package.Invalid(f'{deb}: unsupported preinst control member')
                script = tar.extractfile(member).read().decode('utf-8')
        error = proc.stderr.read().decode(errors='replace')
        if proc.wait():
            raise package.Invalid(f'{deb}: cannot read control archive: {error}')
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.communicate()
    if script is None:
        return []
    # Only LF delimits shell lines. Full-line comments may contain UTF-8, but
    # executable tokens remain ASCII. Reject controls even within comments.
    # Never let removing a comment join an escaped newline to later code.
    physical = script.split('\n')
    invalid = any((ord(c) < 32 and c not in '\t\n') or ord(c) == 127 for c in script)
    lines = []
    continued = False
    for line in physical:
        stripped = line.strip(' \t')
        comment = line.lstrip(' \t').startswith('#')
        if continued and (not stripped or comment or not line.startswith((' ', '\t'))):
            invalid = True
        if comment:
            # Conservative: no escaped-line spelling even in a comment.
            invalid |= line.endswith('\\')
        elif stripped:
            invalid |= any(ord(c) > 126 for c in line)
            if continued:
                lines[-1] = lines[-1][:-1] + stripped
            else:
                lines.append(stripped)
        continued = not comment and line.endswith('\\')
        if continued and (not stripped.endswith(' \\') or not lines[-1].startswith('dpkg-divert ')):
            invalid = True
    invalid |= continued
    if invalid:
        if 'dpkg-divert' in script:
            raise UnmodeledDiversion(f'{deb}: unsupported non-ASCII or non-LF token/control or continuation in diversion preinst')
        return []
    text = '\n'.join(lines)
    if 'dpkg-divert' not in text:
        return []
    literal = r'/[A-Za-z0-9_./+-]+'
    loop = re.fullmatch(
        r'set -e\nif \[ "\$1" = "install" \] \|\| \[ "\$1" = "upgrade" \]; then\n'
        r'for (?P<var>[a-z][a-z0-9_]*) in (?P<paths>' + literal + r'(?: ' + literal + r')*); do\n'
        r'dpkg-divert (?:--quiet )?--package (?P<owner>[a-z0-9][a-z0-9+.-]*) --add --rename '
        r'--divert "\$(?P=var)(?P<suffix>\.[A-Za-z0-9_.+-]+)" "\$(?P=var)"\n'
        r'done\nfi\nexit 0', text)
    direct = re.fullmatch(
        r'set -e\nif \[ "\$1" = (?:install|"install") \] \|\| '
        r'\[ "\$1" = (?:upgrade|"upgrade") \]; then\n'
        r'(?P<commands>(?:dpkg-divert [^\n]+\n)+)fi\nexit 0', text)
    declarations = []
    if loop:
        declarations = [(loop['owner'], source, source + loop['suffix'])
                        for source in loop['paths'].split(' ')]
    elif direct:
        for command in direct['commands'].splitlines():
            match = re.fullmatch(
                r'dpkg-divert (?:--quiet )?--package (?P<owner>[a-z0-9][a-z0-9+.-]*) '
                r'--add --rename --divert (?P<target>' + literal + r') (?P<source>' + literal + r')'
                r'(?: >/dev/null)?', command)
            if not match:
                raise UnmodeledDiversion(f'{deb}: unsupported direct diversion command')
            declarations.append((match['owner'], match['source'], match['target']))
    if not declarations or not script.startswith('#!/bin/sh\n'):
        raise UnmodeledDiversion(f'{deb}: unsupported dynamic or unrecognized diversion preinst')
    result = []
    for owner, source, target in declarations:
        if owner != obj['Package']:
            raise package.Invalid(f'{deb}: diversion owner differs from package identity')
        if any(path.startswith('//') or str(PurePosixPath(path)) != path or '..' in PurePosixPath(path).parts
               for path in (source, target)):
            raise package.Invalid(f'{deb}: unsafe diversion path {source}')
        result.append({'source': source, 'target': target, 'owner': obj['Package'],
                       'archive_sha256': digest(deb),
                       'preinst_sha256': hashlib.sha256(script.encode()).hexdigest()})
    return result


def diversion_map(archives, root, unmodeled=None):
    """Bind static declarations to the selected archives before merging data."""
    result, targets = {}, set()
    for deb, obj in archives:
        try:
            declarations = static_diversions(deb, obj)
        except UnmodeledDiversion as exc:
            if unmodeled is None:
                raise
            # As before, arbitrary scripts are not part of a data-only root.
            # This grants no collision exception or filesystem operation.
            unmodeled.append({'identity': identity(obj), 'archive_sha256': digest(deb), 'reason': str(exc)})
            continue
        for row in declarations:
            source = rooted(root, row['source'], follow=False)
            target = rooted(root, row['target'], follow=False)
            if source in result or source in targets or target in result or target in targets:
                raise package.Invalid(f'{deb}: conflicting or chained diversion at {row["source"]}')
            row['resolved_target'] = str(target.relative_to(root))
            result[source] = row
            targets.add(target)
    return result


def unpack(deb, root, check_space=None, diversions=None, package_name=None):
    """Merge data only; reject conflicting paths, traversal and special files."""
    check_space = check_space or (lambda required: space(root, required))
    proc = subprocess.Popen(['dpkg-deb', '--fsys-tarfile', str(deb)], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    try:
        with tarfile.open(fileobj=proc.stdout, mode='r|') as tar:
            for member in tar:
                if '..' in PurePosixPath(member.name).parts or member.name.startswith('/'):
                    raise package.Invalid(f'{deb}: unsafe archive path: {member.name}')
                check_space((member.size if member.isreg() else 0) + 16384)
                path = rooted(root, member.name, follow=False)
                if diversions:
                    # A declared path must not acquire a different meaning as
                    # other packages introduce symlinks during extraction.
                    for original, row in diversions.items():
                        if (rooted(root, row['source'], follow=False) != original or
                                rooted(root, row['target'], follow=False) != root / row['resolved_target']):
                            raise package.Invalid(f'{deb}: diversion crosses an archive symlink')
                    targets = {rooted(root, row['target'], follow=False) for row in diversions.values()}
                    if path in targets:
                        raise package.Invalid(f'{deb}: diversion destination already supplied: {member.name}')
                    if path in diversions:
                        if not member.isreg():
                            raise package.Invalid(f'{deb}: diversion requires a regular file: {member.name}')
                        row = diversions[path]
                        if package_name != row['owner']:
                            path = rooted(root, row['target'], follow=False)
                path.parent.mkdir(parents=True, exist_ok=True)
                exists = path.exists() or path.is_symlink()
                if member.isdir():
                    if exists and not rooted(root, member.name).is_dir():
                        raise package.Invalid(f'{deb}: directory conflicts at {member.name}')
                    if not exists:
                        path.mkdir(mode=member.mode & 0o777)
                elif member.issym():
                    if diversions and any(path in source.parents or path in (root / row['resolved_target']).parents
                                          for source, row in diversions.items()):
                        raise package.Invalid(f'{deb}: diversion crosses an archive symlink')
                    # Validate even dangling targets; retain their in-root spelling.
                    rooted(root, str(PurePosixPath(member.name).parent / member.linkname)
                           if not member.linkname.startswith('/') else member.linkname)
                    if exists:
                        if not path.is_symlink() or os.readlink(path) != member.linkname:
                            raise package.Invalid(f'{deb}: symlink conflicts at {member.name}')
                    else:
                        path.symlink_to(member.linkname)
                elif member.isreg() or member.islnk():
                    source = tar.extractfile(member) if member.isreg() else None
                    target = rooted(root, member.linkname) if member.islnk() else None
                    if target and diversions and target in diversions and package_name != diversions[target]['owner']:
                        target = rooted(root, diversions[target]['target'], follow=False)
                    if exists:
                        if path.is_symlink() or not path.is_file():
                            raise package.Invalid(f'{deb}: file conflicts at {member.name}')
                        old_hash = digest(path)
                        new_hash = digest(target) if target else hashlib.file_digest(source, 'sha256').hexdigest()
                        if old_hash != new_hash or path.stat().st_mode & 0o777 != member.mode & 0o777:
                            raise package.Invalid(f'{deb}: different payloads at {member.name}')
                    else:
                        if target:
                            if not target.is_file():
                                raise package.Invalid(f'{deb}: missing hardlink target {member.linkname}')
                            with target.open('rb') as source, path.open('xb') as stream:
                                copy_stream(source, stream, check_space)
                        else:
                            with path.open('xb') as stream:
                                copy_stream(source, stream, check_space)
                        path.chmod(member.mode & 0o777)
                else:
                    raise package.Invalid(f'{deb}: unsupported special file {member.name}')
        error = proc.stderr.read().decode(errors='replace')
        if proc.wait():
            raise package.Invalid(f'{deb}: cannot unpack: {error}')
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.communicate()


def space(path, required=0, minimum=2 << 30, root_minimum=12 << 30):
    """Refuse writes before either the scratch or root filesystem floor is crossed."""
    path = Path(path)
    root_free = shutil.disk_usage('/').free
    if root_free < root_minimum:
        raise package.NoSpace(f'/: free space {root_free} is below root floor {root_minimum}')
    floor = max(minimum, root_minimum) if path.stat().st_dev == Path('/').stat().st_dev else minimum
    available = shutil.disk_usage(path).free
    if available - required < floor:
        raise package.NoSpace(f'{path}: insufficient space: {available} free, {required} requested, floor {floor}')
    # Bind mounts and overlay roots can report different device IDs while sharing
    # backing storage. Reserve the same write against the root floor as well.
    if root_free - required < root_minimum:
        raise package.NoSpace(f'/: insufficient space: {root_free} free, {required} requested, floor {root_minimum}')


def copy_stream(source, target, check_space):
    while True:
        block = source.read(1 << 20)
        if not block:
            break
        check_space(len(block) + 16384)
        target.write(block)


def inventory(root, output):
    """Retain hashes and symlink targets before releasing a reconstructable root."""
    with output.open('w') as stream:
        for base, dirs, names in os.walk(root, followlinks=False):
            for name in sorted(dirs + names):
                path = Path(base) / name
                relative = str(path.relative_to(root))
                if path.is_symlink():
                    stream.write(json.dumps({'path': relative, 'target': os.readlink(path)}) + '\n')
                elif path.is_file():
                    stream.write(json.dumps({'path': relative, 'size': path.stat().st_size,
                                             'sha256': digest(path)}) + '\n')


class ExecutionUnavailable(package.Invalid):
    """The execution environment failed, so baseline error comparison is invalid."""


class Archive:
    """One architecture and one frozen set of signed indexes per comparison.

    Configuration is a JSON list of {uri, suite, components, keyring} sources.
    HTTPS archives and explicit file: fixture archives are accepted. The optional
    check_valid_until=false is for immutable snapshots with expired Release dates;
    it never disables signature or hash verification.
    """

    def __init__(self, config, scratch, arch, min_free_gib=2, root_min_free_gib=12):
        self.arch = arch
        self.scratch = Path(scratch).resolve()
        if min_free_gib < 2 or root_min_free_gib < 12:
            raise package.Invalid('space floors cannot be below 2 GiB scratch and 12 GiB root')
        self.minimum, self.root_minimum = min_free_gib << 30, root_min_free_gib << 30
        ancestor = self.scratch
        while not ancestor.exists():
            ancestor = ancestor.parent
        space(ancestor, 1 << 20, self.minimum, self.root_minimum)
        self.scratch.mkdir(parents=True, exist_ok=True)
        self.ensure_space(1 << 20)
        self._inputs, self._indexes, self._active = {}, set(), set()
        self.universes = self.scratch / 'universes'
        self.universes.mkdir(exist_ok=True)
        self.base = Path(tempfile.mkdtemp(prefix=f'link-{arch}-', dir=self.scratch))
        self.cache = self.scratch / 'sha256'
        self.cache.mkdir(exist_ok=True)
        self.env = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LC_ALL': 'C', 'LANGUAGE': 'C',
                    'DEBIAN_FRONTEND': 'noninteractive', 'HOME': str(self.base),
                    'APT_CONFIG': str(self.base / 'apt.conf')}
        self.sources = json.loads(Path(config).read_text())
        if not isinstance(self.sources, list) or not self.sources:
            raise package.Invalid('archive configuration must be a nonempty JSON source list')
        for name in ('etc/parts', 'etc/sources.list.d', 'etc/preferences.d', 'etc/auth.conf.d',
                     'etc/trusted.gpg.d', 'state/lists/partial', 'cache/archives/partial', 'log', 'inputs'):
            (self.base / name).mkdir(parents=True)
        (self.base / 'state/status').touch()
        (self.base / 'etc/apt.conf').touch()
        (self.base / 'etc/preferences').touch()
        lines = []
        for index, source in enumerate(self.sources):
            if set(source) - {'uri', 'suite', 'components', 'keyring', 'check_valid_until'}:
                raise package.Invalid('unknown archive source configuration field')
            uri = source['uri'].rstrip('/')
            parsed = urlsplit(uri)
            if (parsed.scheme not in ('https', 'file') or parsed.username or parsed.password
                    or parsed.query or parsed.fragment or re.search(r'[\s"\\\[\]]', uri)
                    or (parsed.scheme == 'https' and not parsed.hostname)
                    or (parsed.scheme == 'file' and parsed.netloc)):
                raise package.Invalid(f'archive requires an explicit public HTTPS or file URI: {uri}')
            suite = source['suite']
            components = source['components']
            if not re.fullmatch(r'[a-zA-Z0-9._/-]+', suite) or not components:
                raise package.Invalid('invalid archive suite or components')
            if any(not re.fullmatch(r'[a-zA-Z0-9._/-]+', c) for c in components):
                raise package.Invalid('invalid archive component')
            key = self.base / f'etc/key-{index}.gpg'
            key_source = Path(source['keyring'])
            self.ensure_space(key_source.stat().st_size + 16384)
            with key_source.open('rb') as src, key.open('xb') as dest:
                copy_stream(src, dest, self.ensure_space)
            opts = f'arch={arch} signed-by={key}'
            if source.get('check_valid_until', True) is False:
                opts += ' check-valid-until=no'
            lines.append(f'deb [{opts}] {uri} {suite} {" ".join(components)}\n')
        self.public_sources = ''.join(lines)
        (self.base / 'etc/sources.list').write_text(self.public_sources)
        # APT_CONFIG is read BEFORE apt.conf.d, unlike -c and -o. All paths,
        # including auth, trust, extended status and binary caches, are private.
        options = {
            'Dir::Etc': str(self.base / 'etc'), 'Dir::Etc::main': 'apt.conf',
            'Dir::Etc::parts': 'parts', 'Dir::Etc::sourcelist': 'sources.list',
            'Dir::Etc::sourceparts': 'sources.list.d', 'Dir::Etc::preferences': 'preferences',
            'Dir::Etc::preferencesparts': 'preferences.d', 'Dir::Etc::netrc': 'auth.conf',
            'Dir::Etc::netrcparts': 'auth.conf.d', 'Dir::Etc::trusted': 'trusted.gpg',
            'Dir::Etc::trustedparts': 'trusted.gpg.d', 'Dir::State': str(self.base / 'state'),
            'Dir::State::status': str(self.base / 'state/status'),
            'Dir::State::extended_states': str(self.base / 'state/extended_states'),
            'Dir::Cache': str(self.base / 'cache'), 'Dir::Cache::pkgcache': '',
            'Dir::Cache::srcpkgcache': '', 'Dir::Log': str(self.base / 'log'),
            'APT::Architecture': arch, 'APT::Install-Recommends': 'false',
            'APT::Install-Suggests': 'false', 'APT::Get::List-Cleanup': 'false',
            'APT::Get::AllowUnauthenticated': 'false', 'Acquire::AllowInsecureRepositories': 'false',
            'Acquire::AllowDowngradeToInsecureRepositories': 'false',
            'Acquire::Languages': 'none', 'Acquire::ForceHash': 'sha256',
            'Acquire::Retries': '0', 'Acquire::https::Timeout': '60',
            'APT::Sandbox::User': str(os.getuid()),
        }
        for value in options.values():
            if re.search(r'["\\\n]', value):
                raise package.Invalid('scratch path contains unsupported APT configuration characters')
        (self.base / 'apt.conf').write_text(''.join(f'{k} "{v}";\n' for k, v in options.items()) +
                                           f'APT::Architectures {{ "{arch}"; }};\n')
        self.ensure_space(len(self.sources) << 30)
        self.run(['apt-config', 'dump'], 'configuration')
        self.run(['apt-get', '-y', '-o', 'APT::Update::Error-Mode=any', '-o', 'Debug::Acquire::gpgv=true', 'update'], 'update')
        self.metadata = [{'path': str(p.relative_to(self.base)), 'size': p.stat().st_size, 'sha256': digest(p)}
                         for p in sorted((self.base / 'state/lists').iterdir()) if p.is_file() and p.name != 'lock']
        if not any(p['path'].endswith('InRelease') or p['path'].endswith('Release.gpg') for p in self.metadata):
            raise package.Invalid('archive update produced no verified signed Release metadata')
        (self.base / 'metadata.json').write_text(json.dumps({'sources': self.sources, 'metadata': self.metadata,
            'keys': [{'path': str(p.relative_to(self.base)), 'sha256': digest(p)}
                     for p in sorted((self.base / 'etc').glob('key-*.gpg'))],
            'configuration_sha256': digest(self.base / 'apt.conf'),
            'trust': 'APT update succeeded with Signed-By; insecure and unauthenticated inputs disabled'}, indent=2) + '\n')

    def ensure_space(self, required=0):
        space(self.scratch, required, self.minimum, self.root_minimum)

    def run(self, args, label):
        # APT writes only private state. Monitor its growth as well as reserving
        # space before starting; terminate only this command's process group.
        self.ensure_space(256 << 20)
        proc = subprocess.Popen(args, cwd=self.base, env=self.env, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, start_new_session=True)
        deadline = time.monotonic() + 300
        try:
            while True:
                try:
                    out, err = proc.communicate(timeout=0.05)
                    break
                except subprocess.TimeoutExpired:
                    self.ensure_space(256 << 20)
                    if time.monotonic() > deadline:
                        raise package.Invalid(f'archive {label} timed out')
        except BaseException:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            out, err = proc.communicate()
            (self.base / f'{label}.log').write_text('$ ' + ' '.join(args) + '\n' + out + err)
            raise
        (self.base / f'{label}.log').write_text('$ ' + ' '.join(args) + '\n' + out + err)
        if proc.returncode:
            raise package.Invalid(f'archive {label} failed (see {self.base / (label + ".log")}):\n' + (out + err)[-5000:])
        return out

    def input(self, path):
        """Freeze a supplied identity/hash once, without copying unselected bytes."""
        path = Path(path).resolve()
        stat = path.stat()
        stamp = (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)
        if path in self._inputs:
            obj = self._inputs[path]
            if obj['stamp'] != stamp:
                raise package.Invalid(f'{path}: supplied input changed after its universe was frozen')
            return obj
        obj = {'path': path, 'control': control(path), 'sha256': digest(path), 'size': stat.st_size, 'stamp': stamp}
        current = path.stat()
        if stamp != (current.st_dev, current.st_ino, current.st_size, current.st_mtime_ns, current.st_ctime_ns):
            raise package.Invalid(f'{path}: supplied input changed during verification')
        if obj['control']['Architecture'] not in (self.arch, 'all'):
            raise package.Invalid(f'{path}: wrong architecture {obj["control"]["Architecture"]}; context is {self.arch}')
        self._inputs[path] = obj
        return obj

    def cached_input(self, item):
        """Copy only selected bytes, once, without hardlinking or modifying a source."""
        dest = self.cache / (item['sha256'] + '.deb')
        if dest.exists():
            if dest.stat().st_size != item['size'] or digest(dest) != item['sha256']:
                raise package.Invalid(f'{dest}: corrupt cached package; remove it and retry')
            return dest
        self.ensure_space(item['size'] + 16384)
        with tempfile.NamedTemporaryFile(dir=self.cache, prefix='.input-', delete=False) as stream:
            temporary = Path(stream.name)
            try:
                with item['path'].open('rb') as source:
                    copy_stream(source, stream, self.ensure_space)
                stream.flush()
                if digest(temporary) != item['sha256']:
                    raise package.Invalid(f'{item["path"]}: supplied bytes changed while copying')
                temporary.chmod(0o444)
                os.link(temporary, dest)
            finally:
                temporary.unlink(missing_ok=True)
        return dest

    def universe(self, deb, siblings):
        candidate = self.input(deb)
        items = {}
        named = {}
        for path in [deb] + list(siblings):
            item = self.input(path)
            obj = item['control']
            if obj['Package'] == candidate['control']['Package'] and identity(obj) != identity(candidate['control']):
                continue
            key = identity(obj)
            if key in items and items[key]['sha256'] != item['sha256']:
                raise package.Invalid(f'conflicting supplied package identity: {key}')
            name = obj['Package']
            if name in named and named[name] != key:
                raise package.Invalid(f'conflicting supplied package: {name}; provide one authoritative edition snapshot')
            items.setdefault(key, item)
            named[name] = key
        inputs = sorted(items.values(), key=lambda item: identity(item['control']))
        token = hashlib.sha256(json.dumps([item['sha256'] for item in inputs]).encode()).hexdigest()
        local = self.universes / token
        records = []
        for item in inputs:
            obj, sha = item['control'], item['sha256']
            records.append(''.join(f'{key}: {value}\n' for key, value in obj.items()) +
                           f'Filename: pool/{sha}.deb\nSize: {item["size"]}\nSHA256: {sha}\n')
        index = '\n'.join(records).encode()
        self.ensure_space(len(index) * 3 + (len(inputs) + 10) * 8192)
        if not local.exists():
            temporary = Path(tempfile.mkdtemp(prefix='.universe-', dir=self.universes))
            try:
                (temporary / 'pool').mkdir()
                for item in inputs:
                    # Only metadata and links are offered to APT. Selected bytes
                    # are subsequently copied and reverified in the immutable cache.
                    (temporary / 'pool' / (item['sha256'] + '.deb')).symlink_to(item['path'])
                (temporary / 'Packages').write_bytes(index)
                (temporary / 'Packages').chmod(0o444)
                manifest = [{'identity': identity(item['control']), 'sha256': item['sha256'],
                             'size': item['size'], 'source': str(item['path'])} for item in inputs]
                (temporary / 'universe.json').write_text(json.dumps(manifest, indent=2) + '\n')
                (temporary / 'universe.json').chmod(0o444)
                temporary.rename(local)
            finally:
                if temporary.exists():
                    shutil.rmtree(temporary)
        elif (local / 'Packages').read_bytes() != index:
            raise package.Invalid(f'{local}: corrupt immutable local index')
        local_source = f'deb [trusted=yes arch={self.arch}] {local.as_uri()} ./\n'
        (self.base / 'etc/local.list').write_text(local_source)
        (self.base / 'etc/sources.list').write_text(local_source + self.public_sources)
        if token not in self._indexes:
            self.run(['apt-get', '-y', '-o', 'Dir::Etc::sourcelist=local.list', '-o',
                      'APT::Update::Error-Mode=any', 'update'], 'local-' + token)
            self._indexes.add(token)
        preferences = []
        for item in inputs:
            obj = item['control']
            preferences.append(f'Package: {obj["Package"]}\nPin: version {obj["Version"]}\nPin-Priority: 1001\n\n')
        for name in sorted(named):
            preferences.append(f'Package: {name}\nPin: version *\nPin-Priority: -1\n\n')
        (self.base / 'etc/preferences').write_text(''.join(preferences))
        return candidate, inputs, local

    def qualify(self, deb, siblings=()):
        """At most two live roots; successful callers must close their qualifiers."""
        if len(self._active) >= 2:
            raise package.Invalid('two qualified roots are still active; close them before resolving another case')
        self.ensure_space(1 << 20)
        directory = Path(tempfile.mkdtemp(prefix='case-', dir=self.base))
        try:
            return self._qualify(deb, siblings, directory)
        except BaseException as exc:
            (directory / 'failure.txt').write_text(str(exc) + '\n')
            root = directory / 'root'
            if root.exists():
                inventory(root, directory / 'root-files.jsonl')
                shutil.rmtree(root)
            raise

    def _qualify(self, deb, siblings, directory):
        candidate, inputs, local = self.universe(deb, siblings)
        candidate_bytes = self.cached_input(candidate)
        args = ['apt-get', '-y', '--no-remove', '--no-install-recommends', '--download-only',
                '--print-uris', 'install', str(candidate_bytes)]
        label = directory.name + '-solve'
        plan = self.run(args, label)
        root = directory / 'root'
        root.mkdir()
        for mountpoint in ('proc', 'dev', 'tmp'):
            (root / mountpoint).mkdir()
        for name in ('bin', 'sbin', 'lib', 'lib64'):
            (root / 'usr' / name).mkdir(parents=True)
            (root / name).symlink_to('usr/' + name)
        packages = []
        selected_archives = []
        selected_inputs = []
        by_hash = {item['sha256']: item for item in inputs}
        named = {item['control']['Package'] for item in inputs}
        for line in plan.splitlines():
            if not line.startswith("'"):
                continue
            direct = re.match(r"'file:([^']+)' ", line)
            if direct and Path(unquote(direct[1])) == candidate_bytes:
                selected_inputs.append(candidate)
                continue
            match = re.fullmatch(r"'([^']+)' (\S+) (\d+) SHA256:([0-9a-f]{64})", line)
            if not match:
                raise package.Invalid(f'archive solver returned an unverified download: {line}')
            uri, filename, size, sha = match.groups()
            size = int(size)
            if sha in by_hash:
                item = by_hash[sha]
                if (urlsplit(uri).scheme != 'file' or Path(unquote(urlsplit(uri).path)) != local / 'pool' / (sha + '.deb')
                        or size != item['size']):
                    raise package.Invalid(f'archive attempted to substitute supplied {item["control"]["Package"]}')
                selected_inputs.append(item)
                continue
            if urlsplit(uri).scheme not in ('https', 'file'):
                raise package.Invalid(f'unsupported archive download URL: {uri}')
            archive = self.cache / (sha + '.deb')
            if archive.exists() and (archive.stat().st_size != size or digest(archive) != sha):
                raise package.Invalid(f'{archive}: corrupt cached package; remove it and retry')
            if not archive.exists():
                self.ensure_space(size + 16384)
                temporary = directory / 'download.part'
                with urlopen(uri, timeout=60) as response, temporary.open('xb') as stream:
                    remaining = size
                    while remaining:
                        block = response.read(min(1 << 20, remaining))
                        if not block:
                            break
                        self.ensure_space(len(block) + 16384)
                        stream.write(block)
                        remaining -= len(block)
                    if response.read(1):
                        raise package.Invalid(f'{uri}: exceeds signed package size {size}')
                if temporary.stat().st_size != size or digest(temporary) != sha:
                    raise package.Invalid(f'{uri}: corrupt download, signed size or SHA-256 differs')
                temporary.chmod(0o444)
                temporary.rename(archive)
            obj = control(archive)
            if obj['Architecture'] not in (self.arch, 'all'):
                raise package.Invalid(f'{uri}: wrong architecture {obj["Architecture"]}; context is {self.arch}')
            if obj['Package'] in named:
                raise package.Invalid(f'archive attempted to substitute supplied {obj["Package"]}')
            try:
                metadata = self.run(['apt-cache', 'show', f'{obj["Package"]}:{obj["Architecture"]}={obj["Version"]}'],
                                    directory.name + '-' + obj['Package'])
            except package.NoSpace:
                # a disk floor reached while asking APT is not a missing record
                raise
            except package.Invalid as exc:
                raise package.Invalid(f'{uri}: downloaded identity {identity(obj)} is absent from signed index') from exc
            records = [fields(record) for record in metadata.split('\n\n') if record.strip()]
            relationships = ('Depends', 'Pre-Depends', 'Provides', 'Conflicts', 'Breaks', 'Multi-Arch')
            if not any(identity(record) == identity(obj) and record.get('SHA256') == sha
                       and record.get('Size') == str(size)
                       and all(record.get(key, '') == obj.get(key, '') for key in relationships) for record in records):
                raise package.Invalid(f'{uri}: downloaded package identity differs from signed index')
            selected_archives.append((archive, obj))
            packages.append({'identity': identity(obj), 'url': uri, 'size': size, 'sha256': sha,
                             'depends': obj.get('Depends', ''), 'pre_depends': obj.get('Pre-Depends', ''),
                             'provides': obj.get('Provides', ''), 'multi_arch': obj.get('Multi-Arch', '')})
        if not any(identity(item['control']) == identity(candidate['control']) for item in selected_inputs):
            raise package.Invalid('archive solver omitted the requested candidate')
        selected_archives += [(self.cached_input(item), item['control']) for item in selected_inputs]
        unmodeled = []
        diversions = diversion_map(selected_archives, root, unmodeled)
        (directory / 'diversions.json').write_text(json.dumps(
            {'applied': list(diversions.values()), 'unmodeled_scripts': unmodeled}, indent=2) + '\n')
        for path, obj in selected_archives:
            unpack(path, root, self.ensure_space, diversions, obj['Package'])
        selected = {item['sha256'] for item in selected_inputs}
        evidence = {'architecture': self.arch, 'candidate': identity(candidate['control']),
                    'metadata': str(self.base / 'metadata.json'), 'solver': str(self.base / (label + '.log')), 'status': 'empty',
                    'universe': str(local / 'universe.json'), 'local_index_sha256': digest(local / 'Packages'),
                    'space_floors': {'scratch': self.minimum, 'root': self.root_minimum},
                    'diversions': list(diversions.values()),
                    'unmodeled_diversion_scripts': unmodeled,
                    'inputs': [{'identity': identity(item['control']), 'sha256': item['sha256'], 'size': item['size'],
                                'source': str(item['path']), 'selected': item['sha256'] in selected,
                                'depends': item['control'].get('Depends', ''), 'pre_depends': item['control'].get('Pre-Depends', '')}
                               for item in inputs], 'packages': packages}
        (directory / 'resolution.json').write_text(json.dumps(evidence, indent=2) + '\n')
        if (self.base / 'state/status').stat().st_size:
            raise package.Invalid('isolated solver status unexpectedly changed')
        q = Qualified(root, candidate['control'], directory, self.arch)
        q.owner = self
        self._active.add(directory)
        return q


class Qualified:
    def __init__(self, root, candidate, directory, arch):
        self.root, self.candidate, self.directory, self.arch = root, candidate, directory, arch

    def close(self):
        if self.root.exists():
            inventory(self.root, self.directory / 'root-files.jsonl')
            shutil.rmtree(self.root)
        if hasattr(self, 'owner'):
            self.owner._active.discard(self.directory)

    def run(self, command, env=None, timeout=20):
        native = subprocess.run(['dpkg', '--print-architecture'], capture_output=True, text=True, check=True).stdout.strip()
        if native != self.arch:
            raise ExecutionUnavailable(f'unsupported execution gate: {self.arch} context on {native}; native runner required')
        if not shutil.which('bwrap'):
            raise ExecutionUnavailable('archive execution requires bubblewrap and unprivileged user namespaces')
        args = ['bwrap', '--unshare-all', '--die-with-parent', '--new-session', '--cap-drop', 'ALL',
                '--ro-bind', str(self.root), '/', '--proc', '/proc', '--dev', '/dev', '--tmpfs', '/tmp',
                '--clearenv', '--setenv', 'PATH', '/usr/bin:/bin', '--setenv', 'LC_ALL', 'C',
                '--setenv', 'HOME', '/tmp', '--chdir', '/']
        for key, value in (env or {}).items():
            args += ['--setenv', key, value]
        args += ['--'] + list(command)
        run = subprocess.run(args, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
        with (self.directory / 'execution.jsonl').open('a') as stream:
            stream.write(json.dumps({'argv': args, 'returncode': run.returncode,
                                     'stdout': run.stdout, 'stderr': run.stderr}) + '\n')
        if 'bwrap:' in run.stderr:
            raise ExecutionUnavailable(f'isolated execution unavailable: {run.stderr.strip()}')
        return run
