#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Verify the explicitly source-reviewed flat scenes stay at screen depth."""
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image
reasons=json.loads(Path(__file__).with_name('flat-scenes.json').read_text())
roots=list(map(Path,sys.argv[1:])); results=[]
for name,reason in reasons.items():
    result=dict(id=name,reason=reason)
    try:
        case=next(root/name for root in roots if (root/name/'kwin.png').exists())
        a=np.array(Image.open(case/'kwin.png').convert('RGB'))
        assert a.shape==(360,1280,3),'wrong geometry'
        left,right=a[:,:640],a[:,640:]
        mask=np.ones((360,640),bool);mask[-8:,:8]=False;mask[-8:,-8:]=False
        assert min(eye.std(axis=(0,1)).max() for eye in (left,right))>1,'empty/uniform image'
        different=np.any(left!=right,axis=2)
        result['different_fraction']=float(different[mask].mean())
        error=np.abs(left.astype(float)-right.astype(float))
        scores={shift:float(np.abs(left.astype(float)-np.roll(right,shift,axis=1).astype(float))[mask].mean()) for shift in (-3,-1,0,1,3)}
        result.update(mean_error=float(error[mask].mean()),shift_scores=scores)
        # Viewport translation changes a few Mesa raster rounding decisions.
        # Require zero as the unique best alignment, sub-1/1000 changed pixels,
        # and less than .02 of one intensity level averaged over the image.
        assert scores[0]<.02 and result['different_fraction']<.001,'flat image mismatch'
        assert all(scores[0]<scores[shift] for shift in (-3,-1,1,3)),'nonzero flat-scene alignment' 
        # The guard must notice a deliberately displaced picture.
        assert not np.array_equal(left[mask],np.roll(right,3,axis=1)[mask]),'shift mutation invisible'
        result['passed']=True
    except Exception as error:result.update(passed=False,error=str(error))
    results.append(result)
print(json.dumps(results,indent=2))
assert all(r['passed'] for r in results)
