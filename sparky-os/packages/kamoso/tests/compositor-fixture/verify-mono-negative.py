# SPDX-License-Identifier: GPL-2.0-or-later
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
from pathlib import Path
import json,sys
out=Path(sys.argv[1]);action=sys.argv[2]
state=json.loads((out/'effect-1.json').read_text())
assert state['stereoEnabled'] and state['previewActive'] and not state['stereoFrame'],state
pipeline=json.loads((out/'pipeline.json').read_text())
assert any(r['factory']=='appsink' and r.get('sinkBuffers',0)>=5 for r in pipeline)
log=(out/'output.log').read_text(errors='replace')
assert 'ProcessLookupError' not in log and 'Aborted' not in log,log[-3000:]
if action=='photo':
 request=json.loads((out/'effect-2.json').read_text());assert request['path'].endswith('.jpg'),request
 assert 'mono photo was not saved' in log,log[-3000:]
 assert not (out/'ordinary.jpg').exists()
else:
 assert 'Wait for a complete stereo frame before recording.' in (out/'kamoso.log').read_text(errors='replace')
 assert 'Baseline did not acknowledge recording or complete it' in log
print('Negative control reached a live mono preview with Enable 3D on and failed the requested saving route.')
