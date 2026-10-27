"""Static package diversions, with dpkg-divert as the independent oracle."""

import json
import io
import os
import subprocess
import tarfile

import pytest

from lean import archive, linkcheck, package
from lean.tests.archive_fixtures import deb as fixture_deb, signed_archive


def deb(base, name, **kwargs):
    files = dict(kwargs.pop('files', {}))
    if 'DEBIAN/preinst' in files:
        script = base / (name + '-preinst')
        script.write_bytes(files['DEBIAN/preinst'])
        files['DEBIAN/preinst'] = script
    return fixture_deb(base, name, files=files, **kwargs)


def preinst(owner='wrapper', paths='/usr/share/fixture/banner', suffix='.original'):
    return ('#!/bin/sh\nset -e\n'
            'if [ "$1" = "install" ] || [ "$1" = "upgrade" ]; then\n'
            f'for f in {paths}; do\n'
            f'dpkg-divert --quiet --package {owner} --add --rename --divert "$f{suffix}" "$f"\n'
            'done\nfi\nexit 0\n').encode()


def pair(base, script=None, original=None, replacement=None):
    name = 'usr/share/fixture/banner'
    old = deb(base, 'original', files={name: b'original' if original is None else original})
    new = deb(base, 'wrapper', depends='original', files={
        name: b'replacement' if replacement is None else replacement,
        'DEBIAN/preinst': preinst() if script is None else script})
    return old, new


def extract(paths, root):
    root.mkdir()
    selected = [(p, archive.control(p)) for p in paths]
    diversions = archive.diversion_map(selected, root)
    for path, obj in selected:
        archive.unpack(path, root, diversions=diversions, package_name=obj['Package'])
    return diversions


@pytest.mark.parametrize('reverse', [False, True])
def test_static_diversion_matches_dpkg_oracle(tmp_path, reverse):
    old, new = pair(tmp_path)
    oracle = tmp_path / 'dpkg-root'
    oracle.mkdir()
    (oracle / 'var/lib/dpkg').mkdir(parents=True)
    archive.unpack(old, oracle)
    # --root is explicit and owned; no installation or maintainer script runs.
    env = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}
    subprocess.run(['dpkg-divert', '--root', str(oracle), '--package', 'wrapper', '--add', '--rename',
                    '--divert', '/usr/share/fixture/banner.original', '/usr/share/fixture/banner'],
                   env=env, check=True, capture_output=True)
    archive.unpack(new, oracle)
    root = tmp_path / 'qualified'
    rows = extract([new, old] if reverse else [old, new], root)
    for name in ('banner', 'banner.original'):
        assert (root / 'usr/share/fixture' / name).read_bytes() == (oracle / 'usr/share/fixture' / name).read_bytes()
    assert next(iter(rows.values()))['archive_sha256'] == archive.digest(new)


def test_undeclared_collision_still_blocks(tmp_path):
    old, new = pair(tmp_path, script=b'#!/bin/sh\nexit 0\n')
    with pytest.raises(package.Invalid, match='different payloads'):
        extract([old, new], tmp_path / 'root')


@pytest.mark.parametrize('script', [
    preinst(owner='someone-else'),
    preinst(paths='/usr/share/fixture/../banner'),
    preinst(paths='/usr//share/fixture/banner'),
    preinst(paths='"/usr/share/fixture/banner"'),
    preinst(paths='$(touch /outside-root)'),
    preinst().replace(b'--add', b'--remove'),
    preinst().replace(b'--rename', b'--no-rename'),
    preinst().replace(b'set -e', b'set +e'),
    preinst().replace(b'exit 0', b'touch /outside-root\nexit 0'),
    preinst().replace(b'#!/bin/sh', b'#!/bin/bash'),
    preinst().replace(b'"$f.original"', b'$f.original'),
    preinst().replace(b'"install"', b'"remove"'),
    preinst().replace(b'for f ', b'for PATH ').replace(b'$f', b'$PATH'),
    preinst().replace(b'for f ', b'for DPKG_ROOT ').replace(b'$f', b'$DPKG_ROOT'),
])
def test_unrecognized_or_unsafe_diversion_rejected(tmp_path, script):
    old, new = pair(tmp_path, script=script)
    with pytest.raises(package.Invalid, match='diversion'):
        extract([old, new], tmp_path / 'root')
    assert not (tmp_path / 'outside-root').exists()


