"""Reuse proves bindings and a reproducible fresh sample; it never turns failure into success."""
import json
from pathlib import Path
import pytest
from lean import archive, package, reuse


def test_sample_is_seeded_and_keeps_both_repair_inputs_and_four_mixed():
    entries={str(n):{'record':{'findings':[],'notes':[], 'predecessor':{'view':
        'uninstallable-at-publication' if n<2 else 'mixed' if n<12 else 'candidate'}}} for n in range(50)}
    chosen=reuse.sample(entries,'publication-round')
    assert len(chosen)==len(set(chosen))==24
    assert set(('0','1'))<=set(chosen)
    assert sum(entries[n]['record']['predecessor']['view']=='mixed' for n in chosen)>=4
    assert reuse.sample(entries,'publication-round')==chosen
    assert reuse.sample(entries,'another-round')!=chosen


def test_changed_dependency_alternatives_provides_recommends_and_conflicts_are_fresh():
    objects=[{'Package':'theme','Provides':'theme-api'},
             {'Package':'look','Depends':'unrelated | theme-api (>= 1)'},
             {'Package':'desktop','Recommends':'look'},
             {'Package':'old-style','Breaks':'theme (>= 2)'},
             {'Package':'other','Depends':'libc6'}]
    objects=[dict(o,Version='1',Architecture='all') for o in objects]
    assert reuse.affected_names(objects,{'theme'})=={'theme','theme-api','look','desktop','old-style'}


def test_result_binding_rejects_changed_evidence(tmp_path):
    p=tmp_path/'verdict.json';p.write_text('{"findings": []}')
    row={'path':str(p),'sha256':archive.digest(p)}
    assert reuse.read_bound(row)=={'findings':[]}
    p.write_text('{"findings": ["missing library"]}')
    with pytest.raises(package.Invalid,match='missing or changed'):reuse.read_bound(row)


def test_suite_binding_requires_exact_code_success_and_unchanged_log(tmp_path):
    log=tmp_path/'suite.log';log.write_text('500 passed, 2 skipped\n')
    p=tmp_path/'suite.json';obj={'exit':0,'whole_suite':True,'code':{'gate.py':'abc'},'log':{'path':str(log),'sha256':archive.digest(log)}}
    p.write_text(json.dumps(obj));assert reuse.suite_binding(p,obj['code'])==archive.digest(p)
    with pytest.raises(package.Invalid,match='exact current code'):reuse.suite_binding(p,{'gate.py':'new'})
    obj['exit']=1;p.write_text(json.dumps(obj))
    with pytest.raises(package.Invalid,match='passing whole toolkit'):reuse.suite_binding(p,obj['code'])
    obj['exit']=0;p.write_text(json.dumps(obj));log.write_text('1 failed, 499 passed\n')
    with pytest.raises(package.Invalid,match='log changed'):reuse.suite_binding(p,obj['code'])


def test_verdict_comparison_does_not_drop_a_real_finding_or_note():
    clean={'findings':[],'notes':[],'predecessor':{'view':'mixed'}}
    broken=dict(clean,findings=['missing library'])
    assert reuse.verdict(clean)!=reuse.verdict(broken)
    assert reuse.verdict(clean)!=reuse.verdict(dict(clean,notes=['new loader warning']))


def test_retained_signed_view_is_authenticated_without_updating(tmp_path):
    from lean.tests.archive_fixtures import signed_archive
    config=signed_archive(tmp_path/'repo')
    first=archive.Archive(config,tmp_path/'first','amd64')
    second=archive.Archive(config,tmp_path/'second','amd64',frozen_view=first.base)
    assert first.metadata==second.metadata
    assert not (second.base/'update.log').exists()
    assert json.loads((second.base/'retained-authentication.json').read_text())['signatures']==1
    metadata=json.loads((first.base/'metadata.json').read_text())
    row=next(r for r in metadata['metadata'] if r['path'].endswith('Packages'))
    path=first.base/row['path'];path.write_bytes(path.read_bytes()+b'\n')
    with pytest.raises(package.Invalid,match='metadata differs'):
        archive.Archive(config,tmp_path/'third','amd64',frozen_view=first.base)


