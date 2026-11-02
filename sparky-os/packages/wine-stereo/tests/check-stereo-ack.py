#!/usr/bin/env python3
import json,re,sys
from pathlib import Path
p=Path(sys.argv[1]);expected=sys.argv[2];r=json.load(open(p/'result.json'));assert r['returncode']==r['trace_returncode']==0
atoms=json.load(open(p/'atoms.json'));wire=[json.loads(l) for l in (p/'wire.jsonl').read_text().splitlines()];log=(p/'client.stderr').read_text()
receipts=re.findall(r'WINE254_INJECT NtUserSetProp hwnd=(0x[0-9a-f]+) value=0x18003 result=(\d+)',log);assert len(receipts)==1
content=[w for w in wire if w.get('opcode')==18 and w.get('atom')==atoms['_KDE_NET_WM_STEREO_CONTENT']]
member=[w for w in wire if w.get('opcode')==18 and w.get('atom')==atoms['_KDE_NET_WM_STEREO_CONTENT_CHILDREN']]
written=receipts[0][1]=='1'
accepted='Wine stereo WSI v1: acknowledged' in log
assert accepted != ('Wine stereo WSI v1: ordinary WSI fallback' in log)
if accepted:assert written
if accepted:assert 'Wine stereo WSI v1: acknowledged' in log
else:assert 'Wine stereo WSI v1: ordinary WSI fallback' in log
passed=len(content)==int(accepted) and (bool(member) if accepted else not member)
if accepted:passed=passed and content[0]['value']==[3]
print(json.dumps({'pass':passed,'acknowledgement_receipts':receipts,'write_succeeded':written,'producer_acknowledged':accepted,'declaration_failure_injections':log.count('WINE254_INJECT stereo_declare_x11_child'),'native_content_writes':len(content),'membership_writes':len(member),'expected':expected},indent=2))
raise SystemExit(0 if passed else 1)
