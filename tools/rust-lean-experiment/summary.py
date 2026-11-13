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
        if step['kind'] not in ('whole','check','runtime'):continue
        path=root/'results'/step['id']
        receipt=json.loads((path/'receipt.json').read_text())
        if not receipt['complete']:raise RuntimeError('unaccepted step '+step['id'])
        for m in path.rglob('metrics.json'):
            rel=m.relative_to(path/'result').parent.as_posix()
            key=step['kind']+':'+step.get('task','')+':'+rel
            data=json.loads(m.read_text())
            for metric in ('wall_seconds','user_seconds','system_seconds','instructions','page_faults','max_child_rss_kib','cgroup_peak_bytes'):
                groups.setdefault(key+':'+metric,{}).setdefault(step['form'],[]).append(number(str(data[metric])))
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
    atomic(output/'summary.json',{'kit_version':plan['version'],'plan':plan,'rows':rows})
    lines=['# Rust toolchain measurements','',
           'Unique dep-info input counts are source coverage, not repeated I/O. All timing is warm-cache unless explicitly marked.',
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
    (output/'REPORT.md').write_text('\n'.join(lines)+'\n')
    return rows
