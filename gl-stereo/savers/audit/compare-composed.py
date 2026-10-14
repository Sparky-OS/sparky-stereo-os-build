#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check that Stereo KWin preserves the producer's left/right ordering."""
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image
results=[]
for root in map(Path,sys.argv[1:]):
    for case in sorted(root.iterdir()):
        if not case.is_dir() or not (case/'kwin.png').exists(): continue
        result={'id':case.name}
        try:
            raw=sorted(case.glob('frame-*.ppm'))[-1]
            a=np.array(Image.open(raw).convert('RGB'))
            b=np.array(Image.open(case/'kwin.png').convert('RGB'))
            assert a.shape==b.shape, f'shape {a.shape} != {b.shape}'
            error=np.abs(a.astype(float)-b.astype(float))
            result.update(max_error=float(error.max()),mean_error=float(error.mean()),changed_fraction=float(np.any(a!=b,axis=2).mean()))
            # KWin rounds the bottom corners of decorated windows, separately per eye.
            # Exclude only those four 8x8 corner squares, not the image interior.
            mask=np.ones(a.shape[:2],dtype=bool)
            width=a.shape[1]//2
            for start in (0,width):
                mask[-8:,start:start+8]=False
                mask[-8:,start+width-8:start+width]=False
            assert np.array_equal(a[mask],b[mask]), 'composited interior differs from producer'
            width=a.shape[1]//2
            distinct=not np.array_equal(a[:,:width],a[:,width:])
            if distinct:
                swapped=np.concatenate((b[:,width:],b[:,:width]),axis=1)
                assert not np.array_equal(a,swapped), 'eye-swap negative control not rejected'
            result.update(passed=True,eye_swap_rejected=distinct)
        except Exception as error: result.update(passed=False,error=str(error))
        results.append(result)
print(json.dumps(results,indent=2))
assert results and all(r['passed'] for r in results)