@pytest.mark.parametrize('mode', ['duplicate', 'owner', 'chain'])
def test_multiple_diversions_rejected(tmp_path, mode):
    old, new = pair(tmp_path, script=preinst(paths='/usr/share/fixture/banner /usr/share/fixture/banner')
                    if mode == 'duplicate' else None)
    paths = [old, new]
    if mode != 'duplicate':
        source = '/usr/share/fixture/banner.original' if mode == 'chain' else '/usr/share/fixture/banner'
        paths.append(deb(tmp_path, 'second', files={'DEBIAN/preinst': preinst('second', source)}))
    with pytest.raises(package.Invalid, match='conflicting or chained diversion'):
        extract(paths, tmp_path / 'root')


@pytest.mark.parametrize('content', [b'original', b'different'])
def test_occupied_target_rejected_even_when_identical(tmp_path, content):
    old, new = pair(tmp_path)
    third = deb(tmp_path, 'third', files={'usr/share/fixture/banner.original': content})
    with pytest.raises(package.Invalid, match='diversion destination already supplied'):
        extract([old, new, third], tmp_path / 'root')
    oracle = tmp_path / 'dpkg-root'
    oracle.mkdir()
    (oracle / 'var/lib/dpkg').mkdir(parents=True)
    archive.unpack(old, oracle)
    archive.unpack(third, oracle)
    result = subprocess.run(['dpkg-divert', '--root', str(oracle), '--package', 'wrapper', '--add', '--rename',
                             '--divert', '/usr/share/fixture/banner.original', '/usr/share/fixture/banner'],
                            env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}, capture_output=True)
    # Some dpkg versions allow identical destination bytes. The data-only gate
    # deliberately refuses this ambiguous ownership even on those versions.
    if content != b'original':
        assert result.returncode != 0


@pytest.mark.parametrize('kind', ['source-symlink', 'parent-symlink', 'directory'])
def test_diversion_does_not_hide_nonregular_paths(tmp_path, kind):
    if kind == 'source-symlink':
        old, new = pair(tmp_path, original=('/outside-root',))
        paths = [old, new]
    elif kind == 'parent-symlink':
        old, new = pair(tmp_path)
        parent = deb(tmp_path, 'parent', files={'usr/share/fixture': ('/somewhere-else',)})
        paths = [parent, old, new]
    else:
        new = deb(tmp_path, 'wrapper', files={'DEBIAN/preinst': preinst(),
                                            'usr/share/fixture/banner/child': b'child'})
        paths = [new]
    with pytest.raises(package.Invalid, match='diversion'):
        extract(paths, tmp_path / 'root')


def test_real_solver_and_elf_run_after_diversion(tmp_path):
    source = tmp_path / 'probe.c'
    source.write_text('#include <stdio.h>\nint main(void) { FILE *f=fopen("/usr/share/fixture/banner.original","r"); '
                      'return !f || fgetc(f)!=\'o\'; }\n')
    binary = tmp_path / 'probe'
    subprocess.run(['cc', str(source), '-o', str(binary)], check=True)
    old, new = pair(tmp_path)
    config = signed_archive(tmp_path / 'repository', additional=[old, new])
    candidate = deb(tmp_path, 'consumer', depends='libc6, wrapper', files={'usr/bin/probe': binary})
    context = archive.Archive(config, tmp_path / 'scratch', 'amd64')
    q = context.qualify(candidate)
    try:
        evidence = json.loads((q.directory / 'resolution.json').read_text())
        assert evidence['diversions'][0]['owner'] == 'wrapper'
        assert linkcheck.compare(candidate, qualified=q)[0] == []
        assert q.run(['/usr/bin/probe']).returncode == 0
    finally:
        q.close()


