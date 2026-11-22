# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Bound reuse of completed archive comparisons, certified by a fresh seeded sample."""
import json
from pathlib import Path
import random
import re
import subprocess

from . import archive, historical, linkcheck, package


def code_binding(root=None):
    root = Path(root) if root else Path(__file__).parent
    return {p.name: archive.digest(p) for p in sorted(root.glob('*.py'))} | {
        'smoke.tsv': archive.digest(root/'smoke.tsv')}


def read_bound(row):
    path = Path(row['path'])
    if not path.is_file() or archive.digest(path) != row['sha256']:
        raise package.Invalid(f'reuse evidence missing or changed: {path}')
    return json.loads(path.read_text())


def view_binding(evidence):
    return {side: sorted([{k: row[k] for k in ('source', 'identity', 'date', 'key_sha256',
                    'MetaKey', 'InRelease_sha256', 'Packages_sha256')} for row in evidence[side]],
                    key=lambda r: (r['source'], r['MetaKey'])) for side in ('candidate', 'dated')}


def verdict(record):
    # Retain findings and notes in full. Changing diagnostics requires review too.
    return {'findings': record['findings'], 'notes': record['notes'],
            'view': record.get('predecessor', {}).get('view', 'none')}


def sample(entries, seed):
    rng = random.Random(seed)
    names = sorted(entries)
    mandatory = [n for n in names if verdict(entries[n]['record'])['view'] == 'uninstallable-at-publication']
    mixed = [n for n in names if verdict(entries[n]['record'])['view'] == 'mixed']
    if len(mixed) < 4 or len(names) < 24 or len(mandatory) > 20:
        raise package.Invalid('reuse needs 24 prior passing inputs including four mixed and every publication-time unusable baseline')
    picked = mandatory + rng.sample(mixed, 4)
    picked += rng.sample([n for n in names if n not in picked], 24-len(picked))
    return picked


def affected_names(controls, changed):
    """Conservative reverse relation closure, including alternatives and recommendations.

    Any version of a public package may participate. Provides aliases and solver
    conflicts count too; a changed preference package forces every input fresh.
    """
    affected = set(changed)
    relations = {}
    for obj in controls:
        names = historical.providers([(obj, '')])
        deps = set()
        for field in ('Depends', 'Pre-Depends', 'Recommends', 'Conflicts', 'Breaks'):
            deps.update(re.findall(r'(?:^|[,|])\s*([a-zA-Z0-9][a-zA-Z0-9+.-]*)', obj.get(field, '')))
        for name in names:
            relations.setdefault(name, set()).update(deps | (set(names)-{name}))
    while True:
        following = affected | {name for name, deps in relations.items() if deps & affected}
        if following == affected:
            return affected
        affected = following


def suite_binding(path, code):
    obj = json.loads(Path(path).read_text())
    if obj.get('exit') != 0 or obj.get('code') != code or not obj.get('whole_suite'):
        raise package.Invalid('reuse needs a passing whole toolkit suite on the exact current code')
    log = obj['log']
    if archive.digest(log['path']) != log['sha256']:
        raise package.Invalid('toolkit suite log changed')
    if not re.search(r'\b\d+ passed\b', Path(log['path']).read_text()) or re.search(r'\b[1-9]\d* failed\b', Path(log['path']).read_text()):
        raise package.Invalid('whole toolkit log does not record a passing suite')
    return archive.digest(path)


