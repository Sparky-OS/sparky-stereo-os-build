"""Kalzium / Avogadro stereo capture analysis. usage: analyze-kalzium.py <case-dir> <molecule.xyz>
Reads window.png (full side by side, left first) and geom.txt (the modelView (uniform 0) and projection (uniform 1) of the left and the
right pass, logged by tests/gl-shim.c). Ground truth: each atom's centre (from the xyz file) projected with both eyes' matrices gives the
predicted right-minus-left disparity (pixels; + = behind the screen) and vertical difference; the captured left image is block-matched
against the right one around each atom's predicted position."""
import sys, numpy as np
from PIL import Image
from scipy import ndimage as ndi
case, xyz = sys.argv[1], sys.argv[2]
img = np.array(Image.open(f"{case}/window.png").convert("RGB")).astype(float)
H, W2, _ = img.shape; W = W2 // 2
L, R = img[:, :W], img[:, W:]
out = []
def say(s): print(s); out.append(s)
atoms = []
for ln in open(xyz).read().splitlines()[2:]:
    t = ln.split()
    if len(t) >= 4: atoms.append((t[0], np.array([float(v) for v in t[1:4]])))
lines = open(f"{case}/geom.txt").read().splitlines()
passes = {}; cur = None
for ln in lines[1:]:
    if ln.startswith("PASS"): cur = ln.split()[1]; passes[cur] = []; continue
    t = ln.split()
    if t[0] == "U" and cur: passes[cur].append(np.array([float(v) for v in t[3:19]]).reshape(4, 4).T)
pk = sorted([k for k in passes if k.startswith("p")], key=lambda k: int(k[1:]))
if len(pk) < 2: say("no two projective passes in the log"); sys.exit(1)
pL, pR = passes[pk[-2]], passes[pk[-1]]
MV, PL, PR = pL[0], pL[1], pR[1]
assert np.allclose(pL[0], pR[0]), "the model view differs between the eyes"
say(f"logged: model view translation {MV[:3,3]}, projection shear term (0,2): left {PL[0,2]:+.5f} right {PR[0,2]:+.5f}, (0,3): left {PL[0,3]:+.4f} right {PR[0,3]:+.4f}")
black = (L.sum(axis=2) == 0)
lab, nl = ndi.label(black); sizes = ndi.sum(black, lab, range(1, nl + 1)); black = lab == (1 + int(np.argmax(sizes)))
ys, xs = np.nonzero(black); ox, oy = int(xs.min()), int(ys.min()); Wv, Hv = int(xs.max()) - ox + 1, int(ys.max()) - oy + 1
say(f"image {W2}x{H} (eye {W}x{H}); molecule viewer in the window: x {ox}..{int(xs.max())}, y {oy}..{int(ys.max())} = {Wv}x{Hv}")
def px(P, p):
    c = P @ (MV @ np.append(p, 1.0)); n = c[:3] / c[3]
    return ox + (n[0] + 1) / 2 * Wv, oy + (1 - (n[1] + 1) / 2) * Hv, c[3]
res = []
HW = 4
for name, p in atoms:
    xl, yl, wl = px(PL, p); xr, yr, wr = px(PR, p)
    X, Y = int(round(xl)), int(round(yl))
    if not (HW + 15 < X < W - HW - 15 and HW + 4 < Y < H - HW - 4): continue
    if L[Y, X].sum() == 0: continue
    blk = L[Y - HW:Y + HW + 1, X - HW:X + HW + 1]
    best = None; errs = {}
    for dy in range(-3, 4):
        for dx in range(-16, 17):
            r = R[Y + dy - HW:Y + dy + HW + 1, X + dx - HW:X + dx + HW + 1]
            errs[(dy, dx)] = float(np.abs(blk - r).sum())
    (bdy, bdx) = min(errs, key=errs.get)
    # sub-pixel along dx at the best dy
    e = [errs[(bdy, d)] for d in (bdx - 1, bdx, bdx + 1)] if -16 < bdx < 16 else None
    sub = bdx + (0.5 * (e[0] - e[2]) / (e[0] - 2 * e[1] + e[2]) if e and (e[0] - 2 * e[1] + e[2]) > 0 else 0)
    depth = wl
    res.append((name, p, xr - xl, yr - yl, sub, bdy, depth))
    say(f"  atom {name} at {p}: depth {depth:6.2f}  predicted dx {xr-xl:+6.2f} dy {yr-yl:+.3f}   measured dx {sub:+6.2f} at dy {bdy:+d}")
pred = np.array([r[2] for r in res]); meas = np.array([r[4] for r in res]); dys = np.array([r[5] for r in res])
e = meas - pred
say(f"{len(res)} atoms: measured - predicted: mean {e.mean():+.2f}, median abs {np.median(np.abs(e)):.2f} px, max abs {np.abs(e).max():.2f}; correlation {np.corrcoef(pred, meas)[0,1]:.3f}")
say(f"best vertical shift of the match: {sorted(set(dys.tolist()))} (0 = no vertical difference); predicted vertical difference max {max(abs(r[3]) for r in res):.4f} px")
near = pred < -0.5; far = pred > 0.5; zero = np.abs(pred) <= 0.5
for nm, m in (("nearer than the centre (pred < -0.5)", near), ("farther than the centre (pred > +0.5)", far), ("at the centre's depth (|pred| <= 0.5)", zero)):
    if m.sum(): say(f"  {nm}: {int(m.sum())} atoms, predicted mean {pred[m].mean():+.2f}, measured mean {meas[m].mean():+.2f}")
diff = np.abs(L - R).sum(axis=2) > 0
v = np.zeros((H, W), bool); v[oy:oy + Hv, ox:ox + Wv] = True
say(f"pixels that differ between the eyes: {int(diff.sum())} of {H*W}; outside the molecule viewer (tabs, text, statistics, buttons): {int((diff & ~v).sum())}")
open(f"{case}/analysis.txt", "w").write("\n".join(out) + "\n")