def test_frozen_input_preinst_tamper_blocks(tmp_path):
    old, new = pair(tmp_path)
    config = signed_archive(tmp_path / 'repository')
    context = archive.Archive(config, tmp_path / 'scratch', 'amd64')
    context.input(new)
    (tmp_path / 'wrapper-1-amd64/DEBIAN/preinst').write_bytes(preinst().replace(b'.original', b'.changed'))
    subprocess.run(['dpkg-deb', '--build', '--root-owner-group', str(tmp_path / 'wrapper-1-amd64'), str(new)],
                   check=True, stdout=subprocess.DEVNULL)
    with pytest.raises(package.Invalid, match='changed'):
        context.qualify(new, [old])


def test_hardlink_keeps_the_diverted_packages_bytes(tmp_path):
    old, new = pair(tmp_path)
    stage = tmp_path / 'original-1-amd64'
    os.link(stage / 'usr/share/fixture/banner', stage / 'usr/share/fixture/copy')
    subprocess.run(['dpkg-deb', '--build', '--root-owner-group', str(stage), str(old)],
                   check=True, stdout=subprocess.DEVNULL)
    root = tmp_path / 'root'
    extract([new, old], root)
    assert (root / 'usr/share/fixture/copy').read_bytes() == b'original'


@pytest.mark.parametrize('collision', [False, True])
def test_unmodeled_effects_never_authorize_redirection(tmp_path, collision):
    script = preinst().replace(b'exit 0', b'echo arbitrary-effect\nexit 0')
    old, new = pair(tmp_path, script=script)
    if not collision:
        new = deb(tmp_path, 'unrelated', files={'DEBIAN/preinst': script})
    config = signed_archive(tmp_path / 'repository', additional=[old, new])
    candidate = deb(tmp_path, 'consumer', depends='original, ' + archive.control(new)['Package'])
    context = archive.Archive(config, tmp_path / 'scratch', 'amd64')
    if collision:
        with pytest.raises(package.Invalid, match='different payloads'):
            context.qualify(candidate)
        evidence = json.loads(next(context.base.glob('case-*/diversions.json')).read_text())
        assert evidence['applied'] == []
        assert len(evidence['unmodeled_scripts']) == 1
    else:
        q = context.qualify(candidate)
        try:
            evidence = json.loads((q.directory / 'resolution.json').read_text())
            assert evidence['diversions'] == []
            assert len(evidence['unmodeled_diversion_scripts']) == 1
            assert (q.root / 'usr/share/fixture/banner').read_bytes() == b'original'
            assert not (q.root / 'usr/share/fixture/banner.original').exists()
        finally:
            q.close()


@pytest.mark.parametrize('variant', ['alias', 'duplicate-alias', 'not-executable'])
def test_ambiguous_or_unusable_preinst_control_member_rejected(tmp_path, variant):
    _, new = pair(tmp_path)
    raw = subprocess.check_output(['dpkg-deb', '--ctrl-tarfile', str(new)])
    target = tmp_path / 'control.tar.xz'
    with tarfile.open(fileobj=io.BytesIO(raw)) as before, tarfile.open(target, 'w:xz') as after:
        for member in before:
            data = before.extractfile(member).read() if member.isfile() else None
            if member.name == './preinst':
                if variant == 'alias':
                    member.name = '././preinst'
                elif variant == 'not-executable':
                    member.mode = 0o644
            after.addfile(member, io.BytesIO(data) if data is not None else None)
        if variant == 'duplicate-alias':
            data = b'#!/bin/sh\nexit 0\n'
            member = tarfile.TarInfo('././preinst')
            member.mode, member.size = 0o755, len(data)
            after.addfile(member, io.BytesIO(data))
    subprocess.run(['ar', 'r', str(new), str(target)], check=True, capture_output=True)
    if variant == 'duplicate-alias':
        extracted = tmp_path / 'control-oracle'
        subprocess.run(['dpkg-deb', '--control', str(new), str(extracted)], check=True)
        assert (extracted / 'preinst').read_bytes() == b'#!/bin/sh\nexit 0\n'
    with pytest.raises(package.Invalid, match='preinst control member'):
        archive.static_diversions(new, archive.control(new))
