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
    cached.chmod(0o644)
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


def recorded_shows(monkeypatch, rewrite=None):
    """Every apt-cache show call the gate makes, optionally with its records rewritten."""
    calls = []
    original = archive.Archive.run

    def run(self, args, label, **options):
        out = original(self, args, label, **options)
        if args[:2] == ['apt-cache', 'show']:
            calls.append(args[2:])
            if rewrite:
                out = '\n\n'.join(rewrite(record) for record in out.split('\n\n'))
        return out

    monkeypatch.setattr(archive.Archive, 'run', run)
    return calls


def test_one_signed_index_call_per_case_and_reuse_across_cases(context, tmp_path, monkeypatch):
    calls = recorded_shows(monkeypatch)
    # two candidates of one edition snapshot share one local index, as in a publication
    first = deb(tmp_path, 'consumer', depends='chosen, libxrandr2, foreign-helper')
    second = deb(tmp_path, 'other-consumer', depends='chosen, libxrandr2')
    q = context.qualify(first, [second])
    assert len(calls) == 1
    assert sorted(calls[0]) == ['chosen:amd64=2:1.0-3', 'foreign-helper:amd64=1', 'leaf:all=1', 'libxrandr2:amd64=1']
    rows = json.loads((q.directory / 'signed-index.json').read_text())
    assert [tuple(row['identity']) for row in rows] == [tuple(r['identity']) for r in manifest(q)['packages']]
    assert {row['record'] for row in rows} == {q.directory.name + '-signed-index-1.log'}
    q.close()
    # the same local index: every record is reused, APT is not asked again
    q = context.qualify(second, [first])
    assert len(calls) == 1
    reused = json.loads((q.directory / 'signed-index.json').read_text())
    assert {row['record'] for row in reused} == {row['record'] for row in rows}
    assert len(manifest(q)['packages']) == 3
    q.close()
    # another local index digest: asked again
    q = context.qualify(first, [second, deb(tmp_path, 'unrelated')])
    assert len(calls) == 2
    q.close()


def test_batches_are_bounded(monkeypatch):
    monkeypatch.setattr(archive, 'SHOW_ARGUMENTS', 3)
    names = [(f'p{i}', '1', 'amd64') for i in range(7)]
    assert [len(b) for b in archive.show_batches(names)] == [3, 3, 1]
    monkeypatch.setattr(archive, 'SHOW_ARGUMENTS', 1024)
    monkeypatch.setattr(archive, 'SHOW_BYTES', 30)
    assert [b for b in archive.show_batches(names)] == [['p0:amd64=1', 'p1:amd64=1'], ['p2:amd64=1', 'p3:amd64=1'],
                                                        ['p4:amd64=1', 'p5:amd64=1'], ['p6:amd64=1']]


@pytest.mark.parametrize('field,value', [('SHA256', '0' * 64), ('Size', '1'), ('Depends', 'libc6')])
def test_record_differing_from_download_is_refused(context, tmp_path, monkeypatch, field, value):
    def rewrite(record):
        if 'Package: chosen\n' not in record + '\n':
            return record
        lines = [line for line in record.split('\n') if not line.startswith(field + ':')]
        return '\n'.join(lines + [f'{field}: {value}'])

    recorded_shows(monkeypatch, rewrite)
    candidate = deb(tmp_path, 'consumer', depends='libxrandr2, chosen, foreign-helper')
    with pytest.raises(package.Invalid, match=r"chosen_1.0-3_amd64.deb: downloaded package identity differs from signed index"):
        context.qualify(candidate)


def test_absent_identity_in_a_mixed_batch_is_named(tmp_path, monkeypatch):
    config = signed_archive(tmp_path / 'repository', transform=lambda text: text.replace('Package: leaf\n', 'Package: advertised-leaf\n'))
    context = archive.Archive(config, tmp_path / 'scratch', 'amd64')
    calls = recorded_shows(monkeypatch)
    candidate = deb(tmp_path, 'consumer', depends='libxrandr2, advertised-leaf, foreign-helper')
    with pytest.raises(package.Invalid, match=r"leaf_1_all.deb: downloaded identity \('leaf', '1', 'all'\) is absent from signed index"):
        context.qualify(candidate)
    assert len(calls) == 1 and 'leaf:all=1' in calls[0] and len(calls[0]) == 3


