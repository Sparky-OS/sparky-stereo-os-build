#!/usr/bin/env python3
import json,sys
from pathlib import Path
root=Path(sys.argv[1]); result=[]
for name,expected in [('before-daemon',[]),('output-only',['captiond']),('separate-input',['captiond','captiond-input']),('input-off',['captiond']),('paused',[])]:
 rows=json.loads((root/(name+'.json')).read_text())
 nodes={r['info']['props']['node.name']:r['info']['props'] for r in rows if r.get('type')=='PipeWire:Interface:Node' and r.get('info',{}).get('props',{}).get('node.name') in ('captiond','captiond-input')}
 ok=sorted(nodes)==expected
 if 'captiond' in nodes: ok=ok and nodes['captiond'].get('target.object')=='captiond-test-sink' and nodes['captiond'].get('stream.capture.sink') is True
 if 'captiond-input' in nodes: ok=ok and nodes['captiond-input'].get('target.object')=='captiond-test-source' and nodes['captiond-input'].get('node.dont-fallback') is True and nodes['captiond-input'].get('stream.capture.sink') is not True
 result.append(dict(row=name,expected=expected,found=nodes,passed=ok))
print(json.dumps(result,indent=2)); sys.exit(0 if all(r['passed'] for r in result) else 1)
