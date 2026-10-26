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
        if item in ('/', '.', ''):
            continue
        if item == '..':
            if not parts:
                raise package.Invalid(f'archive path escapes root: {name}')
            parts.pop()
            continue
        path = root.joinpath(*parts, item)
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


def unpack(deb, root):
    """Merge data only; reject conflicting paths, traversal and special files."""
    proc = subprocess.Popen(['dpkg-deb', '--fsys-tarfile', str(deb)], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    try:
        with tarfile.open(fileobj=proc.stdout, mode='r|') as tar:
            for member in tar:
                if '..' in PurePosixPath(member.name).parts or member.name.startswith('/'):
                    raise package.Invalid(f'{deb}: unsafe archive path: {member.name}')
                path = rooted(root, member.name, follow=False)
                path.parent.mkdir(parents=True, exist_ok=True)
                exists = path.exists() or path.is_symlink()
                if member.isdir():
                    if exists and not rooted(root, member.name).is_dir():
                        raise package.Invalid(f'{deb}: directory conflicts at {member.name}')
                    if not exists:
                        path.mkdir(mode=member.mode & 0o777)
                elif member.issym():
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
                            shutil.copyfile(target, path)
                        else:
                            with path.open('xb') as stream:
                                shutil.copyfileobj(source, stream)
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


def space(path, required=0):
    if shutil.disk_usage(path).free < (2 << 30) + required:
        raise package.Invalid(f'{path}: archive gate needs 2 GiB free plus {required} input bytes')


class ExecutionUnavailable(package.Invalid):
    """The execution environment failed, so baseline error comparison is invalid."""


class Archive:
    """One architecture and one frozen set of signed indexes per comparison.

    Configuration is a JSON list of {uri, suite, components, keyring} sources.
    HTTPS archives and explicit file: fixture archives are accepted. The optional
    check_valid_until=false is for immutable snapshots with expired Release dates;
    it never disables signature or hash verification.
    """

    def __init__(self, config, scratch, arch):
        self.arch = arch
        self.scratch = Path(scratch).resolve()
        self.scratch.mkdir(parents=True, exist_ok=True)
        space(self.scratch)
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
            shutil.copyfile(source['keyring'], key)
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

    def run(self, args, label):
        run = subprocess.run(args, cwd=self.base, env=self.env, capture_output=True, text=True, timeout=300)
        (self.base / f'{label}.log').write_text('$ ' + ' '.join(args) + '\n' + run.stdout + run.stderr)
        if run.returncode:
            raise package.Invalid(f'archive {label} failed (see {self.base / (label + ".log")}):\n'
                                  + (run.stdout + run.stderr)[-5000:])
        return run.stdout

    def qualify(self, deb, siblings=()):
        """Resolve exact local inputs, verify every byte, and extract one isolated root."""
        directory = Path(tempfile.mkdtemp(prefix='case-', dir=self.base))
        inputs = []
        named = {}
        origins = {}
        candidate = control(deb)
        for path in [deb] + list(siblings):
            obj = control(path)
            if obj['Package'] == candidate['Package'] and Path(path) != Path(deb):
                continue
            if obj['Architecture'] not in (self.arch, 'all'):
                raise package.Invalid(f'{path}: wrong architecture {obj["Architecture"]}; context is {self.arch}')
            name = obj['Package']
            if name in named:
                if named[name] != (identity(obj), digest(path)):
                    raise package.Invalid(f'conflicting supplied package: {name}')
                continue
            named[name] = (identity(obj), digest(path))
            target = directory / f'{len(inputs)}.deb'
            shutil.copyfile(path, target)
            sha = digest(target)
            if sha != named[name][1]:
                raise package.Invalid(f'{path}: supplied bytes changed while copying')
            origins[sha] = str(Path(path).resolve())
            inputs.append((target, obj, sha))
        # A private index makes supplied siblings available to APT without forcing
        # unrelated packages (and their conflicts/dependencies) into this root.
        # Only this generated index is trusted locally; public sources still need
        # their signatures. Public lists remain frozen during this local update.
        local = self.base / 'local'
        if local.exists():
            shutil.rmtree(local)
        (local / 'pool').mkdir(parents=True)
        records = []
        for index, (path, obj, sha) in enumerate(inputs):
            shutil.copyfile(path, local / 'pool' / f'{index}.deb')
            records.append(''.join(f'{key}: {value}\n' for key, value in obj.items()) +
                           f'Filename: pool/{index}.deb\nSize: {path.stat().st_size}\nSHA256: {sha}\n')
        (local / 'Packages').write_text('\n'.join(records))
        local_source = f'deb [trusted=yes arch={self.arch}] {local.as_uri()} ./\n'
        (self.base / 'etc/local.list').write_text(local_source)
        (self.base / 'etc/sources.list').write_text(local_source + self.public_sources)
        self.run(['apt-get', '-y', '-o', 'Dir::Etc::sourcelist=local.list', '-o',
                  'APT::Update::Error-Mode=any', 'update'], directory.name + '-local-index')
        (directory / 'supplied.Packages').write_bytes((local / 'Packages').read_bytes())
        # Pins forbid replacing supplied edition versions with stock versions.

        preferences = []
        for _, obj, _ in inputs:
            preferences += [f'Package: {obj["Package"]}\nPin: version {obj["Version"]}\nPin-Priority: 1001\n\n',
                            f'Package: {obj["Package"]}\nPin: version *\nPin-Priority: -1\n\n']
        (self.base / 'etc/preferences').write_text(''.join(preferences))
        args = ['apt-get', '-y', '--no-remove', '--no-install-recommends', '--download-only',
                '--print-uris', 'install', str(inputs[0][0])]
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
        selected_inputs = []
        supplied_hashes = {sha for _, _, sha in inputs}
        for line in plan.splitlines():
            if not line.startswith("'"):
                continue
            local = re.match(r"'file:([^']+)' ", line)
            if local:
                supplied = next((item for item in inputs if Path(unquote(local[1])) == item[0]), None)
                if supplied:
                    selected_inputs.append(supplied)
                    continue
            match = re.fullmatch(r"'([^']+)' (\S+) (\d+) SHA256:([0-9a-f]{64})", line)
            if not match:
                raise package.Invalid(f'archive solver returned an unverified download: {line}')
            uri, filename, size, sha = match.groups()
            size = int(size)
            if sha in supplied_hashes:
                supplied = next(item for item in inputs if item[2] == sha)
                if urlsplit(uri).scheme != 'file' or not Path(unquote(urlsplit(uri).path)).is_relative_to(self.base / 'local'):
                    raise package.Invalid(f'archive attempted to substitute supplied {supplied[1]["Package"]}')
                selected_inputs.append(supplied)
                continue
            if urlsplit(uri).scheme not in ('https', 'file'):
                raise package.Invalid(f'unsupported archive download URL: {uri}')
            archive = self.cache / (sha + '.deb')
            space(self.scratch, size)
            if archive.exists() and (archive.stat().st_size != size or digest(archive) != sha):
                raise package.Invalid(f'{archive}: corrupt cached package; remove it and retry')
            if not archive.exists():
                temporary = directory / 'download.part'
                with urlopen(uri, timeout=60) as response, temporary.open('xb') as stream:
                    remaining = size
                    while remaining:
                        block = response.read(min(1 << 20, remaining))
                        if not block:
                            break
                        stream.write(block)
                        remaining -= len(block)
                    if response.read(1):
                        raise package.Invalid(f'{uri}: exceeds signed package size {size}')
                if temporary.stat().st_size != size or digest(temporary) != sha:
                    raise package.Invalid(f'{uri}: corrupt download, signed size or SHA-256 differs')
                temporary.rename(archive)
            obj = control(archive)
            if obj['Architecture'] not in (self.arch, 'all'):
                raise package.Invalid(f'{uri}: wrong architecture {obj["Architecture"]}; context is {self.arch}')
            if obj['Package'] in named:
                raise package.Invalid(f'archive attempted to substitute supplied {obj["Package"]}')
            try:
                metadata = self.run(['apt-cache', 'show', f'{obj["Package"]}:{obj["Architecture"]}={obj["Version"]}'],
                                    directory.name + '-' + obj['Package'])
            except package.Invalid as exc:
                raise package.Invalid(f'{uri}: downloaded identity {identity(obj)} is absent from signed index') from exc
            records = [fields(record) for record in metadata.split('\n\n') if record.strip()]
            relationships = ('Depends', 'Pre-Depends', 'Provides', 'Conflicts', 'Breaks', 'Multi-Arch')
            if not any(identity(record) == identity(obj) and record.get('SHA256') == sha
                       and record.get('Size') == str(size)
                       and all(record.get(key, '') == obj.get(key, '') for key in relationships) for record in records):
                raise package.Invalid(f'{uri}: downloaded package identity differs from signed index')
            unpack(archive, root)
            packages.append({'identity': identity(obj), 'url': uri, 'size': size, 'sha256': sha,
                             'depends': obj.get('Depends', ''), 'pre_depends': obj.get('Pre-Depends', ''),
                             'provides': obj.get('Provides', ''), 'multi_arch': obj.get('Multi-Arch', '')})
        if not any(identity(item[1]) == identity(candidate) for item in selected_inputs):
            raise package.Invalid('archive solver omitted the requested candidate')
        for path, obj, sha in selected_inputs:
            unpack(path, root)
        evidence = {'architecture': self.arch, 'candidate': identity(candidate), 'metadata': str(self.base / 'metadata.json'),
                    'solver': str(self.base / (label + '.log')), 'status': 'empty',
                    'local_index_sha256': digest(directory / 'supplied.Packages'),
                    'inputs': [{'identity': identity(obj), 'sha256': sha, 'size': path.stat().st_size,
                                'source': origins[sha], 'selected': any(selected[2] == sha for selected in selected_inputs),
                                'depends': obj.get('Depends', ''), 'pre_depends': obj.get('Pre-Depends', '')}
                               for path, obj, sha in inputs], 'packages': packages}
        (directory / 'resolution.json').write_text(json.dumps(evidence, indent=2) + '\n')
        if (self.base / 'state/status').stat().st_size:
            raise package.Invalid('isolated solver status unexpectedly changed')
        return Qualified(root, candidate, directory, self.arch)


class Qualified:
    def __init__(self, root, candidate, directory, arch):
        self.root, self.candidate, self.directory, self.arch = root, candidate, directory, arch

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
