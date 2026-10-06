import sys, numpy as np
from PIL import Image
def load(p): return np.array(Image.open(p).convert("RGB")).astype(int)
COL = {"red-near":(255,0,0),"green-target":(0,179,0),"blue-far":(0,0,255),
       "magenta-text-near":(255,0,255),"cyan-text-target":(0,204,204),"orange-text-far":(255,128,0),
       "yellow-2D":(255,230,0)}
def blob(img, c, region=None, tol=40):
    d = np.abs(img - np.array(c)).sum(axis=2)
    m = d < tol
    if region is not None:
        x0,x1 = region; mm = np.zeros_like(m); mm[:,x0:x1]=m[:,x0:x1]; m = mm
    ys,xs = np.nonzero(m)
    if len(xs) == 0: return None
    return (xs.mean(), ys.mean(), len(xs))
def report(L, R):
    h,w,_ = L.shape; split = int(w*0.68)
    print("size", w, "x", h, " eyes identical overall:", bool((L==R).all()))
    out = {}
    for name,c in COL.items():
        reg = (split,w) if name=="yellow-2D" else (0,split)
        a = blob(L,c,reg); b = blob(R,c,reg)
        if a is None or b is None:
            print(f"{name:20s} missing (L {a} R {b})"); continue
        dx = b[0]-a[0]; dy = b[1]-a[1]
        out[name] = dx
        print(f"{name:20s} L=({a[0]:.2f},{a[1]:.2f}) n={a[2]:5d}  R=({b[0]:.2f},{b[1]:.2f}) n={b[2]:5d}  right-left dx={dx:+.2f} dy={dy:+.3f}")
    # right panel (legend, 2D axes): identical in both eyes
    print("right panel (x>=%d) pixel differences: %d" % (split, int((L[:,split:]!=R[:,split:]).any(axis=2).sum())))
    # a pure horizontal shift keeps every row's content in its row: the rows holding each
    # colour, and the rows holding anything but the background, are the same in both eyes
    bg = np.array([255,255,255])
    def rows(img, c=None, tol=40):
        if c is None: m = (np.abs(img-bg).sum(axis=2) > 30)[:, :split]
        else: m = (np.abs(img-np.array(c)).sum(axis=2) < tol)[:, :split]
        return m.any(axis=1)
    bad = 0
    for name,c in COL.items():
        if name == "yellow-2D": continue
        bad += int((rows(L,c) != rows(R,c)).sum())
    print("3D area: rows holding each marker/text colour that differ between eyes:", bad)
    print("3D area: rows holding any non-background pixel that differ between eyes:", int((rows(L)!=rows(R)).sum()))
    return out
if __name__ == "__main__":
    d = sys.argv[1]
    report(load(d+"/left.ppm"), load(d+"/right.ppm"))
