"""Kubrick stereo capture analysis. usage: analyze-kubrick.py <case-dir> <separation-percent> [--out file]
Reads window.png (full side by side, left first) and geom.txt (viewport, projection, cube matrices, cubie centres
logged by tests/kubrick-shim.c for the frame on screen). Ground truth: ray-cast of each cube's box from the left
eye camera -> depth t -> predicted right-minus-left disparity  d = (W/2)*P0*(eR-eL)*(1/D - 1/t)  (pixels, + = behind)."""
import sys, numpy as np
from PIL import Image
case, sep = sys.argv[1], float(sys.argv[2])
img = np.array(Image.open(f"{case}/window.png").convert("RGB")).astype(float)
H, W2, _ = img.shape; W = W2 // 2
L, R = img[:, :W], img[:, W:]
geom = open(f"{case}/geom.txt").read().splitlines()
vp = [int(v) for v in geom[0].split()[1:]]
proj = np.array([float(v) for v in geom[1].split()[1:]]).reshape(4, 4).T  # column-major -> matrix
P0, P5 = proj[0, 0], proj[1, 1]
cubes = []; cur = None; after_m = False; rot_after = 0
for ln in geom[2:]:
    t = ln.split()
    if t[0] == "T" and abs(float(t[3]) + 5.0) < 1e-6 and (cur is None or cur.get("M")) and not (cur and not cur.get("done") and False):
        # a cube position translate (z == -5 exactly) starts a new cube
        if cur is None or len(cur["M"]) == 2:
            cur = {"pos": [float(v) for v in t[1:]], "M": [], "T": [], "R": 0}; cubes.append(cur); continue
    if cur is None: continue
    if t[0] == "M": cur["M"].append(np.array([float(v) for v in t[1:]]).reshape(4, 4).T)
    elif t[0] == "T" and len(cur["M"]) == 2: cur["T"].append([float(v) for v in t[1:]])
    elif t[0] == "R" and len(cur["M"]) == 2: cur["R"] += 1
D = 5.0
e = 0.5 * D * sep / 100.0                       # half separation
eL, eR = -e, +e
out = []
def say(s): print(s); out.append(s)
say(f"image {W2}x{H} (eye {W}x{H}), GL viewport {vp[2]}x{vp[3]}, P0={P0:.4f}, separation {sep}% of {D} -> eyes {2*e:.3f} apart")
say(f"cubes in frame: {len(cubes)}; slices turning (glRotatef inside the cubie loop): {[c['R'] for c in cubes]}")
# the GL widget's top row in the window: first row after the toolbar that is not the grey of the widgets
col = L[:, 6]
oy = next(y for y in range(20, H) if abs(col[y] - 239).max() > 40 and abs(col[y] - 239).max() < 255 and L[y, 6:10].std() < 40 and col[y].sum() < 600)
# refine: the widget is vp height tall; pick oy so that the strip above is the toolbar/menu and rows are identical in both eyes
oy = max(range(max(0, H - vp[3] - 60), H - vp[3] + 1), key=lambda y: -np.abs(L[y - 3:y, :] - R[y - 3:y, :]).sum() if y >= 3 else -1e9) if False else oy
say(f"GL widget top row in the window: {oy} (window height {H})")
Wv, Hv = vp[2], vp[3]
MARGIN = False
def cast(c, px, py, ex):
    """depth t of the first hit of the cube's box for the pixel (px, py) (GL convention, py from the bottom) seen from camera x=ex"""
    M = c["M"][1]; Tl = np.array(c["T"]); h = np.abs(Tl).max(axis=0) * 1.0
    xn = 2 * (px + 0.5) / Wv - 1; yn = 2 * (py + 0.5) / Hv - 1
    o = np.array([ex, 0, 0]); d = np.array([xn / P0 - ex / D, yn / P5, -1.0])
    Mi = np.linalg.inv(M); o2 = (Mi @ np.append(o, 1))[:3]; d2 = (Mi @ np.append(d, 0))[:3]
    h = h * (1.0 + (0.10 if MARGIN else 0.0))
    t0, t1 = -1e9, 1e9
    for k in range(3):
        if abs(d2[k]) < 1e-12:
            if abs(o2[k]) > h[k]: return None
            continue
        a, b = (-h[k] - o2[k]) / d2[k], (h[k] - o2[k]) / d2[k]
        if a > b: a, b = b, a
        t0, t1 = max(t0, a), min(t1, b)
    if t0 > t1 or t0 < 0: return None
    return t0   # depth = distance along d (d.z = -1)
