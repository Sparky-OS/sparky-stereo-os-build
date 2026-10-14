#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compare a composed pair with independently rendered single-eye cameras."""
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image
reference=Path(sys.argv[1]); captures=list(map(Path,sys.argv[2:])); results=[]
for case in sorted(reference.iterdir()):
    if not case.is_dir(): continue
    item={'id':case.name}
    try:
        actual=next(root/case.name for root in captures if (root/case.name/'LEFT.png').exists())
        eyes=[]; expected=[]
        for eye in ('left','right'):
            eyes.append(np.array(Image.open(actual/(eye.upper()+'.png')).convert('RGB'),dtype=float))
            expected.append(np.array(Image.open(case/eye/'frame.png').convert('RGB'),dtype=float))
        mask=np.ones(eyes[0].shape[:2],dtype=bool);mask[-8:,:8]=False;mask[-8:,-8:]=False
        mask &= np.maximum(expected[0].max(axis=2),expected[1].max(axis=2))>8
        assert mask.sum()>=50,'too little visible reference geometry'
        errors=[float(np.abs(a-b)[mask].mean()) for a,b in zip(eyes,expected)]
        wrong=[float(np.abs(a-b)[mask].mean()) for a,b in zip(eyes,expected[::-1])]
        # One intensity level of mean visible-geometry error allows raster rounding, not a
        # shifted copy: the independently rendered wrong-eye control must fail.
        alignment=[min(range(-2,3),key=lambda shift:float(np.abs(a-np.roll(b,shift,axis=1))[mask].mean())) for a,b in zip(eyes,expected)]
        item.update(mean_error=errors,wrong_eye_error=wrong,alignment_px=alignment)
        assert min(a.std(axis=(0,1)).max() for a in eyes)>1,'empty/uniform scene'
        assert max(errors)<1,'reference mismatch'
        assert alignment==[0,0],'reference alignment is not zero'
        assert min(wrong)>.05 and min(wrong)>10*max(max(errors),.001),'no unambiguous eye-order proof'
        item['passed']=True
    except Exception as error: item.update(passed=False,error=str(error))
    results.append(item)
print(json.dumps(results,indent=2))
