import sys, numpy as np
from PIL import Image
a=np.asarray(Image.open(sys.argv[1]).convert("RGBA")).astype(int); b=np.asarray(Image.open(sys.argv[2]).convert("RGBA")).astype(int)
if a.shape!=b.shape: print(f"{sys.argv[1].split('/')[-2]} vs {sys.argv[2].split('/')[-2]}: sizes differ {a.shape} {b.shape}")
else: print(f"{sys.argv[1].split('/')[-2]} vs {sys.argv[2].split('/')[-2]}: {a.shape[1]}x{a.shape[0]} differing pixels {int(np.any(a!=b,axis=2).sum())}")
