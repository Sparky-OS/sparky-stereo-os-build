#!/usr/bin/env python3
"""Measure caption disparity; do not assign a desktop depth level."""
import json,sys
from pathlib import Path
import numpy as np
from PIL import Image
folder=Path(sys.argv[1]);scale=float(sys.argv[2]);rows=[]
for case in ('desktop','video'):
    a=np.asarray(Image.open(folder/(case+'.pns')).convert('RGB'))
    if a.shape[1]!=3840:raise SystemExit(f'{case}: expected two 1920-wide eyes, found {a.shape}')
    windows=json.loads((folder/('windows-'+case+'.json')).read_text())['windows']
    overlays=[w for w in windows if 'kaption' in w.get('cls','').lower() and not w.get('hidden')]
    if len(overlays)!=1:raise SystemExit(f'{case}: expected one caption surface, found {overlays}')
    window=overlays[0];x,y,w,h=[int(round(v*scale)) for v in window['fg']]
    # CaptionBox.qml: viewport width = parent.width - 36, bottom margin 14,
    # implicit height = viewport.height + 28. Sample its text viewport, not
    # the rounded transparent corners where unrelated windows can show through.
    hx=int(18*scale);vy=int(14*scale)
    x0=max(40,x+hx);x1=min(1880,x+w-hx);y0=max(0,y+vy);y1=min(a.shape[0],y+h-vy)
    left=a[y0:y1,x0:x1];right=a[:,1920:]
    def ink(rgb):
        return (rgb.min(axis=-1)>230)&(np.ptp(rgb.astype(np.int16),axis=-1)<10)
    li=ink(left)
    if li.sum()<50:raise SystemExit(f'{case}: no usable caption glyph witness')
    scores=[]
    for disparity in range(-32,33):
        ri=ink(right[y0:y1,x0-disparity:x1-disparity])
        scores.append((int(np.logical_xor(li,ri).sum()),disparity))
    scores.sort();error,disparity=scores[0]
    shifted=right[y0:y1,x0-disparity:x1-disparity]
    rows.append(dict(case=case,window=window,scale=scale,left_minus_right_px=disparity,
                     glyph_pixels=int(li.sum()),glyph_xor_pixels=error,
                     sample_roi_physical=[x0,y0,x1,y1],
                     second_best_xor=scores[1][0],raw_unequal_rgb_pixels=int(np.any(left!=right[y0:y1,x0:x1],axis=-1).sum()),
                     shifted_unequal_rgb_pixels=int(np.any(left!=shifted,axis=-1).sum()),
                     note='Default translucent backgrounds may composite different video pixels; glyph-mask matching isolates text geometry.'))
(folder/'eye-measurements.json').write_text(json.dumps(rows,indent=2)+'\n')
print('row\texpected\tfound')
for r in rows:
    print(f"{r['case']} disparity\t0 px (screen plane; nonzero waits for row 822)\t{r['left_minus_right_px']} px; {r['glyph_xor_pixels']} glyph pixels differ")
    if r['glyph_xor_pixels']>max(5,r['glyph_pixels']*.05):raise SystemExit('No close same-row glyph match; inspect the captures')
