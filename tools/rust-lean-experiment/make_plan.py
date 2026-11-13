#!/usr/bin/env python3
"""Create a fixed explicit experiment plan; changing it after launch is refused."""
import argparse
import json
from pathlib import Path


def plan(image,forms,subject='stage1 compiler and standard library, full code generation',fixture=False):
    steps=[{'id':'load','kind':'load'}]
    # The whole builds give real final compilers. Repetition uses the largest
    # separately budgeted subject, in A,B,A,B,C order, with fresh targets.
    for f in 'AB':steps.append({'id':'whole-'+f.lower(),'kind':'whole','form':f})
    for i,f in enumerate('ABAB'):
        steps.append({'id':f'stage1-{i}-{f.lower()}','kind':'stage1','form':f,'subject':subject})
    steps.append({'id':'whole-c','kind':'whole','form':'C'})
    for i in range(4,6):
        steps.append({'id':f'stage1-{i}-c','kind':'stage1','form':'C','subject':subject})
    for f in 'ABC':steps.append({'id':'install-'+f.lower(),'kind':'install','form':f,'build':'whole-'+f.lower()})
    for task,rounds in [('startup',8),('hello',4),('check',3),('release',3),('panic',1)]:
        for r in range(rounds):
            for f in ('ABABC' if task!='panic' else 'ABC'):
                # A second A/B observation in each block makes the exact order explicit.
                i=sum(s.get('task')==task and s.get('form')==f for s in steps)
                steps.append({'id':f'{task}-{r}-{f.lower()}-{i}','kind':'runtime','task':task,'form':f})
    steps += [{'id':'analyze','kind':'analyze'},{'id':'summary','kind':'summary'}]
    return {'version':'order541-kit-1','image_id':image,'seed_version':'1.98.1+dfsg1-1+stereo3d1+lc1',
            'cpus':2 if fixture else 4,'minimum_start_free_gib':7 if fixture else 80,'scratch_floor_gib':2,'start_temperature_c':80 if fixture else 62,
            'stop_temperature_c':90,'forms':forms,'steps':steps,'fixture':fixture}


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('kit',type=Path);p.add_argument('image');p.add_argument('--fixture',action='store_true');a=p.parse_args()
    forms={f:json.loads((a.kit/'sources'/ (f+'.json')).read_text())['tree_sha256'] for f in 'ABC'}
    (a.kit/'plan.json').write_text(json.dumps(plan(a.image,forms,fixture=a.fixture),indent=2)+'\n')
