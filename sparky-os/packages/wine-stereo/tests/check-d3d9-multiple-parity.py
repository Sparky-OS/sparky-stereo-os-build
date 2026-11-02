#!/usr/bin/env python3
"""Compare isolated mono captures and check the first restacked frame.

Each directory contains result.json, atoms.json, client.stdout, wire.jsonl
and the PNGs from the observer. XRecord must include delivered Present events.
The reference must use the responsive capture handshake. The candidate may
use the blocking handshake as a negative control.
"""
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def load(root):
    result = json.loads((root / 'result.json').read_text())
    assert result['returncode'] == result['trace_returncode'] == 0
    assert [p['phase'] for p in result['phases']] == list(range(9))
    wire = [json.loads(line) for line in (root / 'wire.jsonl').read_text().splitlines()]
    atoms = json.loads((root / 'atoms.json').read_text())
    assert not any(w.get('opcode') == 18 and w.get('atom') in
                   (atoms['_KDE_NET_WM_STEREO_CONTENT'], atoms['_KDE_NET_WM_STEREO_CONTENT_CHILDREN']) for w in wire)
    log = (root / 'client.stdout').read_text()
    assert 'input_failures=0' in log and log.count('input target=') == 5
    counts = [(int(a), int(b)) for a, b in re.findall(r'frame=ready presents=(\d+),(\d+)', log)]
    assert counts == [(12,12), (13,13), (13,13), (14,14), (15,15), (15,16), (15,16), (15,16), (15,16)]
    finished = re.findall(r'capture_done phase=(\d+) pumps=(\d+) presents=(\d+),(\d+)', log)
    if finished:
        assert [int(p) for p, _, _, _ in finished] == list(range(9))
        assert [(int(a), int(b)) for _, _, a, b in finished] == counts
    phases = []
    previous = 0
    for p in result['phases']:
        rows = [w for w in wire if previous < w['monotonic'] <= p['capture_monotonic']]
        previous = p['capture_monotonic']
        requests = [w for w in rows if w.get('extension') == 'Present' and w.get('minor') in (1,5)]
        completes = [w for w in rows if w.get('event') == 'Present' and w.get('evtype') == 1]
        assert len(requests) == len(completes) == [24,2,0,2,2,1,0,0,0][p['phase']]
        assert sorted((w['window'], w['serial']) for w in requests) == sorted((w['window'], w['serial']) for w in completes)
        phases.append({'phase': p['phase'], 'presents': len(requests),
                       'copies': [{k:w[k] for k in ('source','destination','coordinates','monotonic')}
                                  for w in rows if w.get('operation') == 'CopyArea']})
    return result, phases


def restacked(root, result):
    phase = result['phases'][1]
    owner = next(w for w in phase['all_windows'] if w['title'] == 'D3D9 Multiple Owner')
    image = np.asarray(Image.open(root / 'phase1-screen.png').convert('RGB'))
    expected = np.zeros((240,320,3), dtype=np.uint8)
    for i in (1,0):
        xx, yy = 80*i, 40*i
        y, x = np.indices((240-yy if i else 200, 320-xx))
        expected[yy:yy+len(y),xx:xx+x.shape[1]] = np.stack((x%256,199-y,((x>>8)<<3)|(i+1)), axis=2)
    expected[40:88,80:144] = 106
    actual = image[owner['y']:owner['y']+240,owner['x']:owner['x']+320]
    raw = []
    identities = []
    for w in phase['windows']:
        image = np.asarray(Image.open(root / f"phase1-window{w['id']}.png").convert('RGB'))
        assert image.shape == (200,320,3)
        y, x = np.indices((200,320))
        wrong = [int(np.any(image != np.stack((x%256,199-y,((x>>8)<<3)|i),axis=2),axis=2).sum()) for i in (1,2)]
        raw.append(min(wrong))
        identities.append(int(np.argmin(wrong))+1)
    assert sorted(identities) == [1,2]
    return {'owner_pixels':76800, 'owner_wrong':int(np.any(actual != expected,axis=2).sum()),
            'raw_pixels':128000, 'raw_wrong':sum(raw)}


reference, candidate = map(Path, sys.argv[1:3])
a, aw = load(reference)
b, bw = load(candidate)
rows = []
for phase in range(9):
    aa, bb = [np.asarray(Image.open(p / f'phase{phase}-screen.png').convert('RGB')) for p in (reference,candidate)]
    assert aa.shape == bb.shape == (600,800,3)
    rows.append({'phase':phase, 'pixels':480000, 'different':int(np.any(aa != bb,axis=2).sum())})
controls = [restacked(reference,a), restacked(candidate,b)]
passed = not any(r['different'] for r in rows) and not any(r['owner_wrong'] or r['raw_wrong'] for r in controls)
print(json.dumps({'pass':passed, 'comparison':rows, 'restack':controls, 'wire':[aw,bw]},indent=2))
raise SystemExit(0 if passed else 1)
