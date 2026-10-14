#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Verify the owning camera fix against its pre-patch pixels and timing input."""
import json
from pathlib import Path
import subprocess
import sys
import numpy as np
from PIL import Image

root=Path(sys.argv[1]);tools=Path(__file__).resolve().parent
reference=root/'installed-flurry-controls/flurry';reference.mkdir(parents=True,exist_ok=True)
for eye in ('left','right'):
    target=reference/eye
    if not target.exists():target.symlink_to(root/('installed-flurry-reference-'+eye)/'flurry',target_is_directory=True)
for captures,expected in [('installed-flurry',True),('installed-kwin',False)]:
    output=subprocess.check_output([sys.executable,str(tools/'compare-reference.py'),str(reference.parent),str(root/captures)],text=True)
    items=json.loads(output);print(output)
    assert len(items)==1 and items[0]['id']=='flurry' and items[0]['passed'] is expected
stock=np.array(Image.open(root/'installed-mono/flurry/stock/frame.png').convert('RGB'))
assert stock.std(axis=(0,1)).max()>1
for mode in ('stock','disabled'):
    current=np.array(Image.open(root/'installed-flurry-mono/flurry'/mode/'frame.png').convert('RGB'))
    assert np.array_equal(stock,current),(mode,'pixels differ from original saver')
clocks=[json.loads((root/directory/'flurry/ready').read_text())['clock_queries'] for directory in ('installed-kwin','installed-flurry')]
assert clocks[0]==clocks[1],('simulation timing input changed',clocks)
subprocess.run([sys.executable,str(tools/'compare-composed.py'),str(root/'installed-flurry')],check=True)
print('PASS: Flurry owning camera, old-flat negative control, original 2D pixels, unchanged simulation timing queries and exact KWin composition')
