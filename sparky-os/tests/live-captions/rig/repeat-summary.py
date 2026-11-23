#!/usr/bin/env python3
"""Summarize every repetition, retaining failures and independently measuring saved frames."""
import json,re,sys
from pathlib import Path
import numpy as np
from PIL import Image
root=Path(sys.argv[1]); rows=json.loads((root/'results.json').read_text())
for row in rows:
    folder=root/(row['gpu']+f"-{row['trial']:02d}")
    log=(folder/'kaption.log').read_text(errors='replace') if (folder/'kaption.log').exists() else ''
    row['utterances']=log.count('output utterance finished')
    row['layer_protocol']=[line for line in log.splitlines() if ('get_layer_surface' in line and 'kaption-overlay' in line) or ('zwlr_layer_surface' in line and '.destroy()' in line) or ('wl_surface' in line and '.attach(nil' in line)]
    row['saved_frames']=[]
    for case in ('desktop','video'):
        try:
            snapshot=json.loads((folder/f'windows-{case}.json').read_text())
            windows=[w for w in snapshot['windows'] if 'kaption' in w.get('cls','').lower() and not w.get('hidden')]
            if len(windows)!=1:raise ValueError('caption surface count '+str(len(windows)))
            w=windows[0];scale=float(row['scale']);x,y,width,height=[round(v*scale) for v in w['fg']]
            a=np.asarray(Image.open(folder/(case+'.pns')).convert('RGB'))
            x0=max(40,x+3);x1=min(1880,x+width-3);y0=max(0,y+3);y1=min(a.shape[0],y+height-3)
            def ink(rgb):return (rgb.min(axis=-1)>230)&(np.ptp(rgb.astype(np.int16),axis=-1)<10)
            left=ink(a[y0:y1,x0:x1]);right=a[:,1920:]
            if left.sum()<50:raise ValueError('no glyph witness')
            scores=sorted((int(np.logical_xor(left,ink(right[y0:y1,x0-d:x1-d])).sum()),d) for d in range(-32,33))
            error,d=scores[0]
            row['saved_frames'].append(dict(case=case,frame_time_ms=snapshot.get('t_monotonic_ms'),window=w,disparity_px=d,glyph_xor=error,glyph_pixels=int(left.sum())))
        except (OSError,ValueError,KeyError) as error:row['saved_frames'].append(dict(case=case,error=str(error)))
(root/'summary.json').write_text(json.dumps(rows,indent=2)+'\n')
lines=['trial\tcard/scale\tload\texpected\tfound\tutterances\tclient unmaps']
for row in rows:
    frames='; '.join(f"{f['case']}: "+(f"{f['disparity_px']} px, xor {f['glyph_xor']}" if 'disparity_px' in f else f['error']) for f in row['saved_frames'])
    if row.get('error'):frames+='; rig failed: '+row['error']
    lines.append(f"{row['trial']}\t{row['gpu']}/{row['scale']}\t{row['load']}\t0 px\t{frames}\t{row['utterances']}\t{sum('.attach(nil' in s for s in row['layer_protocol'])}")
(root/'summary.tsv').write_text('\n'.join(lines)+'\n');print('\n'.join(lines))