@pytest.mark.parametrize('name,status', [('libxrandr2', 'E: No packages found\n'), ('leaf', '')])
def test_only_absent_identities_are_named(tmp_path, name, status):
    # a name APT has never seen: exit 100, "No packages found"; a name another package
    # depends on (chosen: Depends: leaf) but with no record: exit 0, no output
    config = signed_archive(tmp_path / 'repository', transform=lambda text: text.replace(f'Package: {name}\n', 'Package: advertised\n'))
    context = archive.Archive(config, tmp_path / 'scratch', 'amd64')
    candidate = deb(tmp_path, 'consumer', depends='advertised')
    arch = 'all' if name == 'leaf' else 'amd64'
    with pytest.raises(package.Invalid, match=rf"downloaded identity \('{name}', '1', '{arch}'\) is absent from signed index"):
        context.qualify(candidate)
    log = next(context.base.glob('case-*-signed-index-1.log')).read_text()
    assert log == f'$ apt-cache show {name}:{arch}=1\n' + status


def test_regular_expression_fallback_cannot_answer_for_an_absent_name(tmp_path, monkeypatch):
    # apt-cache retries an absent name containing '.' as an unanchored regular expression:
    # "pick.d" prints the record of "picked"; that record must not answer for "pick.d"
    work = tmp_path / 'extra'
    work.mkdir()
    extra = [deb(work, 'pick.d')]
    config = signed_archive(tmp_path / 'repository', additional=extra,
                            transform=lambda text: text.replace('Package: pick.d\n', 'Package: picked\n'))
    context = archive.Archive(config, tmp_path / 'scratch', 'amd64')
    calls = recorded_shows(monkeypatch)
    candidate = deb(tmp_path, 'consumer', depends='chosen, picked')
    with pytest.raises(package.Invalid, match=r"downloaded identity \('pick.d', '1', 'amd64'\) is absent from signed index"):
        context.qualify(candidate)
    assert len(calls) == 1 and 'pick.d:amd64=1' in calls[0]
    log = next(context.base.glob('case-*-signed-index-1.log')).read_text()
    assert 'Package: picked\n' in log


def test_apt_failure_other_than_nothing_found_is_not_taken_for_absence(context):
    with pytest.raises(package.Invalid, match='archive refused-probe failed'):
        context.run(['sh', '-c', 'echo "E: The package lists or status file could not be parsed" >&2; exit 100'],
                    'refused-probe', nothing_found=True)
    with pytest.raises(package.Invalid, match='archive output-probe failed'):
        context.run(['sh', '-c', 'echo "Package: x"; echo "E: No packages found" >&2; exit 100'],
                    'output-probe', nothing_found=True)
    assert context.run(['sh', '-c', 'echo "E: No packages found" >&2; exit 100'], 'empty-probe', nothing_found=True) == ''
    with pytest.raises(package.Invalid, match='archive plain-probe failed'):
        context.run(['sh', '-c', 'echo "E: No packages found" >&2; exit 100'], 'plain-probe')


def test_earlier_identity_refusal_precedes_a_later_solver_line_failure(tmp_path, monkeypatch):
    # one by one, the gate refused the first download in solver order; batched, a later
    # line's failure waits until the downloads before it are checked
    config = signed_archive(tmp_path / 'repository', transform=lambda text: text.replace('Package: leaf\n', 'Package: advertised-leaf\n'))
    context = archive.Archive(config, tmp_path / 'scratch', 'amd64')
    original = archive.Archive.run

    def run(self, args, label, **options):
        out = original(self, args, label, **options)
        if label.endswith('-solve'):
            lines = out.splitlines()
            last = max(i for i, line in enumerate(lines) if line.startswith("'"))
            lines.insert(last + 1, "'https://example.invalid/unverified.deb' unverified.deb 1 MD5Sum:0")
            out = '\n'.join(lines) + '\n'
        return out

    monkeypatch.setattr(archive.Archive, 'run', run)
    candidate = deb(tmp_path, 'consumer', depends='advertised-leaf')
    with pytest.raises(package.Invalid, match=r"\('leaf', '1', 'all'\) is absent from signed index"):
        context.qualify(candidate)
    good = deb(tmp_path / 'good', 'consumer', depends='libxrandr2')
    with pytest.raises(package.Invalid, match='archive solver returned an unverified download'):
        context.qualify(good)


