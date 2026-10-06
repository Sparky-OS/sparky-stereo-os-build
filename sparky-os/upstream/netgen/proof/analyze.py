import sys, numpy as np
from PIL import Image
from scipy import ndimage as ndi
def load(p): return np.array(Image.open(p).convert("RGB")).astype(int)
def comps(img, minsize=30):
    m = (np.abs(img-255).sum(axis=2) > 30)
    lab, n = ndi.label(m, structure=np.ones((3,3)))
    out = []
    for k, sl in enumerate(ndi.find_objects(lab), 1):
        sz = int((lab[sl]==k).sum())
        if sz < minsize: continue
        ys, xs = np.nonzero(lab == k)
        out.append(dict(size=sz, cx=xs.mean(), cy=ys.mean(), x0=xs.min(), x1=xs.max(), y0=ys.min(), y1=ys.max()))
    return sorted(out, key=lambda c: c["cy"])
def report(L, R):
    print("eye size", L.shape[1], "x", L.shape[0], " eyes identical overall:", bool((L==R).all()))
    a, b = comps(L), comps(R)
    print("components (>=30 px): left", len(a), "right", len(b))
    for i, (p, q) in enumerate(zip(a, b)):
        print(f"  #{i} size L {p['size']:5d} R {q['size']:5d}  L=({p['cx']:.2f},{p['cy']:.2f}) R=({q['cx']:.2f},{q['cy']:.2f})  right-left dx={q['cx']-p['cx']:+.2f} dy={q['cy']-p['cy']:+.3f}")
    # rows holding any non-white pixel: a purely horizontal shift keeps them
    rl = (np.abs(L-255).sum(axis=2) > 30).any(axis=1); rr = (np.abs(R-255).sum(axis=2) > 30).any(axis=1)
    print("rows holding a non-background pixel that differ between eyes:", int((rl != rr).sum()))
    return a, b
if __name__ == "__main__":
    report(load(sys.argv[1]+"/left.ppm"), load(sys.argv[1]+"/right.ppm"))
