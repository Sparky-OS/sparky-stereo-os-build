"""KAlgebra / analitza stereo capture analysis. usage: analyze-kalgebra.py <case-dir> <separation-percent>
Reads window.png (full side by side, left first) and geom.txt (matrix uniforms of the left and the right pass logged by tests/gl-shim.c).
Ground truth: world points of the scene (the integer grid points of the reference plane z=-5, the origin = the zero-parallax point, the
axis tips) projected with both eyes' matrices give the predicted right-minus-left disparity (pixels; + = behind the screen) and vertical
difference; the captured left image is block-matched against the right one at those points."""
import sys, numpy as np
from PIL import Image
case = sys.argv[1]
img = np.array(Image.open(f"{case}/window.png").convert("RGB")).astype(float)
H, W2, _ = img.shape; W = W2 // 2
L, R = img[:, :W], img[:, W:]
lines = open(f"{case}/geom.txt").read().splitlines()
vp = [int(v) for v in lines[0].split()[1:]]
out = []
def say(s): print(s); out.append(s)
passes = {}; cur = None
for ln in lines[1:]:
    if ln.startswith("PASS"): cur = ln.split()[1]; passes[cur] = []; continue
    t = ln.split()
    if t[0] == "U" and cur: passes[cur].append(np.array([float(v) for v in t[3:19]]).reshape(4, 4).T)  # column-major uniform
sep = float(sys.argv[2])
# the GL widget in the window: the black rectangle
from scipy import ndimage as ndi
black = (L.sum(axis=2) == 0)
lab, nl = ndi.label(black); sizes = ndi.sum(black, lab, range(1, nl + 1)); black = lab == (1 + int(np.argmax(sizes)))   # the largest black area is the 3D view
ys, xs = np.nonzero(black)
ox, oy = int(xs.min()), int(ys.min())
Wv, Hv = int(xs.max()) - ox + 1, int(ys.max()) - oy + 1
say(f"image {W2}x{H} (eye {W}x{H}); GL widget in the window: x {ox}..{int(xs.max())}, y {oy}..{int(ys.max())} = viewport {Wv}x{Hv}")
proj_passes = [k for k in passes if k.startswith("p") and any(np.abs(m[3, :3]).sum() > 1e-6 for m in passes[k])]
if len(proj_passes) < 2: say("no two passes with a perspective matrix in the log"); sys.exit(1)
pick = lambda k: [m for m in passes[k] if np.abs(m[3, :3]).sum() > 1e-6][-1]
mL, mR = pick(proj_passes[-2]), pick(proj_passes[-1])
say(f"logged matrices (the uniform 'matrix' of the left and the right pass): shear terms (0,2) left {mL[0,2]:+.5f} right {mR[0,2]:+.5f}; eye 0.5*20*sep/100 = {0.5*20*sep/100:.3f} -> expected difference {(0.5*20*sep/100)*2*mL[0,0]/20:+.5f}")
def proj(m, p):
    c = m @ np.append(p, 1.0); n = c[:3] / c[3]
    return (n[0] + 1) / 2 * Wv, (n[1] + 1) / 2 * Hv, c[3]
# Ground truth by rows: a row of the left image and the same row of the right image (vertical disparity 0) show the same world point of a
# straight line at x_L and x_R; the aperture problem of block matching (the reference grid repeats every ~13 px) does not arise.
# Lines: the three axes (red, green, blue: the pixels of that colour), and the four outer edges of the reference plane z=-5, x,y in [-10,10]
# (the leftmost and rightmost grey pixel of the row, which is where an edge is the silhouette).
def px_of(m, p):
    x, y, _ = proj(m, p); return ox + x, oy + (Hv - 1 - y)
def colour_mask(img, kind):
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    if kind == "x": return (r > g + 60) & (r > b + 60)
    if kind == "y": return (g > r + 60) & (g > b + 60)
    if kind == "z": return (b > r + 40) & (b > g + 40)
def centroid(row, mask_row, x0):
    xs = np.nonzero(mask_row)[0]
    if len(xs) == 0 or len(xs) > 6 or xs.max() - xs.min() > 5: return None
    w = np.array([row[x].sum() for x in xs]); return float((xs * w).sum() / w.sum())
rows = []
segs = {"x": (np.array([0., 0., 0.]), np.array([10., 0., 0.])), "y": (np.array([0., 0., 0.]), np.array([0., 10., 0.])), "z": (np.array([0., 0., 0.]), np.array([0., 0., 10.]))}
for kind, (a_, b_) in segs.items():
    mL_, mR_ = colour_mask(L, kind), colour_mask(R, kind)
    for t in np.linspace(0.06, 0.94, 60):
        pw = a_ + (b_ - a_) * t
        xl, yl = px_of(mL, pw); xr, yr = px_of(mR, pw)
        Y = int(round(yl))
        if not (oy + 6 < Y < oy + Hv - 6): continue
        cl = centroid(L[Y], mL_[Y, :], 0); cr = centroid(R[Y], mR_[Y, :], 0)
        if cl is None or cr is None: continue
        # the measured point on the row is the line's pixel; the prediction is the line's x on that row in each eye (find the t' with the row)
        # use the left prediction at this row as the reference: predicted disparity of this world point
        rows.append((kind + " axis", xr - xl, yr - yl, cr - cl))
