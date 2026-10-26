"""Archive solver and execution negatives, using real APT and real ELF files."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from unittest.mock import patch

import pytest

from lean import archive, linkcheck, package, release
from lean.tests.archive_fixtures import deb, signed_archive


@pytest.fixture(scope='module')
def repository(tmp_path_factory):
    base = tmp_path_factory.mktemp('signed-archive')
    config = signed_archive(base)
    return config


@pytest.fixture
def context(repository, tmp_path):
    return archive.Archive(repository, tmp_path / 'scratch', 'amd64')


def manifest(qualified):
    return json.loads((qualified.directory / 'resolution.json').read_text())


@pytest.mark.parametrize('depends,expected', [
    ('absent-first | chosen (>= 2:1.0-3)', 'chosen'),
    ('chosen (>= 3:0) | leaf', 'leaf'),
    ('chosen (= 2:1.0-3)', 'chosen'),
    ('chosen (>> 1:999-99)', 'chosen'),
    ('chosen (<< 2:1.0-4)', 'chosen'),
    ('virtual-abi (>= 7)', 'chosen'),
    ('chosen:any', 'chosen'),
    ('chosen:native', 'chosen'),
    ('chosen:amd64', 'chosen'),
    ('leaf', 'leaf'),
    ('foreign-helper', 'foreign-helper'),
])
def test_debian_dependency_choices(context, tmp_path, depends, expected):
    candidate = deb(tmp_path, 'consumer', depends=depends)
    q = context.qualify(candidate)
    rows = manifest(q)['packages']
    assert expected in [row['identity'][0] for row in rows]
    assert (context.base / 'state/status').read_bytes() == b''
    if expected == 'chosen':
        assert next(row['identity'][1] for row in rows if row['identity'][0] == 'chosen') == '2:1.0-3'
        assert 'leaf' in [row['identity'][0] for row in rows]


@pytest.mark.parametrize('depends', [
    'chosen (>= 2:1.0-4)',
    'chosen (>> 3:0)',
    'missing-first | chosen (<< 1:999-99)',
    'missing-first | missing-second',
    'unversioned-abi (>= 1)',
    'virtual-abi (>= 8)',
    'wrong-only',
    'chosen, collision',
])
def test_unsatisfied_dependencies_block(context, tmp_path, depends):
    candidate = deb(tmp_path, 'consumer', depends=depends)
    with pytest.raises(package.Invalid, match='archive .*solve failed'):
        context.qualify(candidate)


def test_pre_depends_and_architecture_all(context, tmp_path):
    candidate = deb(tmp_path, 'consumer', arch='all', extra='Pre-Depends: virtual-abi (= 7)\n')
    q = context.qualify(candidate)
    assert q.arch == 'amd64'
    assert {'chosen', 'leaf'} <= {r['identity'][0] for r in manifest(q)['packages']}
    assert manifest(q)['inputs'][0]['pre_depends'] == 'virtual-abi (= 7)'


def test_wrong_supplied_architecture(context, tmp_path):
    candidate = deb(tmp_path, 'consumer', arch='arm64')
    with pytest.raises(package.Invalid, match='wrong architecture arm64; context is amd64'):
        context.qualify(candidate)


def test_foreign_execution_is_explicit(context, tmp_path):
    candidate = deb(tmp_path, 'consumer', arch='arm64')
    with pytest.raises(package.Invalid, match='unsupported execution gate for arm64'):
        release.check_link([candidate], archive_config=context.base / "unused.json", scratch=tmp_path)
    q = archive.Qualified(tmp_path, {}, tmp_path, 'arm64')
    with pytest.raises(archive.ExecutionUnavailable, match='native runner required'):
        q.run(['/usr/bin/anything'])


def test_supplied_candidate_and_sibling_remain_authoritative(context, tmp_path):
    local = deb(tmp_path, 'chosen', '1', files={'usr/lib/edition-identity': b'local edition'})
    consumer = deb(tmp_path, 'consumer', depends='chosen (= 1)')
    q = context.qualify(consumer, [local])
    assert (q.root / 'usr/lib/edition-identity').read_bytes() == b'local edition'
    assert 'chosen' not in [r['identity'][0] for r in manifest(q)['packages']]
    incompatible = deb(tmp_path, 'incompatible', depends='chosen (>= 2:1.0-3)')
    with pytest.raises(package.Invalid, match='solve failed'):
        context.qualify(incompatible, [local])


def test_conflicting_supplied_identity(context, tmp_path):
    candidate = deb(tmp_path, 'consumer')
    first = deb(tmp_path, 'sibling', '1')
    second = deb(tmp_path, 'sibling', '2')
    with pytest.raises(package.Invalid, match='conflicting supplied package: sibling'):
        context.qualify(candidate, [first, second])


def test_corrupt_archive_bytes_are_rejected(context, tmp_path):
    candidate = deb(tmp_path, 'consumer', depends='leaf')
    repo = Path(context.sources[0]['uri'][7:])
    source = next((repo / 'pool').glob('leaf_*.deb'))
    original = source.read_bytes()
    try:
        source.write_bytes(original[:-1] + bytes([original[-1] ^ 1]))
        with pytest.raises(package.Invalid, match='corrupt download'):
            context.qualify(candidate)
    finally:
        source.write_bytes(original)


def test_corrupt_cached_bytes_are_rejected(context, tmp_path):
    candidate = deb(tmp_path, 'consumer', depends='leaf')
    q = context.qualify(candidate)
    row = manifest(q)['packages'][0]
    cached = context.cache / (row['sha256'] + '.deb')
    cached.write_bytes(b'corrupt')
    with pytest.raises(package.Invalid, match='corrupt cached package'):
        context.qualify(candidate)


def compile_program(base, text, args=()):
    source = base / 'main.c'
    source.write_text(text)
    binary = base / 'probe'
    subprocess.run(['cc', str(source), '-o', str(binary)] + list(args), check=True)
    return binary


def test_host_present_library_and_rpath_cannot_satisfy(context, tmp_path, monkeypatch):
    binary = compile_program(tmp_path, '#include <math.h>\nvolatile double input=0.3;\n'
                             'int main(void) { return sin(input) > 2; }\n', ['-lm',
                             '-Wl,-rpath,/usr/lib/x86_64-linux-gnu'])
    # libc is present in the fixture archive, libm is deliberately not declared.
    assert 'libm.so.6' in linkcheck.needed(binary)
    host = subprocess.run(['ldd', '-r', str(binary)], capture_output=True, text=True, check=True)
    assert 'libm.so.6 =>' in host.stdout and 'not found' not in host.stdout
    monkeypatch.setenv('LD_LIBRARY_PATH', '/usr/lib/x86_64-linux-gnu')
    candidate = deb(tmp_path, 'consumer', depends='libc6', files={
        'usr/bin/probe': binary, 'etc/ld.so.cache': Path('/etc/ld.so.cache')})
    with pytest.raises(package.Invalid, match='libm.so.6'):
        linkcheck.check(candidate, archive_context=context)


def test_undeclared_loader_cannot_fall_back_to_host(context, tmp_path):
    binary = compile_program(tmp_path, 'int main(void) { return 0; }\n')
    candidate = deb(tmp_path, 'consumer', files={'usr/bin/probe': binary})
    with pytest.raises(package.Invalid, match='qualified interpreter missing'):
        linkcheck.check(candidate, archive_context=context)


def test_unusable_elf_is_blocked(context, tmp_path):
    candidate = deb(tmp_path, 'consumer', files={'usr/bin/broken': b'\x7fELF' + b'\0' * 8})
    with pytest.raises(package.Invalid, match='unusable ELF'):
        linkcheck.check(candidate, archive_context=context)


def test_library_only_program_symbols_remain_notes(context, tmp_path):
    binary = compile_program(tmp_path, 'int supplied_by_program(void);\n'
                             'int plugin(void) { return supplied_by_program(); }\n', ['-shared', '-fPIC'])
    candidate = deb(tmp_path, 'consumer', depends='libc6', files={'usr/lib/libplugin.so': binary})
    notes = linkcheck.check(candidate, archive_context=context)
    assert any('symbols left to its program' in note for note in notes)


def test_execution_environment_and_evidence(context, tmp_path, monkeypatch):
    binary = compile_program(tmp_path, '#include <stdlib.h>\n#include <stdio.h>\n'
        'int main(void) { const char *keys[]={"DISPLAY","WAYLAND_DISPLAY","XAUTHORITY",'
        '"DBUS_SESSION_BUS_ADDRESS","LD_LIBRARY_PATH","LD_PRELOAD"}; '
        'for(unsigned i=0;i<6;i++) if(getenv(keys[i])) return 9; puts("clean"); return 0; }\n')
    candidate = deb(tmp_path, 'consumer', depends='libc6', files={'usr/bin/probe': binary})
    q = context.qualify(candidate)
    monkeypatch.setenv('DISPLAY', ':999')
    monkeypatch.setenv('DBUS_SESSION_BUS_ADDRESS', 'unix:path=/not-allowed')
    monkeypatch.setenv('LD_LIBRARY_PATH', '/usr/lib')
    run = q.run(['/usr/bin/probe'])
    assert (run.returncode, run.stdout) == (0, 'clean\n')
    records = [json.loads(line) for line in (q.directory / 'execution.jsonl').read_text().splitlines()]
    binds = records[0]['argv']
    assert binds[binds.index('--ro-bind') + 1:binds.index('--ro-bind') + 3] == [str(q.root), '/']
    assert '--unshare-all' in binds and '--clearenv' in binds


def test_runner_failure_cannot_be_hidden_by_predecessor(context, tmp_path):
    binary = compile_program(tmp_path, 'int main(void) { return 0; }\n')
    candidate = deb(tmp_path, 'consumer', depends='libc6', files={'usr/bin/probe': binary})
    with patch.object(archive.Qualified, 'run', side_effect=archive.ExecutionUnavailable('namespace unavailable')):
        with pytest.raises(archive.ExecutionUnavailable, match='namespace unavailable'):
            linkcheck.check(candidate, candidate, archive_context=context)


def test_configuration_excludes_host_state_hooks_and_credentials(context):
    dump = (context.base / 'configuration.log').read_text()
    assert str(context.base / 'state/status') in dump
    assert '/var/lib/dpkg/status' not in dump and '/etc/apt' not in dump
    assert 'Post-Invoke' not in dump and 'Pre-Install-Pkgs' not in dump
    assert 'netrc "auth.conf"' in dump
    assert context.env['APT_CONFIG'] == str(context.base / 'apt.conf')
    assert set(context.env) == {'PATH', 'LC_ALL', 'LANGUAGE', 'DEBIAN_FRONTEND', 'HOME', 'APT_CONFIG'}
    metadata = json.loads((context.base / 'metadata.json').read_text())
    assert metadata['keys'] and any(m['path'].endswith('InRelease') for m in metadata['metadata'])


def test_missing_configuration_never_reverts_to_host(tmp_path, monkeypatch):
    monkeypatch.delenv('SPARKY_LC_ARCHIVE_CONFIG', raising=False)
    monkeypatch.delenv('SPARKY_LC_SCRATCH', raising=False)
    with pytest.raises(package.Invalid, match='check-link needs --archive-config'):
        release.check_link([])


def test_rooted_extraction_rejects_host_escape(tmp_path):
    root = tmp_path / 'root'
    root.mkdir()
    (root / 'absolute').symlink_to('/usr/lib')
    assert archive.rooted(root, '/absolute/libfoo.so') == root / 'usr/lib/libfoo.so'
    (root / 'escape').symlink_to('../../outside')
    with pytest.raises(package.Invalid, match='escapes root'):
        archive.rooted(root, '/escape/library')


def test_wrong_downloaded_architecture(context, tmp_path):
    candidate = deb(tmp_path, 'consumer', depends='wrong-only:arm64')
    with pytest.raises(package.Invalid, match='wrong architecture arm64; context is amd64'):
        context.qualify(candidate)


def test_unrelated_siblings_do_not_force_dependencies_or_payload(context, tmp_path):
    candidate = deb(tmp_path, 'consumer')
    sibling = deb(tmp_path, 'unrelated', depends='unavailable', files={'usr/lib/unrelated': b'unrelated'})
    q = context.qualify(candidate, [sibling])
    assert not (q.root / 'usr/lib/unrelated').exists()
    assert not next(row['selected'] for row in manifest(q)['inputs'] if row['identity'][0] == 'unrelated')


def test_wrong_downloaded_identity(tmp_path):
    config = signed_archive(tmp_path / 'repository', transform=lambda text: text.replace('Package: leaf\n', 'Package: advertised-leaf\n'))
    context = archive.Archive(config, tmp_path / 'scratch', 'amd64')
    candidate = deb(tmp_path, 'consumer', depends='advertised-leaf')
    with pytest.raises(package.Invalid, match='identity .*signed index'):
        context.qualify(candidate)


def test_signed_control_relationship_mismatch(tmp_path):
    config = signed_archive(tmp_path / 'repository', transform=lambda text: text.replace('Depends: leaf\n', 'Depends: libc6\n'))
    context = archive.Archive(config, tmp_path / 'scratch', 'amd64')
    candidate = deb(tmp_path, 'consumer', depends='chosen')
    with pytest.raises(package.Invalid, match='identity differs from signed index'):
        context.qualify(candidate)


def test_invalid_signed_metadata_is_rejected(tmp_path):
    config = signed_archive(tmp_path / 'repository')
    signed = tmp_path / 'repository/repo/dists/fixture/InRelease'
    signed.write_bytes(signed.read_bytes().replace(b'Origin: Link gate fixture', b'Origin: Forged repository'))
    with pytest.raises(package.Invalid, match='archive update failed'):
        archive.Archive(config, tmp_path / 'scratch', 'amd64')


def test_valid_signature_cannot_cover_changed_index(tmp_path):
    config = signed_archive(tmp_path / 'repository')
    index = tmp_path / 'repository/repo/dists/fixture/main/binary-amd64/Packages'
    index.write_bytes(index.read_bytes().replace(b'Package: leaf', b'Package: fake'))
    with pytest.raises(package.Invalid, match='archive update failed'):
        archive.Archive(config, tmp_path / 'scratch', 'amd64')


def test_previous_versions_use_debian_epoch_and_revision(tmp_path):
    previous = tmp_path / 'previous'
    previous.mkdir()
    newest = deb(previous, 'consumer', '2:1.0-3')
    deb(previous, 'consumer', '2:1.0-2')
    deb(previous, 'consumer', '1:999-99')
    deb(previous, 'consumer', '3:0')
    candidate = deb(tmp_path, 'consumer', '2:1.0-4')
    assert release.previous_build(candidate, previous) == newest


def test_publication_gate_is_before_copy_and_sign_and_preserves_byte_checks():
    source = (Path(__file__).resolve().parents[2] / 'repo/publish-tree.sh').read_text()
    assert source.index('lean.release check-selection') < source.index('lean.release check-link')
    assert source.index('lean.release check-link') < source.index('# 2. Pool: copy') < source.index('# 4. Release, signed')
    assert source.index('published archive is immutable:') < source.index('# 2. Pool: copy')
    assert '--siblings-file "$W/link-siblings.txt"' in source
    assert 'unsupported execution gate for $arch' in source


def test_check_link_cli_accepts_scratch_archive_and_sibling_inputs(repository, tmp_path):
    consumer = deb(tmp_path, 'consumer', depends='edition-library (= 3)')
    sibling = deb(tmp_path, 'edition-library', '3')
    paths = tmp_path / 'siblings.txt'
    paths.write_text(str(sibling) + '\n')
    run = subprocess.run(['python3', '-m', 'lean.release', 'check-link', '--archive-config', str(repository),
        '--scratch', str(tmp_path / 'scratch'), '--siblings-file', str(paths), str(consumer)],
        env={**os.environ, 'PYTHONPATH': str(Path(__file__).resolve().parents[2])}, capture_output=True, text=True)
    assert run.returncode == 0, run.stdout + run.stderr
    records = list((tmp_path / 'scratch').glob('link-*/case-*/resolution.json'))
    assert records and any(row['identity'][0] == 'edition-library' and row['selected']
                           for row in json.loads(records[0].read_text())['inputs'])


def test_same_version_stock_package_cannot_replace_edition_input(context, tmp_path):
    local = deb(tmp_path, 'chosen', '2:1.0-3', files={'usr/lib/edition-identity': b'edition bytes'})
    consumer = deb(tmp_path, 'consumer', depends='chosen (= 2:1.0-3)')
    q = context.qualify(consumer, [local])
    assert (q.root / 'usr/lib/edition-identity').read_bytes() == b'edition bytes'
    assert 'chosen' not in [row['identity'][0] for row in manifest(q)['packages']]


def test_invalid_predecessor_cannot_mask_candidate_failure(context, tmp_path):
    binary = compile_program(tmp_path, 'int main(void) { return 0; }\n')
    candidate = deb(tmp_path, 'consumer', files={'usr/bin/probe': binary})
    with pytest.raises(package.Invalid, match='predecessor failed archive-qualified resolution'):
        linkcheck.check(candidate, candidate, archive_context=context)


def test_inherited_apt_configuration_cannot_add_hooks(repository, tmp_path, monkeypatch):
    marker = tmp_path / 'hook-ran'
    poison = tmp_path / 'inherited-apt.conf'
    poison.write_text('Dir::State::status "/var/lib/dpkg/status";\n'
                      f'APT::Update::Post-Invoke {{ "touch {marker}"; }};\n')
    monkeypatch.setenv('APT_CONFIG', str(poison))
    context = archive.Archive(repository, tmp_path / 'scratch', 'amd64')
    assert not marker.exists()
    assert 'Post-Invoke' not in (context.base / 'configuration.log').read_text()
    assert (context.base / 'state/status').read_bytes() == b''


def test_lost_unneeded_library_remains_informational(context, tmp_path):
    source = tmp_path / 'unused.c'
    source.write_text('int unused(void) { return 3; }\n')
    library = tmp_path / 'libunused.so.1'
    subprocess.run(['cc', '-shared', '-fPIC', str(source), '-o', str(library),
                    '-Wl,-soname,libunused.so.1'], check=True)
    source.write_text('int main(void) { return 0; }\n')
    before_binary = tmp_path / 'before'
    after_binary = tmp_path / 'after'
    for binary, flag in ((before_binary, '--no-as-needed'), (after_binary, '--as-needed')):
        subprocess.run(['cc', str(source), '-o', str(binary), f'-Wl,{flag}', str(library)], check=True)
    before = deb(tmp_path, 'consumer', '1', depends='libc6', files={
        'usr/bin/probe': before_binary, 'usr/lib/libunused.so.1': library})
    after = deb(tmp_path, 'consumer', '2', depends='libc6', files={
        'usr/bin/probe': after_binary, 'usr/lib/libunused.so.1': library})
    assert 'libunused.so.1' in linkcheck.needed(before_binary)
    assert 'libunused.so.1' not in linkcheck.needed(after_binary)
    notes = linkcheck.check(after, before, archive_context=context)
    assert any('NEEDED no longer lists libunused.so.1' in note for note in notes)