def test_flat_source_and_source_architectures(tmp_path):
    # NVIDIA publishes its CUDA repository flat: sources.list(5) says a suite ending in "/"
    # is an exact path, with the components omitted
    config = signed_archive(tmp_path / 'flat', flat=True)
    flat = json.loads(config.read_text())[0]
    context = archive.Archive(config, tmp_path / 'scratch', 'amd64')
    assert context.public_sources.endswith(flat['uri'].rstrip('/') + '/ /\n')
    q = context.qualify(deb(tmp_path, 'consumer', depends='chosen (= 2:1.0-3)'))
    assert ('chosen', '2:1.0-3', 'amd64') in [tuple(r['identity']) for r in manifest(q)['packages']]
    q.close()
    # a source for other architectures is left out of this context, like sources.list's Architectures
    both = tmp_path / 'both.json'
    both.write_text(json.dumps([flat, dict(flat, architectures=['arm64', 'i386'])]))
    context = archive.Archive(both, tmp_path / 'scratch-both', 'amd64')
    assert context.skipped_sources == [1] and context.public_sources.count('deb ') == 1
    assert json.loads((context.base / 'metadata.json').read_text())['skipped_sources'] == [1]
    for sources, message in (([dict(flat, architectures=['arm64'])], 'no source for amd64'),
                             ([dict(flat, architectures=[])], 'invalid archive architectures'),
                             ([dict(flat, components=['main'])], 'invalid archive suite or components'),
                             ([dict(flat, suite='fixture')], 'invalid archive suite or components'),
                             ([{k: v for k, v in flat.items() if k != 'components'}], None)):
        bad = tmp_path / 'bad.json'
        bad.write_text(json.dumps(sources))
        if message is None:
            archive.Archive(bad, tmp_path / 'scratch-omitted', 'amd64')
        else:
            with pytest.raises(package.Invalid, match=message):
                archive.Archive(bad, tmp_path / 'scratch-bad', 'amd64')


LOCK_TEXT = b'Package: firmware\nPin: version 1\nPin-Priority: 1005\n\nPackage: firmware\nPin: version *\nPin-Priority: 100\n'


def policy_package(base, name='fixture-lock', file='10fixture-lock', text=LOCK_TEXT, version='1'):
    return deb(base, name, version, arch='all', files={
        f'/etc/apt/preferences.d/{file}': text, 'DEBIAN/conffiles': f'/etc/apt/preferences.d/{file}\n'.encode()})


@pytest.fixture(scope='module')
def two_firmwares(tmp_path_factory):
    base = tmp_path_factory.mktemp('two-firmwares')
    extra = base / 'extra'
    extra.mkdir()
    return signed_archive(base, additional=[deb(extra, 'firmware', '1', arch='all'), deb(extra, 'firmware', '2', arch='all')])


def test_exact_dependency_on_an_older_version_resolves_with_the_supplied_lock(two_firmwares, tmp_path):
    # The NVIDIA trap in miniature: the archive's newer firmware is APT's candidate, and APT's solver
    # never takes a non-candidate version for an exact dependency (apt 2.9.17, "Reject all
    # non-candidates outright for strict pinning"); the edition's lock, installed first on every
    # edition system, makes the locked version the candidate.
    context = archive.Archive(two_firmwares, tmp_path / 'scratch', 'amd64')
    module = deb(tmp_path, 'module', depends='firmware (= 1)')
    with pytest.raises(package.Invalid, match='solve failed'):
        context.qualify(module, [deb(tmp_path, 'unrelated')])
    lock = policy_package(tmp_path)
    q = context.qualify(module, [lock])
    assert ('firmware', '1', 'all') in [tuple(r['identity']) for r in manifest(q)['packages']]
    applied = [{'path': '/etc/apt/preferences.d/10fixture-lock', 'package': ['fixture-lock', '1', 'all'],
                'sha256': hashlib.sha256(LOCK_TEXT).hexdigest()}]
    assert manifest(q)['preferences'] == applied
    assert json.loads((q.directory / 'preferences.json').read_text()) == applied
    assert (context.base / 'etc/preferences.d/10fixture-lock').read_bytes() == LOCK_TEXT
    q.close()
    # a later universe without the lock has no preferences file
    with pytest.raises(package.Invalid, match='solve failed'):
        context.qualify(module, [deb(tmp_path / 'again', 'unrelated')])
    assert not any((context.base / 'etc/preferences.d').iterdir())


