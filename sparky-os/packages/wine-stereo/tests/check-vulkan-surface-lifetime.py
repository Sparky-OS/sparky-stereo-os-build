#!/usr/bin/env python3
import json,re,sys
from pathlib import Path
p=Path(sys.argv[1]);r=json.load(open(p/'result.json'));assert r['returncode']==r['trace_returncode']==0
assert [x['phase'] for x in r['phases']]==list(range(6))
atoms=json.load(open(p/'atoms.json'));wire=[json.loads(l) for l in (p/'wire.jsonl').read_text().splitlines()]
content=[w for w in wire if w.get('opcode')==18 and w.get('atom')==atoms['_KDE_NET_WM_STEREO_CONTENT']];children=[w['window'] for w in content]
assert len(children)==len(set(children))==17
assert all(w['value']==[3] for w in content)
assert sum(w.get('opcode')==4 and w.get('window') in children for w in wire)==17
assert not any(w.get('opcode')==19 and w.get('atom')==atoms['_KDE_NET_WM_STEREO_CONTENT'] for w in wire)
assert not any(w.get('extension')=='Present' and w.get('minor') in (1,5) for w in wire)
owners=[]
for stage in r['phases']:
 a,b=[next(w for w in stage['all_windows'] if w['title']=='Lifetime Owner '+n) for n in ['A','B']];owners=[a['id'],b['id']]
 assert not a['declaration'] and not b['declaration']
 active=[w for w in stage['all_windows'] if w['id'] in children];phase=stage['phase']
 expected=([children[0]],[]) if phase==0 else (([],[children[0]]) if phase==1 else (([children[1]],[]) if phase==4 else ([],[])))
 assert a['properties'].get('_KDE_NET_WM_STEREO_CONTENT_CHILDREN',[])==expected[0]
 assert b['properties'].get('_KDE_NET_WM_STEREO_CONTENT_CHILDREN',[])==expected[1]
 if phase in [0,1,2,4]:
  assert len(active)==1 and active[0]['id']==children[1 if phase==4 else 0]
  assert active[0]['declaration']==[3]
  if phase==2:assert not active[0]['mapped'] and active[0]['parent'] not in owners
  else:assert active[0]['parent']==(b['id'] if phase==1 else a['id'])
 else:assert not active
state={};writes=deletes=0
for w in wire:
 if w.get('atom')!=atoms['_KDE_NET_WM_STEREO_CONTENT_CHILDREN']:continue
 if w.get('opcode')==18:
  writes+=1;value=w['value'];assert all(x in children for x in value)
  old=state.get(w['window'],[]);new=value if w['mode']==0 else value+old if w['mode']==1 else old+value
  assert len(new)==len(set(new));state[w['window']]=new
 elif w.get('opcode')==19:deletes+=1;state[w['window']]=[]
assert all(not v for v in state.values())
log=(p/'client.stdout').read_text();created=re.findall(r'created iteration=(\d+) result=(-?\d+) acknowledged=(\d+) restored=(\d+) tid=(\d+)',log)
assert len(created)==17 and all(x[1:4]==('0','1','1') for x in created)
assert 'PASS helper nested property restoration' in log
assert 'helper_invalid_window error=1400 vulkan_calls=0' in log
moves=[tuple(map(int,m)) for m in re.findall(r'move iteration=\d+ start=(\d+) end=(\d+)',log)]
destroys=[tuple(map(int,m)) for m in re.findall(r'destroy iteration=\d+ start=(\d+) end=(\d+)',log)]
overlap=sum(any(max(a,c)<min(b,d) for c,d in moves) for a,b in destroys)
assert moves and overlap>0
print(json.dumps({'pass':True,'surface_creations':17,'content_writes':len(content),'content_deletes':0,'actual_destroy_requests':17,'membership_writes':writes,'membership_deletes':deletes,'duplicate_membership_entries':0,'final_owner_lists_empty':True,'property_restorations':17,'invalid_window_helper_error':1400,'vulkan_calls_with_invalid_hwnd':0,'move_intervals':moves,'destroy_intervals':destroys,'destroy_intervals_overlapping_owner_operations':overlap,'present_requests':0,'scope':'Surface lifecycle/declaration/control only; no rendered pixel or swapchain/Present-concurrency claim.'},indent=2))
