import sys
from PIL import Image; import numpy as np
a=np.array(Image.open(sys.argv[1]).convert('RGB')).astype(int)
H,W,_=a.shape; print(a.shape)
for name,sl in (('L',a[:,:W//2]),('R',a[:,W//2:])):
    red=(sl[:,:,0]>200)&(sl[:,:,1]<60)&(sl[:,:,2]<60); grn=(sl[:,:,1]>200)&(sl[:,:,0]<60)&(sl[:,:,2]<60)
    for c,m in (('red',red),('green',grn)):
        ys,xs=np.nonzero(m)
        print(name,c,int(m.sum()), (int(xs.min()),int(ys.min()),int(xs.max()),int(ys.max())) if m.sum() else None)
