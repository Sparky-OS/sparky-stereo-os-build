import sys, struct, numpy as np
from PIL import Image
d=open(sys.argv[1],'rb').read()
hs=struct.unpack('>I',d[:4])[0]; w=struct.unpack('>I',d[16:20])[0]; h=struct.unpack('>I',d[20:24])[0]
bpl=struct.unpack('>I',d[48:52])[0]; nc=struct.unpack('>I',d[76:80])[0]
off=hs+nc*12
a=np.frombuffer(d[off:off+bpl*h],dtype=np.uint8).reshape(h,bpl)[:,:w*4].reshape(h,w,4)
Image.fromarray(a[:,:,[2,1,0]]).save(sys.argv[2])
