"""A moving signed archive cannot excuse a candidate regression or an unverifiable baseline."""
import json
from pathlib import Path
import subprocess

import pytest

from lean import archive, historical, linkcheck, package, release
from lean.tests.archive_fixtures import deb, signed_archive


def fixture(tmp_path, broken_old=False, late=False):
    old_ext = deb(tmp_path / 'ext1', 'external-framework', '1', depends='edition-icons (>= 1)')
    new_ext = deb(tmp_path / 'ext2', 'external-framework', '2', depends='edition-icons (>= 2)')
    def keep(version):
        def transform(text):
            return '\n\n'.join(p for p in text.split('\n\n') if not p.startswith('Package: external-framework\n')
                               or f'\nVersion: {version}\n' in '\n'+p+'\n')
        return transform
    old = signed_archive(tmp_path / 'archive', additional=[old_ext, new_ext],
                         transform=keep('2' if broken_old else '1'),
                         variants=[('current', keep('2'), 'Wed, 28 Oct 2026 00:00:00 UTC'),
                                   ('later', keep('1'), 'Fri, 30 Oct 2026 00:00:00 UTC')])
    current = old.parent / 'current/archive.json'
    before = deb(tmp_path / 'before', 'edition-app', '1', depends='external-framework')
    after = deb(tmp_path / 'after', 'edition-app', '2', depends='external-framework')
    icons1 = deb(tmp_path / 'icons1', 'edition-icons', '1')
    icons2 = deb(tmp_path / 'icons2', 'edition-icons', '2')
    return current, old.parent/'later/archive.json' if late else old, before, after, icons1, icons2


def test_current_red_dated_green_and_cli_counts(tmp_path, capsys):
    current, old, before, after, icons1, icons2 = fixture(tmp_path)
    args = dict(archive_config=current, scratch=tmp_path/'scratch', siblings=[icons2],
                previous_siblings=[before, icons1])
    with pytest.raises(package.Invalid, match='previous edition dependency qualification failed'):
        release.check_link([after], **args)
    release.check_link([after], **args, previous_archive_config=old, previous_published_at='2026-10-27T00:00:00Z')
    output = capsys.readouterr().out
    assert 'predecessor view=dated' in output
    assert 'dated predecessor baselines: 1 of 1' in output
    evidence = list((tmp_path/'scratch').glob('link-*/predecessor-views.json'))
    assert evidence
    rows = json.loads(evidence[0].read_text())
    assert rows['dated'][0]['date'] == '2026-10-26T00:00:00+00:00'
    assert rows['dated'][0]['Packages_sha256'] != rows['candidate'][0]['Packages_sha256']


@pytest.mark.parametrize('broken_old,late,expected', [(True,False,'previous edition dependency qualification failed'),
                                                    (False,True,'later than predecessor publication')])
def test_invalid_baseline_stays_red(tmp_path, broken_old, late, expected):
    current, old, before, after, icons1, icons2 = fixture(tmp_path, broken_old, late)
    with pytest.raises(package.Invalid, match=expected):
        release.check_link([after], archive_config=current, scratch=tmp_path/'scratch', siblings=[icons2],
                           previous_siblings=[before, icons1], previous_archive_config=old,
                           previous_published_at='2026-10-27T00:00:00Z')


def test_dated_mode_does_not_admit_candidate_in_previous_snapshot(tmp_path):
    current, old, before, after, icons1, icons2 = fixture(tmp_path)
    with pytest.raises(package.Invalid, match='candidate packages in previous edition snapshot'):
        release.check_link([after, icons2], archive_config=current, scratch=tmp_path/'scratch',
                           previous_siblings=[before, icons2], previous_archive_config=old,
                           previous_published_at='2026-10-27T00:00:00Z')


def test_candidate_owned_solver_failure_is_not_eligible(tmp_path):
    current, old, before, after, icons1, icons2 = fixture(tmp_path)
    external_successor = deb(tmp_path/'ext3', 'external-framework', '3', depends='edition-icons (>= 2)')
    with pytest.raises(package.Invalid, match='not exclusively outside the candidate set'):
        release.check_link([after, external_successor], archive_config=current, scratch=tmp_path/'scratch',
                           siblings=[icons2], previous_siblings=[before, icons1], previous_archive_config=old,
                           previous_published_at='2026-10-27T00:00:00Z')


def test_existing_missing_library_regression_stays_red_in_dated_view(tmp_path):
    from lean.tests.test_linkcheck import _runpath_case
    _, built = _runpath_case(tmp_path)
    before, after = built('1', 'lib/x86_64-linux-gnu'), built('1+lc1', 'share/own/x86_64-linux-gnu')
    current, old, _, _, icons1, icons2 = fixture(tmp_path/'views')
    # Same real ELF regression fixture; only add the external dependency that requires dated qualification.
    for path in (before, after):
        root = tmp_path / ('unpack-' + path.name)
        subprocess.run(['dpkg-deb', '-R', str(path), str(root)], check=True, stdout=subprocess.DEVNULL)
        control = root/'DEBIAN/control'
        control.write_text(control.read_text().replace('Depends: libc6', 'Depends: libc6, external-framework'))
        subprocess.run(['dpkg-deb', '-b', str(root), str(path)], check=True, stdout=subprocess.DEVNULL)
    with pytest.raises(package.Invalid, match='1 new not found: libdemoown.so'):
        release.check_link([after], archive_config=current, scratch=tmp_path/'new-scratch', siblings=[icons2],
                           previous_siblings=[before, icons1], previous_archive_config=old,
                           previous_published_at='2026-10-27T00:00:00Z')


