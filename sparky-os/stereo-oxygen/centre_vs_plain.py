import sys
sys.path.insert(0,'/q/step1')
import numpy as np
from PIL import Image
import make_stereo_icon as m
res={}
for l in sys.argv[1:]:
    icon=l.strip(); ctx,name=icon.split('/')
    for n in (32,48,128,256):
        path,kind=m.source_path('/q/oxygen-icons',icon,n)
        r=m.render(m.load_svg(path),n).astype(float)
        p=np.array(Image.open(f'/q/oxygen-icons/{n}x{n}/{ctx}/{name}.png').convert('RGBA')).astype(float)
        if p.shape!=r.shape: res.setdefault(n,[]).append(None); continue
        bl=lambda a:(a[...,:3]*a[...,3:]+128*(255-a[...,3:]))/255
        res.setdefault(n,[]).append(np.abs(bl(r)-bl(p)).mean()); print(icon,n,kind,round(res[n][-1],2), r.shape)
for n,v in res.items():
    v=[x for x in v if x is not None]; print(n,'mean abs difference (0-255) of our centre render vs Oxygen PNG over grey: mean %.2f max %.2f'%(np.mean(v),np.max(v)), 'icons',len(v))
