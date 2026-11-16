#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare unchanged 2D page content, naming the deliberately changed areas."""
import json, sys
from pathlib import Path
from PIL import Image, ImageChops
root=Path(sys.argv[1])
rows=[]
for scale in ['1','1.25']:
    a=Image.open(root/f'published-{scale}/off.png').convert('RGB')
    b=Image.open(root/f'candidate-{scale}/off.png').convert('RGB')
    assert a.size==b.size
    # The toolbar gains a visibility switch; Recording Streams gains a repaired
    # device selector. Everything from Playback Devices through Playback Streams
    # must retain exactly the published rendering, without pixel tolerance.
    s=float(scale)
    unchanged=(0,round(55*s),1560,round(730*s))
    difference=ImageChops.difference(a.crop(unchanged),b.crop(unchanged))
    count=0 if difference.getbbox() is None else sum(pixel!=(0,0,0) for pixel in difference.getdata())
    assert count==0,(scale,count,difference.getbbox())
    rows.append({'scale':scale,'unchanged_region':unchanged,'differing_pixels':count,
                 'whole_frame_difference_box':ImageChops.difference(a,b).getbbox(),
                 'deliberate_differences':['new toolbar action','repaired recording selector']})
print(json.dumps(rows,indent=2))
