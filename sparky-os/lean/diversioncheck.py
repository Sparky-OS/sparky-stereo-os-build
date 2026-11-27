# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Report diversion scripts and payload overlaps before the archive link gate."""

import re
import shlex
import subprocess
import tarfile
from pathlib import Path, PurePosixPath

from . import archive, package


_COMMAND = re.compile(r'(?<![\w.-])(?:/usr/(?:s?bin)/)?dpkg-divert(?=[ \t]|$)')
_PATH = r'/[A-Za-z0-9_./+-]+'
_VAR = r'[a-z][a-z0-9_]*'
_QUERY = {'--list', '--listpackage', '--truename'}
_SWITCH = {'--add', '--remove', '--rename', '--no-rename', '--quiet', '--local', '--test'}
_OPERAND = {'--divert', '--package'}


def _diversion_sources(script, commands):
    """Inspect explicit commands only. These findings never authorize a redirect."""
    sources = set()
    for match in commands:
        tail = script[match.end():].split('\n', 1)[0]
        if tail.split() and tail.split()[0] in _QUERY:
            continue
        # A compound or dynamic invocation is deliberately left unresolved.
        line_start = script.rfind('\n', 0, match.start()) + 1
        if script[line_start:match.start()].strip():
            raise ValueError('diversion command is embedded in shell code')
        words = iter(shlex.split(re.sub(r'\s*>\s*/dev/null\s*$', '', tail), comments=True))
        action, source = '--add', None
        for word in words:
            if word in _OPERAND:
                if next(words, None) is None:
                    raise ValueError('missing diversion option value')
            elif word in _SWITCH:
                if word in ('--add', '--remove'):
                    action = word
            elif source is None:
                source = word
            else:
                raise ValueError('diversion command has an unknown argument')
        if source is None:
            raise ValueError('missing diversion source')
        if action == '--remove':
            continue
        if re.fullmatch(_PATH, source):
            paths = [source]
        else:
            var = re.fullmatch(r'\$(' + _VAR + ')', source)
            if not var:
                raise ValueError(f'unresolved diversion source {source!r}')
            name = var[1]
            # Count all literal bindings, including other loops using this
            # variable. A possible overlap still needs the reviewer's attention.
            bindings = re.findall(
                rf'^[ \t]*(?:{name}=([^\n]*)|for {name} in ([^\n]*); do[ \t]*)$',
                script[:match.start()], re.MULTILINE)
            paths = [path for binding in bindings for value in binding for path in value.split()]
            if not paths:
                raise ValueError(f'no literal binding for diversion source {source!r}')
        for path in paths:
            if (not re.fullmatch(_PATH, path) or path.startswith('//')
                    or '..' in PurePosixPath(path).parts or str(PurePosixPath(path)) != path):
                raise ValueError(f'unsafe or unresolved diversion path {path!r}')
            sources.add(path)
    return sources


def _shipped_sources(deb, sources):
    if not sources:
        return set()
    with subprocess.Popen(['dpkg-deb', '--fsys-tarfile', str(deb)], stdout=subprocess.PIPE) as proc:
        try:
            with tarfile.open(fileobj=proc.stdout, mode='r|') as data:
                shipped = {
                    '/' + str(PurePosixPath(member.name))
                    for member in data
                    if '/' + str(PurePosixPath(member.name)) in sources
                }
            # Drain archive padding before checking the decompressor's status.
            while proc.stdout.read(65536):
                pass
        except (OSError, tarfile.TarError) as exc:
            proc.kill()
            raise package.Invalid(f'{deb}: cannot inspect data archive: {exc}') from exc
        if proc.wait():
            raise package.Invalid(f'{deb}: cannot inspect data archive')
    return shipped


def check(pool):
    paths = sorted(Path(pool).rglob('*.deb'))
    if not paths:
        raise package.Invalid('empty diversion check pool')
    modeled = unmodeled = blocked = 0
    for deb in paths:
        script = archive.preinst_script(deb)
        if script is None:
            continue
        text = '\n'.join(line for line in script.split('\n') if not line.lstrip(' \t').startswith('#'))
        text = re.sub(r' \\\n[ \t]+', ' ', text)
        commands = list(_COMMAND.finditer(text))
        if not commands:
            continue
        try:
            declarations = archive.static_diversions(deb, archive.control(deb), script=script)
        except package.Invalid as exc:
            reason = str(exc)
        else:
            if declarations:
                modeled += 1
                print(f'{deb.name}\tmodelled\tstatic declarations: ' +
                      ', '.join(row['source'] for row in declarations))
                continue
            reason = 'preinst did not produce static declarations'
        unmodeled += 1
        try:
            sources = _diversion_sources(text, commands)
            shipped = _shipped_sources(deb, sources)
        except ValueError as exc:
            detail = f'ships diverted path: unknown ({exc})'
            blocked += 1
        else:
            detail = 'ships diverted path: ' + (', '.join(sorted(shipped)) if shipped else 'no')
            if sources:
                detail += '; inspected ' + ', '.join(sorted(sources))
            else:
                detail += '; no additions'
            blocked += bool(shipped)
        print(f'{deb.name}\tunmodelled\t{detail}\t{reason}')
    print(f'{len(paths)} archives, {modeled} modelled, {unmodeled} unmodelled, {blocked} blocked')
    if blocked:
        raise package.Invalid(f'{blocked} unmodelled diversion scripts ship a diverted path or have unresolved sources')