def check(debs, *, previous_dir=None, smoke_table=None, archive_config=None, scratch=None, siblings=(),
          previous_siblings=(), min_free_gib=None, root_min_free_gib=1,
          previous_archive_config=None, previous_published_at=None, previous_archive_policy=None,
          archive_evidence=None, collect_predecessor_stops=False, allow_unavailable_baseline=False,
          reuse_manifest=None, reuse_seed=None, suite_record=None):
    from . import release
    if not (reuse_seed and suite_record and previous_archive_config and previous_published_at):
        raise package.Invalid('bound reuse requires a seed, whole-suite record and explicit predecessor views')
    manifest = json.loads(Path(reuse_manifest).read_text())
    old_code = code_binding(manifest['code_root'])
    if old_code != manifest['code']:
        raise package.Invalid('prior gate code binding differs')
    code = code_binding()
    suite_sha = suite_binding(suite_record, code)
    debs = list(map(Path, debs))
    previous_inputs = list(map(Path, previous_siblings))
    if previous_dir:
        previous_inputs += sorted(Path(previous_dir).rglob('*.deb'))
    current_inputs = list(dict.fromkeys(debs + list(map(Path, siblings))))
    previous_inputs = list(dict.fromkeys(previous_inputs))
    native = subprocess.check_output(['dpkg', '--print-architecture'], text=True).strip()
    controls = {p: archive.control(p) for p in dict.fromkeys(current_inputs+previous_inputs)}
    if any(controls[p]['Architecture'] not in (native, 'all') for p in debs):
        raise package.Invalid('reuse requires one native architecture')
    current_inputs = [p for p in current_inputs if controls[p]['Architecture'] in (native, 'all')]
    previous_inputs = [p for p in previous_inputs if controls[p]['Architecture'] in (native, 'all')]
    context = archive.Archive(archive_config, scratch, native, min_free_gib, root_min_free_gib, manifest['candidate_view'])
    context.freeze(current_inputs+previous_inputs)
    context.previous_view = historical.PreviousView(context, previous_archive_config, previous_published_at,
                                                    debs, previous_archive_policy, allow_unavailable_baseline, manifest['dated_view'])
    if archive_evidence:
        historical.retain_view(context, archive_evidence)
    views = view_binding(context.previous_view.evidence)
    if views != manifest['views']:
        raise package.Invalid('reuse signed archive views differ')
    old_current = {r['name']: r for r in manifest['current_inputs']}
    new_current = {controls[p]['Package']: {'path':str(p), 'sha256':archive.digest(p)} for p in current_inputs}
    old_previous = {r['name']: r for r in manifest['previous_inputs']}
    new_previous = {controls[p]['Package']: {'path':str(p), 'sha256':archive.digest(p)} for p in previous_inputs}
    for row in manifest['current_inputs']+manifest['previous_inputs']:
        if archive.digest(row['path']) != row['sha256']:
            raise package.Invalid('original sibling input changed: '+row['path'])
    changed = {n for old,new in ((old_current,new_current),(old_previous,new_previous))
               for n in old.keys()|new.keys() if old.get(n,{}).get('sha256')!=new.get(n,{}).get('sha256')}
    universe = list(controls.values())
    for rows,ctx in ((context.previous_view.evidence['candidate'],context),
                     (context.previous_view.evidence['dated'],context.previous_view.dated)):
        for row in rows:
            text = subprocess.check_output(['/usr/lib/apt/apt-helper','cat-file',row['Packages']],env=ctx.env,text=True)
            universe.extend(archive.fields(p) for p in text.split('\n\n') if p.startswith('Package: '))
    for row in manifest['current_inputs']+manifest['previous_inputs']:
        if row['name'] in changed:
            universe.append(archive.control(row['path']))
    affected = affected_names(universe, changed)
    for name in changed:
        for record in (old_current.get(name),new_current.get(name),old_previous.get(name),new_previous.get(name)):
            if record and any(p.startswith('/etc/apt/') for p in archive.shipped_paths(record['path'])):
                affected.update(new_current)
    entries = {}
    for row in manifest['entries']:
        record = read_bound(row['result'])
        if record.get('findings') != []:
            raise package.Invalid('only a passing comparison may be reused')
        name = row['name']
        if name in entries:
            raise package.Invalid('duplicate reuse input: '+name)
        # Check the recorded candidate and predecessor against their actual archives.
        for field in ('candidate','predecessor'):
            if row.get(field) and archive.digest(row[field]['path']) != row[field]['sha256']:
                raise package.Invalid('prior comparison input changed: '+name)
        if record['package'] != row['candidate']['path']:
            raise package.Invalid('record belongs to another candidate: '+name)
        pred = record.get('predecessor',{}).get('predecessor')
        if pred != (row.get('predecessor') or {}).get('path'):
            raise package.Invalid('record belongs to another predecessor: '+name)
        entries[name] = dict(row, record=record)
    plan=[]
    for deb in debs:
        name=controls[deb]['Package']
        previous=release.previous_build(deb,previous_debs=previous_inputs,controls=controls)
        binding={'candidate':archive.digest(deb),'predecessor':archive.digest(previous) if previous else None,
                 'views':views,'code':code,'suite_sha256':suite_sha}
        old=entries.get(name)
        equal=old and binding['candidate']==old['candidate']['sha256'] and binding['predecessor']==(old.get('predecessor') or {}).get('sha256')
        plan.append({'name':name,'deb':deb,'previous':previous,'binding':binding,
                     'eligible':bool(equal and name not in affected),'reason':'unchanged comparison' if equal and name not in affected else 'changed input/dependent or no passing record'})
    eligible={p['name']:entries[p['name']] for p in plan if p['eligible']}
    picked=sample(eligible,reuse_seed)
    destination=Path(scratch);destination.mkdir(parents=True,exist_ok=True)
    (destination/'reuse-sample.json').write_text(json.dumps({'seed':reuse_seed,'inputs':picked,'old_code':old_code,'new_code':code,'affected':sorted(affected & set(new_current))},indent=2)+'\n')
    results={};sample_ok=True
    ordered=sorted(plan,key=lambda p:(p['name'] not in picked,p['eligible'],debs.index(p['deb'])))
    for row in ordered:
        name=row['name'];fresh=name in picked or not row['eligible']
        result={'input':str(row['deb']),'mode':'fresh' if fresh else 'reused','binding':row['binding'],'reason':row['reason']}
        if fresh:
            context.predecessor_result={};context.link_result=None
            try:
                linkcheck.check(row['deb'],previous_deb=row['previous'],smoke_table=smoke_table,
                                archive_context=context,siblings=current_inputs,previous_siblings=previous_inputs)
                record=context.link_result
                if record is None:
                    raise package.Invalid('fresh gate did not produce a verdict record')
                result['verdict']=verdict(record)
                result['predecessor']=context.predecessor_result
                if name in picked:
                    result['sample_previous_result']=entries[name]['result']
                    if result['verdict']!=verdict(entries[name]['record']):
                        raise package.Invalid('seeded sample verdict differs from prior record: '+name)
                result['exit']=0
            except (OSError,package.Invalid) as exc:
                result.update(exit=1,error=str(exc),predecessor=context.predecessor_result)
                if name in picked:sample_ok=False
        elif not sample_ok:
            result.update(exit=1,error='reuse refused: seeded fresh certification failed')
        else:
            result.update(exit=0,verdict=verdict(entries[name]['record']),previous_result=entries[name]['result'],
                          previous_code=old_code,certification={'seed':reuse_seed,'sample':picked,'suite_sha256':suite_sha})
        results[name]=result
        print('lc1: bound input '+json.dumps(result,sort_keys=True),flush=True)
        report={'inputs':[results[p['name']] for p in plan if p['name'] in results], 'expected':len(plan),
                'completed':len(results),'sample':picked,'seed':reuse_seed,
                'exit':int(len(results)!=len(plan) or any(r['exit'] for r in results.values()))}
        (destination/'bound-verdict.json').write_text(json.dumps(report,indent=2)+'\n')
    if code_binding() != code:
        raise package.Invalid('gate code changed during qualification')
    for row in plan:
        if archive.digest(row['deb']) != row['binding']['candidate'] or (archive.digest(row['previous']) if row['previous'] else None) != row['binding']['predecessor']:
            raise package.Invalid('comparison input changed during qualification')
    if report['exit']:
        raise package.Invalid('bound whole-pool verdict failed; complete inventory: '+str(destination/'bound-verdict.json'))
    print(f'lc1: bound whole-pool verdict passed: {len(plan)} inputs; fresh={sum(r["mode"]=="fresh" for r in results.values())}; reused={sum(r["mode"]=="reused" for r in results.values())}')