def test_solvable_predecessor_stays_in_candidate_view(tmp_path, capsys):
    current, old, before, after, icons1, icons2 = fixture(tmp_path)
    release.check_link([after], archive_config=current, scratch=tmp_path/'scratch', siblings=[icons2],
                       previous_siblings=[before, icons2], previous_archive_config=old,
                       previous_published_at='2026-10-27T00:00:00Z')
    output = capsys.readouterr().out
    assert 'predecessor view=candidate' in output
    assert 'dated predecessor baselines: 0 of 1' in output


def test_different_archive_key_is_not_the_same_view(tmp_path):
    current, old, before, after, icons1, icons2 = fixture(tmp_path)
    other = signed_archive(tmp_path/'other')
    with pytest.raises(package.Invalid, match='same archives, components and signing keys'):
        release.check_link([after], archive_config=current, scratch=tmp_path/'scratch', siblings=[icons2],
                           previous_siblings=[before, icons1], previous_archive_config=other,
                           previous_published_at='2026-10-27T00:00:00Z')


def test_signed_metadata_cannot_change_after_update(tmp_path):
    current, old, before, after, icons1, icons2 = fixture(tmp_path)
    context = archive.Archive(old, tmp_path/'scratch', 'amd64')
    index = next((context.base/'state/lists').glob('*_Packages'))
    index.write_bytes(index.read_bytes() + b'\n')
    with pytest.raises(package.Invalid, match='authenticated metadata missing or changed'):
        historical.authenticated_view(context, historical.instant('2026-10-27T00:00:00Z'))


def test_terminal_conflict_owner_excludes_the_request_chain():
    text = '''The following packages have unmet dependencies:
 edition-app : Depends: external-framework but it is not going to be installed
 policy-a : Conflicts: policy-b but 1 is to be installed
E: Unable to satisfy dependencies. Reached two conflicting assignments:
   1. policy-a:amd64=1 is selected for install
   2. policy-a:amd64 is not selected for install because:
      1. policy-b:amd64=1 is selected for install
      2. policy-a:amd64 Conflicts policy-b
'''
    assert historical.failure_owners(text) == ['policy-a']


def mixed_fixture(tmp_path, implicated=False, different=False):
    import hashlib
    current, old, before, after, icons1, icons2 = fixture(tmp_path)
    extra = []
    if implicated:
        extra.append(deb(tmp_path/'third-ext', 'external-framework', '2', depends='edition-icons (>= 2)'))
    third = signed_archive(tmp_path/'third', additional=extra,
        variants=[('current', lambda x: x, 'Wed, 28 Oct 2026 00:00:00 UTC'),
                  ('changed', lambda x: x+'\n', 'Wed, 28 Oct 2026 00:00:00 UTC')])
    third_now = json.loads((third.parent/'current/archive.json').read_text())[0]
    third_old = json.loads((third.parent/('changed' if different else 'current')/'archive.json').read_text())[0]
    candidate = json.loads(current.read_text()) + [third_now]
    previous = json.loads(old.read_text()) + [third_old]
    (tmp_path/'current.json').write_text(json.dumps(candidate))
    (tmp_path/'previous.json').write_text(json.dumps(previous))
    proof = tmp_path/'search.json';proof.write_text(json.dumps({'fixture': 'no retained older third-party indexes'}))
    policy = {'publication': '2026-10-27T00:00:00Z', 'candidate_frozen': {'2': {
        'uri': third_now['uri'], 'suite': third_now['suite'], 'searches': [
            {'method': method, 'result': 'no-dated-signed-copy', 'summary': 'isolated synthetic archive search',
             'files': [{'path': str(proof), 'sha256': hashlib.sha256(proof.read_bytes()).hexdigest()}]}
            for method in ['official-mirrors', 'retained-baseline', 'archive-search']]}}}
    (tmp_path/'policy.json').write_text(json.dumps(policy))
    return dict(debs=[after], archive_config=tmp_path/'current.json', scratch=tmp_path/'scratch',
                siblings=[icons2], previous_siblings=[before, icons1],
                previous_archive_config=tmp_path/'previous.json', previous_archive_policy=tmp_path/'policy.json',
                previous_published_at=policy['publication'], archive_evidence=tmp_path/'round-evidence')


def test_unrelated_current_archive_with_search_proof_is_allowed(tmp_path, capsys):
    args = mixed_fixture(tmp_path)
    release.check_link(**args)
    output = capsys.readouterr().out
    assert 'predecessor view=mixed' in output
    assert 'no dated signed copy; bound search evidence; absent from solver failure' in output
    assert 'mixed dated/current: 1' in output
    saved = tmp_path/'round-evidence/amd64'
    assert (saved/'archive-view.json').is_file()
    subprocess.run(['sha256sum', '-c', 'SHA256SUMS'], cwd=saved, check=True, stdout=subprocess.DEVNULL)
    assert len(list((saved/'state/lists').glob('*InRelease'))) == 2


def test_implicated_archive_with_only_a_later_index_still_blocks(tmp_path):
    args = mixed_fixture(tmp_path, implicated=True)
    with pytest.raises(package.Invalid, match='solver failure names an archive with only a later index'):
        release.check_link(**args)


def test_reused_archive_must_equal_the_candidate_index(tmp_path):
    args = mixed_fixture(tmp_path, different=True)
    with pytest.raises(package.Invalid, match='differs from candidate frozen index'):
        release.check_link(**args)


def test_missing_or_changed_search_evidence_blocks(tmp_path):
    args = mixed_fixture(tmp_path)
    (tmp_path/'search.json').write_text('{}')
    with pytest.raises(package.Invalid, match='search evidence missing or changed'):
        release.check_link(**args)
