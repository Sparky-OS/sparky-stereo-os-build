#!/usr/bin/env python3
# usage: an-osd.py <a.png> <b.png> <winx> <winy> <winw> <winh> <screenw> : per eye, bbox of the white text (subtitle and marquee) and of what the volume key added
import sys, numpy as np
from PIL import Image
a=np.array(Image.open(sys.argv[1]).convert('RGB')).astype(int); b=np.array(Image.open(sys.argv[2]).convert('RGB')).astype(int)
wx,wy,ww,wh,sw=map(int,sys.argv[3:8]); stereo = a.shape[1]==2*sw
def box(m):
    ys,xs=np.nonzero(m); return None if len(xs)==0 else (int(xs.min()),int(ys.min()),int(xs.max()-xs.min()+1),int(ys.max()-ys.min()+1))
res={}
for eye in ((0,sw) if stereo else (0,)):
    A=a[wy:wy+wh, eye+wx:eye+wx+ww]; B=b[wy:wy+wh, eye+wx:eye+wx+ww]
    white=(A[...,0]>215)&(A[...,1]>215)&(A[...,2]>215); white[:wh//8+30]=False   # not the frame number blocks
    diff=(abs(A-B).sum(2)>60)
    res[eye]=(box(white), box(white[: int(wh*.55)]), box(white[int(wh*.55):]), box(diff), int(white.sum()))
    print('eye@%d: white text bbox %s (top part %s, bottom part %s), volume OSD added %s, white px %d' % ((eye,)+res[eye]))
if stereo:
    l,r=res[0],res[sw]; print('left == right:', l[:4]==r[:4], ' white px equal:', l[4]==r[4])
