import sys, numpy as np
from PIL import Image
def load(p): return np.array(Image.open(p).convert("RGB")).astype(int)
def diff(a,b):
    A,B=load(a),load(b)
    if A.shape!=B.shape: return f"shape {A.shape} vs {B.shape}"
    return int((np.abs(A-B).sum(axis=2)>0).sum())
for m in ("sw","gpu"):
    e=f"evidence/fx-{m}-"
    for img in ("window","screen"):
        print(f"{m} {img}: off(stereo build+fix) vs debfix: {diff(e+'off/'+img+'.png', e+'debfix/'+img+'.png')} differing px; debian(unpatched) vs debfix: {diff(e+'debian/'+img+'.png', e+'debfix/'+img+'.png')} differing px")
    # molecule pixels in viewer: non-black pixels inside viewer area x302..541,y57..313 of window (2D: window is 571 wide?)
    for v in ("debian","debfix","off"):
        a=load(f"{e}{v}/window.png"); print(f"  {m} {v}: window {a.shape[1]}x{a.shape[0]}, non-black pixels in the viewer area (x 302..541, y 57..313): {int((a[57:314,302:542].sum(axis=2)>0).sum())}")
