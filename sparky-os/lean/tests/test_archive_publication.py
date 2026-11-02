"""Versioned edition snapshots and bounded archive scratch, through real APT/ELF."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
from unittest.mock import patch

import pytest

from lean import archive, linkcheck, package, release
from lean.tests.archive_fixtures import deb, signed_archive


@pytest.fixture(scope='module')
def sources(tmp_path_factory):
    return signed_archive(tmp_path_factory.mktemp('publication-archive'))


def edition(base, broken=False, dependency='2'):
    base.mkdir(parents=True)
    lib = base / 'library.c'
    binary = base / 'libedition.so.1'
    programs = []
    libraries = []
    for version, symbol in (('1', 'edition_previous'), ('2', 'edition_current')):
        lib.write_text(f'int {symbol}(void) {{ return 7; }}\n')
        subprocess.run(['cc', '-shared', '-fPIC', str(lib), '-o', str(binary),
                        '-Wl,-soname,libedition.so.1'], check=True)
        main = base / 'main.c'
        main.write_text(f'int {symbol}(void);\nint main(void) {{ return {symbol}() != 7; }}\n')
        program = base / 'probe'
        subprocess.run(['cc', str(main), '-o', str(program), str(binary)], check=True)
        programs.append(deb(base, 'edition-consumer', version, depends=
            f'edition-library (= {dependency if version == "2" else "1"}), common-edition (= 7), libc6',
            files={'usr/bin/probe': program}))
        if broken and version == '2':
            lib.write_text('int edition_previous(void) { return 7; }\n')
            subprocess.run(['cc', '-shared', '-fPIC', str(lib), '-o', str(binary),
                            '-Wl,-soname,libedition.so.1'], check=True)
        libraries.append(deb(base, 'edition-library', version, depends='libc6', files={'usr/lib/libedition.so.1': binary}))
    common = deb(base, 'common-edition', '7', files={'usr/share/common-edition/identity': b'unchanged edition'})
    return programs, libraries, common


def resolutions(scratch):
    return [(p, json.loads(p.read_text())) for p in scratch.glob('link-*/case-*/resolution.json')]


def selected_inputs(obj):
    return {tuple(r['identity']): r['sha256'] for r in obj['inputs'] if r['selected']}


def test_exact_version_upgrade_has_comparable_correct_universes(sources, tmp_path):
    programs, libraries, common = edition(tmp_path / 'build')
    previous = tmp_path / 'previous'
    previous.mkdir()
    for path in (programs[0], libraries[0], common):
        shutil.copyfile(path, previous / path.name)
    scratch = tmp_path / 'scratch'
    release.check_link([programs[1]], previous, archive_config=sources, scratch=scratch,
                       siblings=[libraries[1], common])
    rows = resolutions(scratch)
    before = next(obj for _, obj in rows if obj['candidate'][1] == '1')
    now = next(obj for _, obj in rows if obj['candidate'][1] == '2')
    assert ('edition-library', '1', 'amd64') in selected_inputs(before)
    assert ('edition-library', '2', 'amd64') in selected_inputs(now)
    assert selected_inputs(before)[('common-edition', '7', 'amd64')] == selected_inputs(now)[('common-edition', '7', 'amd64')]
    assert before['metadata'] == now['metadata']
    assert all(not (p.parent / 'root').exists() and (p.parent / 'root-files.jsonl').is_file() for p, _ in rows)
    assert len(list((scratch / 'sha256').glob(archive.digest(common) + '.deb'))) == 1


def test_direct_upgrade_with_explicit_previous_siblings(sources, tmp_path):
    programs, libraries, common = edition(tmp_path / 'build')
    context = archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    linkcheck.check(programs[0], archive_context=context, siblings=[libraries[0], common])
    linkcheck.check(programs[1], archive_context=context, siblings=[libraries[1], common])
    linkcheck.check(programs[1], programs[0], archive_context=context,
                   siblings=[libraries[1], common], previous_siblings=[libraries[0], common])
    assert not context._active


def test_broken_new_library_still_fails_with_good_old_universe(sources, tmp_path):
    programs, libraries, common = edition(tmp_path / 'build', broken=True)
    context = archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    linkcheck.check(programs[0], archive_context=context, siblings=[libraries[0], common])
    with pytest.raises(package.Invalid, match='edition_current'):
        linkcheck.check(programs[1], programs[0], archive_context=context,
                       siblings=[libraries[1], common], previous_siblings=[libraries[0], common])
    assert not context._active


def test_broken_new_dependency_is_not_satisfied_by_previous_inputs(sources, tmp_path):
    programs, libraries, common = edition(tmp_path / 'build', dependency='3')
    context = archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    linkcheck.check(programs[0], archive_context=context, siblings=[libraries[0], common])
    with pytest.raises(package.Invalid, match='solve failed'):
        linkcheck.check(programs[1], programs[0], archive_context=context,
                       siblings=[libraries[1], common], previous_siblings=[libraries[0], common])


def test_missing_previous_dependency_is_not_borrowed_from_new(sources, tmp_path):
    programs, libraries, common = edition(tmp_path / 'build')
    context = archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    with pytest.raises(package.Invalid, match='previous edition dependency qualification failed'):
        linkcheck.check(programs[1], programs[0], archive_context=context,
                       siblings=[libraries[1], common], previous_siblings=[common])


def test_ambiguous_previous_snapshots_do_not_weaken_pins(sources, tmp_path):
    programs, libraries, common = edition(tmp_path / 'build')
    intermediate = deb(tmp_path, 'edition-library', '1.5', files={'usr/share/unused': b'other snapshot'})
    context = archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    with pytest.raises(package.Invalid, match='one authoritative edition snapshot'):
        linkcheck.check(programs[1], programs[0], archive_context=context, siblings=[libraries[1], common],
                        previous_siblings=[libraries[0], intermediate, common])


def test_missing_previous_directory_is_an_error(sources, tmp_path):
    candidate = deb(tmp_path, 'consumer')
    with pytest.raises(package.Invalid, match='previous package directory is missing'):
        release.check_link([candidate], tmp_path / 'absent', archive_config=sources, scratch=tmp_path / 'scratch')


def allocated_tree(root):
    """Count physical blocks once per inode, without following offered-source symlinks."""
    inodes, size = set(), 0
    for base, dirs, names in os.walk(root, followlinks=False):
        for name in dirs + names:
            st = (Path(base) / name).lstat()
            key = (st.st_dev, st.st_ino)
            if key not in inodes:
                inodes.add(key)
                size += st.st_blocks * 512
    return size, inodes


def test_unrelated_archive_bytes_and_inodes_do_not_multiply(sources, tmp_path):
    candidate = deb(tmp_path, 'tiny-no-dependencies')
    offered = [deb(tmp_path, f'unrelated-sibling-{i}', files={f'usr/share/unrelated-{i}/blob': os.urandom(256 << 10)})
               for i in range(12)]
    original = {p: (archive.digest(p), p.stat().st_mode, p.stat().st_ino) for p in offered}
    context = archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    measurements = []
    cached_inodes = None
    for _ in range(3):
        q = context.qualify(candidate, offered)
        assert [r['identity'][0] for r in json.loads((q.directory / 'resolution.json').read_text())['inputs']
                if r['selected']] == ['tiny-no-dependencies']
        assert not list(q.directory.glob('*.deb'))
        q.close()
        cache = list(context.cache.glob('*.deb'))
        assert len(cache) == 1
        current = {(p.stat().st_dev, p.stat().st_ino) for p in cache}
        assert cached_inodes is None or cached_inodes == current
        cached_inodes = current
        measurements.append(allocated_tree(context.base)[0])
    assert measurements[-1] - measurements[0] < 256 << 10
    assert all((archive.digest(p), p.stat().st_mode, p.stat().st_ino) == original[p] for p in offered)
    assert len(list(context.universes.iterdir())) == 1
    assert not list(context.base.glob('case-*/root'))


def test_selected_bytes_are_cached_once_without_source_hardlinks(sources, tmp_path):
    payload = os.urandom(1 << 20)
    sibling = deb(tmp_path, 'selected-edition', files={'usr/share/selected/blob': payload})
    candidate = deb(tmp_path, 'consumer', depends='selected-edition')
    context = archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    inodes = set()
    for _ in range(3):
        q = context.qualify(candidate, [sibling])
        assert (q.root / 'usr/share/selected/blob').read_bytes() == payload
        cached = context.cache / (archive.digest(sibling) + '.deb')
        inodes.add(cached.stat().st_ino)
        assert cached.stat().st_ino != sibling.stat().st_ino
        assert cached.stat().st_mode & 0o222 == 0
        q.close()
    assert len(inodes) == 1
    assert not list(context.base.glob('case-*/root'))


def test_active_root_limit_and_inventory(sources, tmp_path):
    candidate = deb(tmp_path, 'consumer')
    context = archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    first, second = context.qualify(candidate), context.qualify(candidate)
    with pytest.raises(package.Invalid, match='two qualified roots are still active'):
        context.qualify(candidate)
    first.close()
    third = context.qualify(candidate)
    second.close()
    third.close()
    assert not context._active


def disk_free(free):
    return shutil._ntuple_diskusage(100 << 30, (100 << 30) - free, free)


def test_low_space_refuses_before_snapshot_import_or_apt(sources, tmp_path):
    with patch('lean.archive.shutil.disk_usage', return_value=disk_free((12 << 30) - 1)):
        with pytest.raises(package.Invalid, match='below root floor'):
            archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    assert not (tmp_path / 'scratch').exists()


def test_low_space_refuses_selected_copy_without_crossing_floor(sources, tmp_path):
    context = archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    candidate = deb(tmp_path, 'large-input', files={'usr/share/blob': os.urandom(1 << 20)})
    item = context.input(candidate)
    with patch('lean.archive.shutil.disk_usage', return_value=disk_free((12 << 30) + item['size'] - 1)):
        with pytest.raises(package.Invalid, match='insufficient space'):
            context.cached_input(item)
    assert not list(context.cache.iterdir())


def test_low_space_refuses_extraction_before_payload_write(sources, tmp_path):
    candidate = deb(tmp_path, 'payload', files={'usr/share/blob': os.urandom(1 << 20)})
    root = tmp_path / 'root'
    root.mkdir()
    with patch('lean.archive.shutil.disk_usage', return_value=disk_free((12 << 30) + (512 << 10))):
        with pytest.raises(package.Invalid, match='insufficient space'):
            archive.unpack(candidate, root)
    assert not (root / 'usr/share/blob').exists()


def test_low_space_while_checking_a_download_is_reported_as_space(sources, tmp_path):
    # the identity check asks APT for the downloaded record; a disk floor reached there
    # must not be reported as a record absent from the signed index
    context = archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    candidate = deb(tmp_path, 'consumer', depends='libxrandr2')
    original = archive.Archive.run

    def run(self, args, label, **options):
        if args[:2] == ['apt-cache', 'show']:
            raise package.NoSpace('/: free space 1 is below root floor 12884901888')
        return original(self, args, label, **options)

    with patch.object(archive.Archive, 'run', run):
        with pytest.raises(package.NoSpace, match='below root floor') as raised:
            context.qualify(candidate)
    assert 'absent from signed index' not in str(raised.value)


def test_raised_scratch_floor_and_minimum_configuration(sources, tmp_path):
    with patch('lean.archive.shutil.disk_usage', return_value=disk_free(13 << 30)):
        with pytest.raises(package.Invalid, match='insufficient space'):
            archive.Archive(sources, tmp_path / 'scratch', 'amd64', min_free_gib=14)
    with pytest.raises(package.Invalid, match='floors cannot be below'):
        archive.Archive(sources, tmp_path / 'low', 'amd64', root_min_free_gib=1)


def test_frozen_input_drift_is_rejected(sources, tmp_path):
    candidate = deb(tmp_path, 'consumer')
    context = archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    q = context.qualify(candidate)
    q.close()
    candidate.write_bytes(candidate.read_bytes() + b'changed')
    with pytest.raises(package.Invalid, match='input changed after its universe was frozen'):
        context.qualify(candidate)


def test_corrupt_local_index_is_rejected(sources, tmp_path):
    candidate = deb(tmp_path, 'consumer')
    context = archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    q = context.qualify(candidate)
    q.close()
    index = next(context.universes.glob('*/Packages'))
    index.chmod(0o644)
    index.write_bytes(b'changed')
    with pytest.raises(package.Invalid, match='corrupt immutable local index'):
        context.qualify(candidate)


def qualify_payload(raw, output, stage):
    stage.mkdir(parents=True)
    archive.unpack(raw, stage)
    (stage / 'DEBIAN').mkdir()
    (stage / 'DEBIAN/control').write_text(subprocess.check_output(['dpkg-deb', '-f', str(raw)], text=True))
    release.build_tree(stage, output)


FAKE_DOCKER = r'''#!/usr/bin/env python3
"""Stands in for Docker and Debian's appstream-generator: records each call, writes a workspace like the generator's."""
import gzip, io, json, os, sys, tarfile
from pathlib import Path

args = sys.argv[1:]
with open(os.environ['FAKE_DOCKER_LOG'], 'a') as log:
    log.write(json.dumps(args) + '\n')
if args[:2] == ['image', 'inspect']:
    if args[2] in os.environ.get('FAKE_DOCKER_MISSING', '').split():
        sys.exit('Error: No such image: ' + args[2])
    sys.exit(0)
assert args[0] == 'run', args
mounts = [args[i + 1] for i, a in enumerate(args) if a == '-v']
dep11 = Path(next(m.split(':')[0] for m in mounts if m.split(':')[1] == '/dep11'))
if os.environ.get('FAKE_ASGEN_FAIL'):
    print('fake appstream-generator: failing as the test asked', file=sys.stderr)
    sys.exit(3)
config = json.loads((dep11 / 'config/config.json').read_text())
work = dep11 / 'workspace'
data = work / 'export/data/mashtabba/main'
data.mkdir(parents=True)
for junk in ('db/main/data.mdb', 'export/hints/mashtabba/main/Hints-amd64.json.gz', 'export/html/index.html',
             'export/data/mashtabba/main/CID-Index-amd64.json.gz', 'export/data/mashtabba/main/Components-amd64.yml.xz'):
    (work / junk).parent.mkdir(parents=True, exist_ok=True)
    (work / junk).write_bytes(b'generator working file\n')
if os.environ.get('FAKE_ASGEN_EMPTY'):
    sys.exit(0)
for arch in config['Suites']['mashtabba']['architectures']:
    packages = (dep11 / f'archive/dists/mashtabba/main/binary-{arch}/Packages').read_text()
    names = sorted(line.split(': ', 1)[1] for line in packages.splitlines() if line.startswith('Package: '))
    text = 'File: DEP-11\nVersion: "1.0"\nOrigin: Sparky Stereo OS\n' + ''.join(
        f'---\nType: desktop-application\nID: org.example.{name}\nPackage: {name}\n' for name in names)
    with (data / f'Components-{arch}.yml.gz').open('wb') as raw:
        with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as stream:
            stream.write(text.encode())
for size in ('48x48', '64x64', '128x128'):
    with tarfile.open(data / f'icons-{size}.tar.gz', 'w:gz') as tar:
        for name in ('zz-late.png', 'org.example.edition-consumer.png'):
            info = tarfile.TarInfo(name)
            payload = f'{size} {name}\n'.encode()
            info.size, info.mtime = len(payload), 1700000000 + len(name)
            tar.addfile(info, io.BytesIO(payload))
'''


def fake_docker(directory):
    directory.mkdir(parents=True, exist_ok=True)
    executable = directory / 'docker'
    executable.write_text(FAKE_DOCKER)
    executable.chmod(0o755)
    return executable


def docker_calls(env):
    log = Path(env['FAKE_DOCKER_LOG'])
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


@pytest.fixture
def publisher_env(sources, tmp_path):
    # Synthetic key only. A short isolated home avoids Unix socket path limits. Docker and the AppStream generator are
    # a recording stand-in, so the catalogues are made by default, as on the edition's machines.
    fake = fake_docker(tmp_path / 'fake-docker')
    with tempfile.TemporaryDirectory(prefix='lc-pub-', dir='/tmp') as home:
        env = {'PATH': f'{fake.parent}:/usr/sbin:/usr/bin:/sbin:/bin', 'LC_ALL': 'C', 'HOME': str(tmp_path),
               'FAKE_DOCKER_LOG': str(tmp_path / 'fake-docker/calls.jsonl'),
               'GNUPGHOME': home, 'SPARKY_REPO_GNUPGHOME': home, 'TMPDIR': str(tmp_path),
               'SPARKY_LC_ARCHIVE_CONFIG': str(sources), 'SPARKY_LC_SCRATCH': str(tmp_path / 'link-scratch')}
        try:
            subprocess.run(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', '',
                            '--quick-generate-key', 'Publisher fixture', 'ed25519', 'sign', '0'],
                           env=env, check=True, capture_output=True)
            listing = subprocess.check_output(['gpg', '--batch', '--with-colons', '--list-keys'], env=env, text=True)
            env['SPARKY_REPO_KEY'] = next(line.split(':')[9] for line in listing.splitlines() if line.startswith('fpr:'))
            yield env
        finally:
            subprocess.run(['gpgconf', '--kill', 'gpg-agent'], env=env, capture_output=True)


def publish_fixture(source, destination, env):
    publisher = Path(__file__).resolve().parents[2] / 'repo/publish-tree.sh'
    return subprocess.run(['bash', str(publisher), str(source), str(destination)],
                          env=env, capture_output=True, text=True, timeout=180)


def tree_hashes(root):
    return {str(path.relative_to(root)): archive.digest(path) for path in root.rglob('*') if path.is_file()}


def test_actual_publisher_wires_destination_previous_snapshot(publisher_env, tmp_path):
    programs, libraries, common = edition(tmp_path / 'build')
    old_out, new_out = tmp_path / 'old-out', tmp_path / 'new-out'
    for i, raw in enumerate((programs[0], libraries[0], common)):
        qualify_payload(raw, old_out, tmp_path / f'old-stage-{i}')
    for i, raw in enumerate((programs[1], libraries[1])):
        qualify_payload(raw, new_out, tmp_path / f'new-stage-{i}')
    shutil.copyfile(old_out / common.name, new_out / common.name)
    destination = tmp_path / 'published-fixture'
    first = publish_fixture(old_out, destination, publisher_env)
    assert first.returncode == 0, first.stdout + first.stderr
    # No manually supplied previous-dir: the real destination is the prior universe.
    second = publish_fixture(new_out, destination, publisher_env)
    assert second.returncode == 0, second.stdout + second.stderr
    rows = resolutions(Path(publisher_env['SPARKY_LC_SCRATCH']))
    matched = []
    for _, obj in rows:
        if obj['candidate'][0] == 'edition-consumer':
            version = obj['candidate'][1]
            assert ('edition-library', version, 'amd64') in selected_inputs(obj)
            matched.append(obj)
    assert any(obj['candidate'][1] == '2' for obj in matched)
    assert any('/published-fixture/pool/' in row['source'] for obj in matched if obj['candidate'][1] == '1'
               for row in obj['inputs'] if row['selected'] and row['identity'][0] == 'edition-library')
    signed = subprocess.run(['gpg', '--batch', '--decrypt', str(destination / 'dists/mashtabba/InRelease')],
                            env=publisher_env, capture_output=True, text=True)
    assert signed.returncode == 0, signed.stderr
    assert not list(Path(publisher_env['SPARKY_LC_SCRATCH']).glob('link-*/case-*/root'))
    # An invalid new dependency must fail before changing the good published tree.
    before = tree_hashes(destination)
    broken = deb(tmp_path, 'edition-consumer', '3', depends='edition-library (= 9), libc6',
                 files={'usr/bin/probe': tmp_path / 'build/probe'})
    broken_out = tmp_path / 'broken-out'
    qualify_payload(broken, broken_out, tmp_path / 'broken-stage')
    for name in (libraries[1].name, common.name):
        shutil.copyfile(new_out / name, broken_out / name)
    failure = publish_fixture(broken_out, destination, publisher_env)
    assert failure.returncode != 0 and 'solve failed' in failure.stderr, failure.stdout + failure.stderr
    assert tree_hashes(destination) == before


MAIN_BEFORE_APPSTREAM = '6851488d4376a0a86626950391b2edfd818da39d'
DEP11_FILES = {'Components-amd64.yml', 'Components-amd64.yml.gz',
               'icons-48x48.tar.gz', 'icons-64x64.tar.gz', 'icons-128x128.tar.gz'}


def qualified_source(tmp_path):
    programs, libraries, common = edition(tmp_path / 'build')
    source = tmp_path / 'source'
    for i, raw in enumerate((programs[0], libraries[0], common)):
        qualify_payload(raw, source, tmp_path / f'stage-{i}')
    return source


def release_entries(root, part):
    release = (root / 'dists/mashtabba/Release').read_text()
    return {line.split()[2]: tuple(line.split()[:2]) for line in release.splitlines()
            if line.startswith(' ') and f'/{part}/' in line}


def signed_text(path, env):
    return subprocess.run(['gpg', '--batch', '--decrypt', str(path)], env=env,
                          capture_output=True, text=True, check=True).stdout


def without_date(text):
    return '\n'.join(line for line in text.splitlines() if not line.startswith('Date: '))


def main_publisher(directory):
    """The publisher of main before the AppStream catalogues, with the files it runs beside it."""
    repo = directory / 'repo'
    repo.mkdir(parents=True)
    tree = Path(__file__).resolve().parents[3]
    for name in ('publish-tree.sh', 'make-contents.py', 'check-installable.py', 'index.html'):
        (repo / name).write_bytes(subprocess.check_output(
            ['git', 'show', f'{MAIN_BEFORE_APPSTREAM}:sparky-os/repo/{name}'], cwd=tree))
    return repo / 'publish-tree.sh'


def test_appstream_catalogues_are_made_by_default(publisher_env, tmp_path):
    source = qualified_source(tmp_path)
    destination = tmp_path / 'published-fixture'
    first = publish_fixture(source, destination, publisher_env)
    assert first.returncode == 0, first.stdout + first.stderr
    pinned = (Path(__file__).resolve().parents[2] / 'repo/appstream/Dockerfile').read_text()
    version = pinned.split('appstream-generator=', 1)[1].split()[0]
    run = next(call for call in docker_calls(publisher_env) if call[0] == 'run')
    image = run[run.index('appstream-generator') - 1]
    assert image == f'sparky-appstream-generator:{version}'
    assert ['image', 'inspect', image] in docker_calls(publisher_env)
    for option, value in (('--pull', 'never'), ('--network', 'none'), ('--user', f'{os.getuid()}:{os.getgid()}'),
                          ('--cpus', '4')):
        assert run[run.index(option) + 1] == value
    mounts = [run[i + 1] for i, a in enumerate(run) if a == '-v']
    assert [m for m in mounts if not m.endswith(':/dep11')] and all(
        m.endswith(':ro') for m in mounts if not m.endswith(':/dep11'))
    assert f'AppStream catalogues: on, made by appstream-generator in {image}' in first.stdout
    assert 'AppStream catalogues: published in dists/mashtabba/main/dep11 (5 files' in first.stdout
    dep11 = destination / 'dists/mashtabba/main/dep11'
    assert {path.name for path in dep11.iterdir() if path.is_file()} == DEP11_FILES
    entries = release_entries(destination, 'dep11')
    assert set(entries) == {f'main/dep11/{name}' for name in DEP11_FILES}
    for name in DEP11_FILES:
        digest, size = entries[f'main/dep11/{name}']
        assert (archive.digest(dep11 / name), str((dep11 / name).stat().st_size)) == (digest, size)
        assert archive.digest(dep11 / 'by-hash/SHA256' / digest) == digest
    assert 'main/dep11/Components-amd64.yml' in signed_text(destination / 'dists/mashtabba/InRelease', publisher_env)
    with tarfile.open(dep11 / 'icons-64x64.tar.gz') as icons:
        assert [m.name for m in icons.getmembers()] == ['org.example.edition-consumer.png', 'zz-late.png']
        assert {(m.mtime, m.uid, m.mode) for m in icons.getmembers()} == {(0, 0, 0o644)}
    assert b'ID: org.example.edition-consumer\n' in (dep11 / 'Components-amd64.yml').read_bytes()
    published = {str(p.relative_to(destination)) for p in (destination / 'dists').rglob('*')}
    assert not [p for p in published if any(word in p for word in ('Hints', 'CID-Index', '.yml.xz', '.html', '.mdb'))]
    before = tree_hashes(destination)
    again = publish_fixture(source, destination, publisher_env)
    assert again.returncode == 0, again.stdout + again.stderr
    assert 'Release kept' in again.stdout and 'AppStream catalogues: unchanged (5 files' in again.stdout
    assert tree_hashes(destination) == before
    explicit = publish_fixture(source, destination, {**publisher_env, 'SPARKY_APPSTREAM': '1'})
    assert explicit.returncode == 0, explicit.stdout + explicit.stderr
    assert 'Release kept' in explicit.stdout and tree_hashes(destination) == before
    # SPARKY_APPSTREAM=0 publishes without them: the catalogues and their Release lines go, and it is said.
    off = publish_fixture(source, destination, {**publisher_env, 'SPARKY_APPSTREAM': '0'})
    assert off.returncode == 0, off.stdout + off.stderr
    assert 'AppStream catalogues: not made (SPARKY_APPSTREAM=0)' in off.stdout
    assert 'the earlier catalogues were removed from DEST' in off.stdout and 'Release signed' in off.stdout
    assert not dep11.exists() and not release_entries(destination, 'dep11')
    assert 'dep11' not in signed_text(destination / 'dists/mashtabba/InRelease', publisher_env)


def test_appstream_off_publishes_what_main_published(publisher_env, tmp_path):
    source = qualified_source(tmp_path)
    off = {**publisher_env, 'SPARKY_APPSTREAM': '0'}
    reference = {**publisher_env, 'SPARKY_LC_SCRATCH': str(tmp_path / 'main-link-scratch'),
                 'PYTHONPATH': str(Path(__file__).resolve().parents[2])}
    publisher = main_publisher(tmp_path / 'main')
    current, baseline = tmp_path / 'current-out', tmp_path / 'main-out'

    def both():
        ours = publish_fixture(source, current, off)
        assert ours.returncode == 0, ours.stdout + ours.stderr
        assert 'AppStream catalogues: not made (SPARKY_APPSTREAM=0)' in ours.stdout
        theirs = subprocess.run(['bash', str(publisher), str(source), str(baseline)], env=reference,
                                capture_output=True, text=True, timeout=180)
        assert theirs.returncode == 0, theirs.stdout + theirs.stderr
        signed = ('dists/mashtabba/InRelease', 'dists/mashtabba/Release.gpg', 'dists/mashtabba/Release')
        ours_tree, main_tree = tree_hashes(current), tree_hashes(baseline)
        for name in signed:
            ours_tree.pop(name)
            main_tree.pop(name)
        assert ours_tree == main_tree
        assert without_date((current / signed[2]).read_text()) == without_date((baseline / signed[2]).read_text())
        assert without_date(signed_text(current / signed[0], off)) == without_date(signed_text(baseline / signed[0], off))

    both()
    assert not (current / 'dists/mashtabba/main/dep11').exists()
    # An index copy older than the by-hash window goes in both, and a recent one stays in both.
    old, recent = time.time() - 10 * 86400, time.time() - 3600
    for root in (current, baseline):
        store = root / 'dists/mashtabba/main/binary-amd64/by-hash/SHA256'
        for name, stamp in (('0' * 64, old), ('1' * 64, recent)):
            (store / name).write_text('an index of an earlier run\n')
            os.utime(store / name, (stamp, stamp))
    both()
    for root in (current, baseline):
        store = root / 'dists/mashtabba/main/binary-amd64/by-hash/SHA256'
        assert not (store / ('0' * 64)).exists() and (store / ('1' * 64)).exists()


@pytest.mark.parametrize('fault', ['generator-fails', 'no-catalogue'])
def test_appstream_generator_failure_stops_before_signing(publisher_env, tmp_path, fault):
    source = qualified_source(tmp_path)
    destination = tmp_path / 'published-fixture'
    first = publish_fixture(source, destination, {**publisher_env, 'SPARKY_APPSTREAM': '0'})
    assert first.returncode == 0, first.stdout + first.stderr
    broken = {**publisher_env, ('FAKE_ASGEN_FAIL' if fault == 'generator-fails' else 'FAKE_ASGEN_EMPTY'): '1'}
    fresh = tmp_path / 'fresh-destination'
    for target in (destination, fresh):
        before = tree_hashes(target) if target.exists() else {}
        failure = publish_fixture(source, target, broken)
        assert failure.returncode == 1, failure.stdout + failure.stderr
        reason = ('appstream-generator failed (exit 3)' if fault == 'generator-fails'
                  else 'appstream-generator made no Components-amd64.yml.gz.')
        assert 'AppStream catalogues: ' + reason in failure.stderr
        assert 'Nothing in DEST was changed and no Release was signed.' in failure.stderr
        assert 'SPARKY_APPSTREAM=0' in failure.stderr and 'appstream/build-image.sh' in failure.stderr
        assert tree_hashes(target) == before
    assert not (fresh / 'dists').exists() and not (fresh / 'pool').exists()


def test_appstream_missing_image_stops_before_the_gates(publisher_env, tmp_path):
    source = qualified_source(tmp_path)
    destination = tmp_path / 'published-fixture'
    env = {**publisher_env, 'SPARKY_APPSTREAM_IMAGE': 'sparky-appstream-generator:absent',
           'FAKE_DOCKER_MISSING': 'sparky-appstream-generator:absent'}
    failure = publish_fixture(source, destination, env)
    assert failure.returncode == 1, failure.stdout + failure.stderr
    assert ('AppStream catalogues: the generator image sparky-appstream-generator:absent cannot be used: '
            'Error: No such image: sparky-appstream-generator:absent') in failure.stderr
    assert 'Nothing was changed.' in failure.stderr and 'appstream/build-image.sh' in failure.stderr
    assert 'SPARKY_APPSTREAM=0' in failure.stderr
    assert not any(destination.iterdir())
    assert not (tmp_path / 'link-scratch').exists()
    assert [call[0] for call in docker_calls(env)] == ['image']


@pytest.mark.parametrize('value', ['', 'yes', 'on', '2', 'true'])
def test_appstream_flag_takes_only_one_or_zero(publisher_env, tmp_path, value):
    source = qualified_source(tmp_path)
    refused = publish_fixture(source, tmp_path / 'published-fixture', {**publisher_env, 'SPARKY_APPSTREAM': value})
    assert refused.returncode == 2, refused.stdout + refused.stderr
    assert 'SPARKY_APPSTREAM must be 1 (the default: make the AppStream catalogues) or 0' in refused.stderr
    assert not docker_calls(publisher_env)


def test_actual_publisher_missing_old_edition_dependency_blocks(publisher_env, tmp_path):
    programs, libraries, common = edition(tmp_path / 'build')
    source = tmp_path / 'source'
    for i, raw in enumerate((programs[0], libraries[0], common)):
        qualify_payload(raw, source, tmp_path / f'stage-old-{i}')
    destination = tmp_path / 'published-fixture'
    first = publish_fixture(source, destination, publisher_env)
    assert first.returncode == 0, first.stdout + first.stderr
    old_library = next(destination.glob('pool/**/edition-library_1_amd64.deb'))
    old_library.unlink()  # Deliberately incomplete synthetic previous input, never a live pool.
    before = tree_hashes(destination)
    next_source = tmp_path / 'next-source'
    for i, raw in enumerate((programs[1], libraries[1])):
        qualify_payload(raw, next_source, tmp_path / f'stage-new-{i}')
    shutil.copyfile(source / common.name, next_source / common.name)
    failure = publish_fixture(next_source, destination, publisher_env)
    assert failure.returncode != 0 and 'edition-library' in failure.stderr, failure.stdout + failure.stderr
    assert tree_hashes(destination) == before


def test_previous_manifest_uses_control_identity_not_filename(tmp_path):
    old = deb(tmp_path, 'consumer', '1')
    renamed = tmp_path / (archive.digest(old) + '.deb')
    shutil.copyfile(old, renamed)
    new = deb(tmp_path, 'consumer', '2')
    assert release.previous_build(new, previous_debs=[renamed]) == renamed


def test_low_space_during_streaming_stops_before_next_chunk(tmp_path):
    import io
    source = io.BytesIO(b'x' * (3 << 20))
    destination = io.BytesIO()
    checks = []
    def available(required):
        checks.append(required)
        if len(checks) == 2:
            raise package.Invalid('controlled floor reached')
    with pytest.raises(package.Invalid, match='controlled floor reached'):
        archive.copy_stream(source, destination, available)
    assert len(destination.getvalue()) == 1 << 20


def test_old_wrong_version_is_explicitly_rejected(sources, tmp_path):
    programs, libraries, common = edition(tmp_path / 'build')
    context = archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    with pytest.raises(package.Invalid, match='previous edition dependency qualification failed'):
        linkcheck.check(programs[1], programs[0], archive_context=context,
                       siblings=[libraries[1], common], previous_siblings=[libraries[1], common])


@pytest.mark.parametrize('fault', ['missing', 'wrong-bytes', 'missing-index', 'missing-release', 'wrong-index'])
def test_known_predecessor_cannot_disappear_silently(publisher_env, tmp_path, fault):
    programs, libraries, common = edition(tmp_path / 'build')
    old_out, new_out = tmp_path / 'old', tmp_path / 'new'
    for i, raw in enumerate((programs[0], libraries[0], common)):
        qualify_payload(raw, old_out, tmp_path / f'stage-old-{i}')
    for i, raw in enumerate((programs[1], libraries[1])):
        qualify_payload(raw, new_out, tmp_path / f'stage-new-{i}')
    shutil.copyfile(old_out / common.name, new_out / common.name)
    destination = tmp_path / 'published-fixture'
    first = publish_fixture(old_out, destination, publisher_env)
    assert first.returncode == 0, first.stdout + first.stderr
    old_consumer = next(destination.glob('pool/**/edition-consumer_1_amd64.deb'))
    if fault == 'missing':
        old_consumer.unlink()
        diagnostic = 'previous edition archive missing'
    elif fault == 'wrong-bytes':
        old_consumer.write_bytes(old_consumer.read_bytes() + b'changed')
        diagnostic = 'previous edition archive differs from its index'
    elif fault == 'missing-index':
        (destination / 'dists/mashtabba/main/binary-amd64/Packages').unlink()
        diagnostic = 'previous edition index missing'
    elif fault == 'missing-release':
        (destination / 'dists/mashtabba/Release').unlink()
        diagnostic = 'previous edition Release missing'
    else:
        (destination / 'dists/mashtabba/main/binary-amd64/Packages').write_bytes(b'')
        diagnostic = 'previous edition index differs from its Release'
    before = tree_hashes(destination)
    failure = publish_fixture(new_out, destination, publisher_env)
    assert failure.returncode != 0 and diagnostic in failure.stderr, failure.stdout + failure.stderr
    assert tree_hashes(destination) == before


def test_public_key_copy_obeys_space_guard(sources, tmp_path):
    size = Path(json.loads(sources.read_text())[0]['keyring']).stat().st_size
    original = archive.Archive.ensure_space
    def refuse_key_copy(self, required=0):
        if required == size + 16384:
            raise package.Invalid('controlled public-key space refusal')
        return original(self, required)
    with patch.object(archive.Archive, 'ensure_space', refuse_key_copy):
        with pytest.raises(package.Invalid, match='public-key space refusal'):
            archive.Archive(sources, tmp_path / 'scratch', 'amd64')
    assert not list((tmp_path / 'scratch').glob('link-*/etc/key-*.gpg'))
