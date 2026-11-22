#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Wait at most 60 seconds for caption ink, then retain that exact frame."""
import json,subprocess,sys,time
from pathlib import Path
import numpy as np
from PIL import Image
from capture import capture
out=Path(sys.argv[1]);case=sys.argv[2];scale=float(sys.argv[3]);start=time.monotonic();attempt=0
with (out/(case+'-readiness.jsonl')).open('w') as log:
    while time.monotonic()-start<60:
        attempt+=1
        snapshot=json.loads(subprocess.check_output([sys.executable,str(Path(__file__).with_name('kwin_windows.py')),str(out/'kwin.log')],text=True))
        windows=snapshot.get('windows') or []
        caps=[w for w in windows if 'kaption' in w.get('cls','').lower() and not w.get('hidden')]
        info,pixels=capture();counts=[]
        if len(caps)==1:
            x,y,w,h=[int(round(v*scale)) for v in caps[0]['fg']]
            for offset in (0,1920):
                crop=pixels[max(0,y+3):min(1080,y+h-3),offset+max(40,x+3):offset+min(1880,x+w-3)]
                counts.append(int(((crop.min(axis=-1)>230)&(np.ptp(crop.astype(np.int16),axis=-1)<10)).sum()) if crop.size else 0)
        elapsed=time.monotonic()-start
        ready=info['width']==3840 and info['height']==1080 and len(counts)==2 and min(counts)>=50 and (case!='desktop' or any(w.get('desktop') for w in windows))
        log.write(json.dumps(dict(attempt=attempt,elapsed_seconds=elapsed,glyph_pixels=counts,ready=ready))+'\n');log.flush()
        if ready and elapsed<=60:
            Image.fromarray(pixels,'RGB').save(out/(case+'.png'))
            (out/('windows-'+case+'.json')).write_text(json.dumps(snapshot)+'\n')
            print(json.dumps(info));break
        Image.fromarray(pixels,'RGB').save(out/(case+'-not-ready.png'))
        time.sleep(.5)
    else:raise SystemExit('No visible caption text within the 60-second readiness bound')