# sample the cubes: points on the left image, texture, block match
RNG = 10
def block_disp(y, x, r=7, rng=None):
    rng = rng or RNG
    a = L[y - r:y + r + 1, x - r:x + r + 1]
    if a.std() < 12: return None
    best = None; res = []
    for dy in (-2, -1, 0, 1, 2):
        row = []
        for dx in range(-rng, rng + 1):
            xx = x + dx
            if xx - r < 0 or xx + r + 1 > W or y + dy - r < 0 or y + dy + r + 1 > H: row.append(1e18); continue
            row.append(np.abs(R[y + dy - r:y + dy + r + 1, xx - r:xx + r + 1] - a).sum())
        res.append(row)
    res = np.array(res)
    r0 = res[2]; ix0 = int(r0.argmin()); far = np.abs(np.arange(len(r0)) - ix0) > 2
    if not far.any() or r0[far].min() < 1.5 * r0[ix0] + 1e-6 * r0.size: return None   # ambiguous (repeated pattern): the best match must be clearly the best
    iy, ix = np.unravel_index(res.argmin(), res.shape)
    dxs = ix - rng
    if 0 < ix < res.shape[1] - 1:
        s0, s1, s2 = res[iy, ix - 1], res[iy, ix], res[iy, ix + 1]
        den = s0 - 2 * s1 + s2
        sub = 0.5 * (s0 - s2) / den if den > 0 else 0
    else: sub = 0
    return dxs + sub, iy - 2, res[iy, ix] / a.size, res.min(axis=1) / a.size
rows = []; dyc = []
# search bound: a little more than the largest disparity the geometry allows
RNG = int(np.ceil(1.3 * (Wv / 2) * P0 * 2 * e * 0.1)) + 2
for ci, c in enumerate(cubes):
    for py in range(8, Hv - 8, 7):
        for px in range(8, Wv - 8, 7):
            t = cast(c, px, py, eL)
            if t is None: continue
            # stay clear of the silhouette (the block would take in background): all four neighbours 8 px away must hit too
            if any(cast(c, px + a, py + b, eL) is None for a, b in ((9, 0), (-9, 0), (0, 9), (0, -9))): continue
            x = px; y = oy + (Hv - 1 - py)
            m = block_disp(y, x)
            if m is None: continue
            pred = (Wv / 2) * P0 * (eR - eL) * (1 / D - 1 / t)
            rows.append((ci, px, py, t, pred, m[0], m[1], m[2])); dyc.append(m[3])
rows = np.array(rows)
say(f"block-matched points on the cubes: {len(rows)}")
if len(rows):
    pred, meas, dy = rows[:, 4], rows[:, 5], rows[:, 6]
    ok = np.abs(meas - pred) < 3
    say(f"predicted disparity range {pred.min():+.2f} .. {pred.max():+.2f} px; measured {meas.min():+.2f} .. {meas.max():+.2f} px")
    say(f"measured - predicted: mean {np.mean(meas-pred):+.2f}, mean abs {np.mean(np.abs(meas-pred)):.2f}, median abs {np.median(np.abs(meas-pred)):.2f} px; within 1 px: {np.mean(np.abs(meas-pred)<1)*100:.0f}%, within 2 px: {np.mean(np.abs(meas-pred)<2)*100:.0f}%")
    say(f"correlation measured vs predicted: {np.corrcoef(pred, meas)[0,1]:.3f}")
    dyc = np.array(dyc).mean(axis=0)
    say("mean block error (per pixel) when the match may move by dy rows = -2,-1,0,+1,+2: " + ", ".join(f"{v:.2f}" for v in dyc) + f"  -> lowest at dy={int(np.argmin(dyc))-2}")
    near = pred < -1.0; far = pred > 1.0; tgt = np.abs(pred) <= 0.5
    for nm, m in (("near (t < D)", near), ("far (t > D)", far), ("at the target distance (|pred| <= 0.5)", tgt)):
        if m.sum(): say(f"  {nm}: {int(m.sum())} points, predicted mean {pred[m].mean():+.2f}, measured mean {meas[m].mean():+.2f} px")
# the 2D parts: everything outside the cubes' boxes (dilated) must be identical in both eyes
mask = np.zeros((H, W), bool); MARGIN = True   # the stickers stand 1% of a cubie off the box: widen it a little for the mask only
for c in cubes:
    for py in range(0, Hv):
        for px in range(0, Wv, 2):
            if cast(c, px, py, eL) is not None or cast(c, px, py, eR) is not None:
                y = oy + (Hv - 1 - py); mask[max(0, y - 2):y + 3, max(0, px - 12):px + 14] = True
diff = np.abs(L - R).sum(axis=2) > 0
ys, xs = np.nonzero(diff & ~mask)
if len(ys): say(f"  outside-silhouette differing pixels sit at x {xs.min()}..{xs.max()}, rows {ys.min()}..{ys.max()} (window rows; GL widget rows {oy}..{oy+Hv-1})")
say(f"pixels that differ between the eyes: {int(diff.sum())} of {H*W}; of them outside the cubes' silhouettes (menus, toolbar, status bar, background picture, labels): {int((diff & ~mask).sum())}")
# window-level numbers
open(f"{case}/analysis.txt", "w").write("\n".join(out) + "\n")