def test_supplied_policy_cannot_replace_an_exact_edition_input(context, tmp_path):
    # the gate's own pins come first (/etc/apt/preferences, then preferences.d), and the first specific
    # record that matches a version decides its priority (apt_preferences(5))
    local = deb(tmp_path, 'chosen', '1', files={'usr/lib/edition-identity': b'local edition'})
    policy = policy_package(tmp_path, text=b'Package: chosen\nPin: version 2:1.0-3\nPin-Priority: 1005\n')
    consumer = deb(tmp_path, 'consumer', depends='chosen')
    q = context.qualify(consumer, [local, policy])
    assert (q.root / 'usr/lib/edition-identity').read_bytes() == b'local edition'
    assert 'chosen' not in [r['identity'][0] for r in manifest(q)['packages']]
    q.close()


def test_two_supplied_packages_cannot_ship_one_preferences_file(context, tmp_path):
    first = policy_package(tmp_path, name='first-policy')
    second = policy_package(tmp_path, name='second-policy')
    with pytest.raises(package.Invalid, match='two supplied packages ship /etc/apt/preferences.d/10fixture-lock'):
        context.qualify(deb(tmp_path, 'consumer'), [first, second])


def test_preferences_are_the_files_the_control_members_name(tmp_path):
    shipped = deb(tmp_path, 'policy', arch='all', files={
        'etc/apt/preferences.d/a': b'x', 'etc/apt/preferences.d/b': b'y', 'etc/apt/preferences.d/sub/c': b'z',
        'etc/apt/other': b'w', 'DEBIAN/conffiles': b'/etc/apt/preferences.d/a\n/etc/apt/other\n',
        'DEBIAN/md5sums': (hashlib.md5(b'y').hexdigest() + '  etc/apt/preferences.d/b\n' +
                           hashlib.md5(b'z').hexdigest() + '  etc/apt/preferences.d/sub/c\n').encode()})
    assert archive.preference_names(archive.shipped_paths(shipped)) == ['a', 'b']
    # without md5sums, the data says what the package ships
    bare = deb(tmp_path, 'bare', arch='all', files={'etc/apt/preferences.d/d': b'v'})
    assert archive.preference_names(archive.shipped_paths(bare)) == ['d']
    assert archive.preference_names(archive.shipped_paths(deb(tmp_path, 'plain'))) == []


def test_a_pin_shipped_without_being_declared_a_conffile_applies(two_firmwares, tmp_path):
    # sparky-stereo-apt before 20261031.1 shipped its pins without declaring them conffiles; APT reads them anyway
    context = archive.Archive(two_firmwares, tmp_path / 'scratch', 'amd64')
    lock = deb(tmp_path, 'fixture-lock', arch='all', files={
        'etc/apt/preferences.d/10fixture-lock': LOCK_TEXT,
        'DEBIAN/md5sums': (hashlib.md5(LOCK_TEXT).hexdigest() + '  etc/apt/preferences.d/10fixture-lock\n').encode()})
    q = context.qualify(deb(tmp_path, 'module', depends='firmware (= 1)'), [lock])
    assert ('firmware', '1', 'all') in [tuple(r['identity']) for r in manifest(q)['packages']]
    q.close()


