#!/usr/bin/env python3
"""Summarize complete steps, reporting every difference and observed spread."""
import json
from pathlib import Path
import statistics
from guard import atomic
from measure import number


def summarize(root, plan):
    groups={}
    for step in plan['steps']:
        if step['kind'] not in ('whole','check','stage1','runtime'):continue
        path=root/'results'/step['id']
        receipt=json.loads((path/'receipt.json').read_text())
        if not receipt['complete']:raise RuntimeError('unaccepted step '+step['id'])
        for m in path.rglob('metrics.json'):
            rel=m.relative_to(path/'result').parent.as_posix()
            key=step['kind']+':'+step.get('task','')+':'+rel
            data=json.loads(m.read_text())
            for metric in ('wall_seconds','user_seconds','system_seconds','instructions','page_faults','max_child_rss_kib','cgroup_peak_bytes'):
                groups.setdefault(key+':'+metric,{}).setdefault(step['form'],[]).append(number(str(data[metric])))
        if step['kind']=='runtime' and step['task']=='startup':
            loader=json.loads((path/'result/loader.json').read_text())
            groups.setdefault('runtime:startup:dynamic_loader:cycles',{}).setdefault(step['form'],[]).append(number(str(loader['total_startup_cycles'])))
    rows=[]
    for key, forms in sorted(groups.items()):
        stats={f:{'n':len(v),'mean':statistics.mean(v),'min':min(v),'max':max(v),
                  'stdev':statistics.stdev(v) if len(v)>1 else None,'observations':v} for f,v in forms.items()}
        row={'measurement':key,'forms':stats,'comparison':{}}
        a=stats.get('A')
        if a:
            for f in ('B','C'):
                if f not in stats:continue
                b=stats[f];delta=b['mean']-a['mean']
                overlap=not(b['max']<a['min'] or b['min']>a['max'])
                row['comparison'][f]={'absolute':delta,'percent':100*delta/a['mean'] if a['mean'] else None,
                    'interpretation': 'single observation; spread unknown' if min(a['n'],b['n'])<2 else
                    ('inside observed spread' if overlap else 'ranges separated in this sample; no population significance claimed')}
        rows.append(row)
    output=root/'summary';output.mkdir(exist_ok=True)
    inputs={}
    for s in plan['steps']:
        if s['kind']=='whole':
            d=json.loads((root/'results'/s['id']/'result/inputs.json').read_text())
            inputs[s['form']]={k:d[k] for k in ('bytes','lines','unique_files')}
    analysis=root/'results/analyze/result'
    extras={}
    if analysis.is_dir():
        for name in ('installed-files','program-bytes','panic-resolution'):
            extras[name]=json.loads((analysis/(name+'.json')).read_text())
        extras['installed_bytes']={f:sum(r['bytes'] for r in v.values() if not r['link']) for f,v in extras['installed-files'].items()}
    atomic(output/'summary.json',{'kit_version':plan['version'],'plan':plan,'rows':rows,'unique_inputs':inputs,**extras})
    lines=['# Rust toolchain measurements','',
           'Unique dep-info input counts are source coverage, not repeated I/O. Targets start empty; filesystem caches are not reset. Compiler installation preloads --version before startup rounds.',
           'Thermal pauses and cool-downs are in each receipt; elapsed time includes any pause during the measured command.', '',
           '| Measurement | A mean [min,max], n | B mean [min,max], n | C mean [min,max], n | B−A (percent) | C−A (percent) | Evidence |',
           '|---|---:|---:|---:|---:|---:|---|']
    for row in rows:
        cells=[]
        for f in 'ABC':
            s=row['forms'].get(f)
            cells.append('—' if s is None else f"{s['mean']:.12g} [{s['min']:.12g},{s['max']:.12g}], {s['n']}")
        comparisons=[]; interpretations=[]
        for f in 'BC':
            c=row['comparison'].get(f)
            comparisons.append('—' if c is None else f"{c['absolute']:.12g} ({c['percent']:.12g}%)" if c['percent'] is not None else f"{c['absolute']:.12g} (undefined baseline)")
            if c:interpretations.append(f+': '+c['interpretation'])
        lines.append('| '+' | '.join([row['measurement'],*cells,*comparisons,'; '.join(interpretations)])+' |')
    if inputs:
        lines+=['','## Unique compiler inputs','','| Count | A | B | C | B−A (%) | C−A (%) |','|---|---:|---:|---:|---:|---:|']
        for key in ('bytes','lines','unique_files'):
            a=inputs['A'][key];b=inputs['B'][key];c=inputs['C'][key]
            lines.append(f'| {key} | {a} | {b} | {c} | {b-a} ({100*(b-a)/a:.12g}%) | {c-a} ({100*(c-a)/a:.12g}%) |')
    if extras:
        totals=extras['installed_bytes'];a=totals['A'];b=totals['B'];c=totals['C']
        lines+=['','## Package payloads','','These are exact archived installed-file lengths; package compression is excluded.',
                '', '| A bytes | B bytes | C bytes | B−A (%) | C−A (%) |','|---:|---:|---:|---:|---:|',
                f'| {a} | {b} | {c} | {b-a} ({100*(b-a)/a:.12g}%) | {c-a} ({100*(c-a)/a:.12g}%) |',
                '', 'ELF section/content and layout differences are in `results/analyze/result/size-differences.json`. Unknown causal contributions remain named there.',
                '', '## Program bytes and panic locations','']
        for name,data in extras['program-bytes'].items():lines.append(f'- {name}: identical across every compiled output = {data["all_same"]}.')
        for f,data in extras['panic-resolution'].items():lines.append(f'- {f}: {data["reported_path"]}:{data["reported_line"]} resolves to authored line {data["authored"]["line"]} ({data["authored"]["how"]}).')
    (output/'REPORT.md').write_text('\n'.join(lines)+'\n')
    return rows
