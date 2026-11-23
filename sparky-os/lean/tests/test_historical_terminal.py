import pytest
from lean import historical, release
from lean.tests.archive_fixtures import deb, signed_archive

TEXT = '''E: Unable to satisfy dependencies. Reached two conflicting assignments:
   1. edition-app:amd64=1+edition3 is selected for install because:
      1. edition-app-dbgsym:amd64=1+edition3 is selected for install
      2. edition-app-dbgsym:amd64 Depends edition-app (= 1+edition3)
   2. edition-app:amd64=1+edition3 Depends external-library-old (>= 1)
      but none of the choices are installable:
      [no choices]
'''

def test_versioned_terminal_owner():
    assert historical.failure_owners(TEXT) == ['edition-app']

def test_nested_chain_is_not_terminal_assignment():
    assert historical.failure_terminal(TEXT).startswith('   2. edition-app:amd64=')
    assert 'edition-app-dbgsym' not in historical.failure_terminal(TEXT)

@pytest.mark.parametrize('debug', [False, True])
def test_concrete_archive_abi_move_uses_real_dated_baseline(tmp_path, capsys, debug):
    oldlib = deb(tmp_path/'oldlib', 'external-library-old', '1')
    newlib = deb(tmp_path/'newlib', 'external-library-new', '1')
    def keep(name):
        return lambda text: '\n\n'.join(p for p in text.split('\n\n') if not p.startswith('Package: external-library-') or p.startswith('Package: '+name+'\n'))
    old = signed_archive(tmp_path/'archive', additional=[oldlib,newlib], transform=keep('external-library-old'), variants=[('current',keep('external-library-new'),'Wed, 28 Oct 2026 00:00:00 UTC')])
    before = deb(tmp_path/'before','edition-app','1+edition3',depends='external-library-old (>= 1)')
    after = deb(tmp_path/'after','edition-app','1+edition4',depends='external-library-new (>= 1)')
    prior=[before]; candidates=[after]
    if debug:
        prior.append(deb(tmp_path/'olddebug','edition-app-dbgsym','1+edition3',depends='edition-app (= 1+edition3)'))
        candidates.append(deb(tmp_path/'newdebug','edition-app-dbgsym','1+edition4',depends='edition-app (= 1+edition4)'))
    release.check_link(candidates,archive_config=old.parent/'current/archive.json',previous_archive_config=old,previous_published_at='2026-10-27T00:00:00Z',previous_siblings=prior,scratch=tmp_path/'scratch',collect_predecessor_stops=True)
    text=capsys.readouterr().out
    assert f'dated predecessor baselines: {len(candidates)} of {len(candidates)}' in text
    assert 'published predecessor not installable at its publication: 0 inputs' in text