def test_conflicting_driver_locks_follow_the_cases_install_set(two_firmwares, tmp_path):
    context = archive.Archive(two_firmwares, tmp_path / 'scratch', 'amd64')
    main = deb(tmp_path, 'main-lock', arch='all', extra='Conflicts: legacy-lock\n', files={
        'etc/apt/preferences.d/10main-lock': LOCK_TEXT})
    legacy_text = LOCK_TEXT.replace(b'version 1', b'version 2')
    legacy = deb(tmp_path, 'legacy-lock', arch='all', extra='Conflicts: main-lock\n', files={
        'etc/apt/preferences.d/09legacy-lock': legacy_text})
    module = deb(tmp_path, 'main-module', depends='main-lock, firmware (= 1)')
    older = deb(tmp_path, 'legacy-module', depends='legacy-lock, firmware (= 2)')
    global_policy = policy_package(tmp_path, name='global-policy', file='99global',
                                   text=b'Package: leaf\nPin: version *\nPin-Priority: 700\n')
    siblings = [main, legacy, module, older, global_policy]
    for candidate, owner, firmware in ((module, 'main-lock', '1'), (older, 'legacy-lock', '2'),
                                       (module, 'main-lock', '1')):
        q = context.qualify(candidate, siblings)
        rows = manifest(q)
        assert {p['package'][0] for p in rows['preferences']} == {owner, 'global-policy'}
        assert ('firmware', firmware, 'all') in [tuple(r['identity']) for r in rows['packages']]
        assert {r['identity'][0] for r in rows['inputs'] if r['selected']} == {owner, archive.control(candidate)['Package']}
        assert len(list((context.base / 'etc/preferences.d').iterdir())) == 2
        q.close()
    # An unrelated case must not acquire a driver lock just to use its pins.
    q = context.qualify(deb(tmp_path, 'unrelated-case'), siblings)
    assert {p['package'][0] for p in manifest(q)['preferences']} == {'global-policy'}
    q.close()
    # A genuinely impossible co-installation must still fail.
    with pytest.raises(package.Invalid, match='solve failed'):
        context.qualify(deb(tmp_path, 'both-stacks', depends='main-lock, legacy-lock'), siblings)


@pytest.mark.parametrize('conflict,provides,expected', [
    ('module', '', True),
    ('module (<< 2)', '', True),
    ('module (<< 1)', '', False),
    ('module:amd64 (>= 1)', '', True),
    ('module:arm64', '', False),
    ('virtual-module', 'Provides: virtual-module\n', True),
    ('virtual-module (>= 2)', 'Provides: virtual-module (= 2)\n', True),
    ('virtual-module (>> 2)', 'Provides: virtual-module (= 2)\n', False),
    ('virtual-module (>= 2)', 'Provides: virtual-module\n', False),
])
def test_policy_conflicts_match_versions_virtual_names_and_architectures(context, tmp_path, conflict, provides, expected):
    policy = deb(tmp_path, 'policy', arch='all', extra=f'Conflicts: {conflict}\n', files={
        'etc/apt/preferences.d/10policy': b'Package: leaf\nPin: version *\nPin-Priority: 700\n'})
    module = deb(tmp_path, 'module', extra=provides)
    q = context.qualify(module, [policy])
    assert bool(manifest(q)['preferences']) is not expected
    q.close()


def test_one_sided_conflict_on_the_consumer_disables_policy(context, tmp_path):
    policy = policy_package(tmp_path)
    consumer = deb(tmp_path, 'consumer', extra='Conflicts: fixture-lock\n')
    q = context.qualify(consumer, [policy])
    assert not manifest(q)['preferences']
    q.close()


def test_a_policy_can_conflict_with_its_own_virtual_name(context, tmp_path):
    policy = deb(tmp_path, 'policy', arch='all', extra='Provides: virtual-policy\nConflicts: virtual-policy\n', files={
        'etc/apt/preferences.d/10policy': b'Package: leaf\nPin: version *\nPin-Priority: 700\n'})
    q = context.qualify(deb(tmp_path, 'consumer', depends='policy'), [policy])
    assert [p['package'][0] for p in manifest(q)['preferences']] == ['policy']
    q.close()