# the reference plane's outline
edges = [(np.array([-10., -10, -5]), np.array([-10., 10, -5])), (np.array([10., -10, -5]), np.array([10., 10, -5])), (np.array([-10., -10, -5]), np.array([10., -10, -5])), (np.array([-10., 10, -5]), np.array([10., 10, -5]))]
grey = lambda img: (np.abs(img[..., 0] - img[..., 1]) < 12) & (np.abs(img[..., 1] - img[..., 2]) < 12) & (img[..., 0] > 40)
gL, gR = grey(L), grey(R)
def extreme_pred(m, side):
    best = {}
    for a_, b_ in edges:
        for t in np.linspace(0, 1, 800):
            x, y = px_of(m, a_ + (b_ - a_) * t); Y = int(round(y))
            if Y not in best or (x < best[Y] if side == "left" else x > best[Y]): best[Y] = x
    return best
for side in ("left", "right"):
    eL, eR = extreme_pred(mL, side), extreme_pred(mR, side)
    for Y in range(oy + 10, oy + Hv - 10, 3):
        if Y not in eL or Y not in eR: continue
        ml = np.nonzero(gL[Y, ox:ox + Wv])[0]; mr = np.nonzero(gR[Y, ox:ox + Wv])[0]
        if len(ml) == 0 or len(mr) == 0: continue
        xl = (ml.min() if side == "left" else ml.max()) + ox; xr = (mr.min() if side == "left" else mr.max()) + ox
        # the silhouette is the plane outline only where the outline is outermost: accept rows where the prediction is within 3 px in both eyes
        if abs(xl - eL[Y]) > 3 or abs(xr - eR[Y]) > 3: continue
        rows.append(("plane edge (%s)" % side, eR[Y] - eL[Y], 0.0, xr - xl))
names = np.array([r[0] for r in rows]); pred = np.array([r[1] for r in rows]); pdy = np.array([r[2] for r in rows]); meas = np.array([r[3] for r in rows])
say(f"row measurements: {len(rows)} ({', '.join(f'{n}: {int((names==n).sum())}' for n in sorted(set(names)))})")
say(f"predicted disparity {pred.min():+.2f} .. {pred.max():+.2f} px (predicted vertical difference {np.abs(pdy).max():.4f} px); measured {meas.min():+.2f} .. {meas.max():+.2f}")
e = meas - pred
say(f"measured - predicted: mean {e.mean():+.2f}, median abs {np.median(np.abs(e)):.2f} px, within 1 px {np.mean(np.abs(e)<1)*100:.0f}%, within 2 px {np.mean(np.abs(e)<2)*100:.0f}%; correlation {np.corrcoef(pred, meas)[0,1]:.3f}")
for nm, m in (("nearer than the origin (pred < -1)", pred < -1), ("farther than the origin (pred > +1)", pred > 1), ("at the origin's distance (|pred| <= 1)", np.abs(pred) <= 1)):
    if m.sum(): say(f"  {nm}: {int(m.sum())} rows, predicted mean {pred[m].mean():+.2f}, measured mean {meas[m].mean():+.2f}, measured median {np.median(meas[m]):+.2f} px")
for n in sorted(set(names)):
    m = names == n; say(f"  {n}: {int(m.sum())} rows, predicted {pred[m].min():+.2f}..{pred[m].max():+.2f}, measured {meas[m].min():+.2f}..{meas[m].max():+.2f}, median abs error {np.median(np.abs(e[m])):.2f} px")
# vertical: the rows of the axis pixels are identical in both eyes (checked by the row method itself); check the pixel rows directly
bothrows = [(np.nonzero(colour_mask(L, k)[:, ox:ox+Wv].any(axis=1))[0], np.nonzero(colour_mask(R, k)[:, ox:ox+Wv].any(axis=1))[0]) for k in "xyz"]
say("rows holding axis-coloured pixels, left eye minus right eye: " + ", ".join(f"{k}: {len(set(a)^set(b))} rows differ of {len(set(a)|set(b))}" for k, (a, b) in zip('xyz', bothrows)))
diff = np.abs(L - R).sum(axis=2) > 0
gl = np.zeros((H, W), bool); gl[oy:oy + Hv, ox:ox + Wv] = True
say(f"pixels that differ between the eyes: {int(diff.sum())} of {H*W}; outside the 3D view (menus, tabs, buttons, status bar): {int((diff & ~gl).sum())}")
open(f"{case}/analysis.txt", "w").write("\n".join(out) + "\n")