def test_retained_view_cannot_replace_signed_packages_even_with_new_manifest_hash(tmp_path):
    from lean.tests.archive_fixtures import signed_archive
    config=signed_archive(tmp_path/'repo')
    first=archive.Archive(config,tmp_path/'first','amd64')
    manifest=first.base/'metadata.json';obj=json.loads(manifest.read_text())
    row=next(r for r in obj['metadata'] if r['path'].endswith('Packages'))
    path=first.base/row['path'];path.write_bytes(path.read_bytes()+b'\n')
    row.update(sha256=archive.digest(path),size=path.stat().st_size);manifest.write_text(json.dumps(obj))
    with pytest.raises(package.Invalid,match='differs from its InRelease'):
        archive.Archive(config,tmp_path/'second','amd64',frozen_view=first.base)


def test_bound_gate_fresh_sample_and_reuse_one_verdict(tmp_path, monkeypatch):
    from lean import release
    from lean.tests.test_historical import fixture
    from lean.tests.archive_fixtures import deb
    current,old,before,after,icons1,icons2=fixture(tmp_path)
    other_old=deb(tmp_path/'other-old','other-app','1',depends='external-framework')
    other_new=deb(tmp_path/'other-new','other-app','2',depends='external-framework')
    old_scratch=tmp_path/'old-run'
    args=dict(archive_config=current,scratch=old_scratch,siblings=[icons2],
              previous_siblings=[before,other_old,icons1],previous_archive_config=old,
              previous_published_at='2026-10-27T00:00:00Z')
    release.check_link([after,other_new],**args)
    context=next(p.parent for p in old_scratch.glob('link-*/predecessor-views.json'))
    dated=next((old_scratch/'dated-predecessor').glob('link-*'))
    records={}
    for p in old_scratch.glob('link-*/case-*/link-check.json'):
        obj=json.loads(p.read_text());records[archive.control(obj['package'])['Package']]=(p,obj)
    def bound(p):return {'path':str(p),'sha256':archive.digest(p)}
    def inputs(paths):return [dict(bound(p),name=archive.control(p)['Package']) for p in paths]
    entries=[]
    for candidate,previous in [(after,before),(other_new,other_old)]:
        name=archive.control(candidate)['Package'];p,record=records[name]
        entries.append(dict(name=name,result=bound(p),candidate=bound(candidate),predecessor=bound(previous)))
    manifest={'code_root':str(Path(reuse.__file__).parent),'code':reuse.code_binding(),
              'candidate_view':str(context),'dated_view':str(dated),
              'views':reuse.view_binding(json.loads((context/'predecessor-views.json').read_text())),
              'current_inputs':inputs([after,other_new,icons2]),'previous_inputs':inputs([before,other_old,icons1]),
              'entries':entries}
    m=tmp_path/'reuse.json';m.write_text(json.dumps(manifest))
    log=tmp_path/'suite.log';log.write_text('fixture: 1 passed\n')
    suite=tmp_path/'suite.json';suite.write_text(json.dumps({'exit':0,'whole_suite':True,'code':reuse.code_binding(),'log':bound(log)}))
    # Exercise the full runner cheaply; the independent sample test enforces 24.
    monkeypatch.setattr(reuse,'sample',lambda entries,seed:['edition-app'])
    args.update(scratch=tmp_path/'new-run',reuse_manifest=m,reuse_seed='fixture',suite_record=suite)
    release.check_link([after,other_new],**args)
    result=json.loads((tmp_path/'new-run/bound-verdict.json').read_text())
    assert result['exit']==0 and result['completed']==result['expected']==2
    assert [r['mode'] for r in result['inputs']]==['fresh','reused']
    assert all(r['binding']['code']==reuse.code_binding() for r in result['inputs'])
    manifest['views']['candidate'][0]['Packages_sha256']='0'*64;m.write_text(json.dumps(manifest))
    args['scratch']=tmp_path/'wrong-view'
    with pytest.raises(package.Invalid,match='signed archive views differ'):
        release.check_link([after,other_new],**args)
