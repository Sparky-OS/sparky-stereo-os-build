#!/usr/bin/env python3
"""pv_analyze.py RUNDIR [SHOT]: ParaView's two squares in a capture (far 2x2 at z=0 blue, near 0.8x0.8 at z=1 red).
For each eye: the left and right edges, top and bottom of each square's colour (in the middle band of rows, so lighting and
the square's own edges decide, not the scalar bar). Disparity = right eye minus left eye (negative: in front of the screen).
Prediction from the captured widths: f and the near depth solved from the two widths (sizes 2 and 0.8, depths d and d+1),
focal point at the box centre (D = d + 0.5, VTK's ResetCamera), VTK's shear stereo with EyeAngle 2 degrees:
disparity = 2 f tan(1 deg) (1 - D / depth). Prints one JSON line; exit 1 when the capture is not two eyes."""
import json, math, sys
import numpy as np
from PIL import Image
run = sys.argv[1]; shot = sys.argv[2] if len(sys.argv) > 2 else "shot1.png"
a = np.asarray(Image.open(f"{run}/{shot}").convert("RGB")).astype(int)
h, w, _ = a.shape
out = {"capture": [w, h], "stereo": w == 2 * 1920}
eyes = [a[:, :w // 2], a[:, w // 2:]] if out["stereo"] else [a, a]
def boxes(e):
    r, g, b = e[..., 0], e[..., 1], e[..., 2]
    red = (r > 80) & (r < 200) & (g < 50) & (b < 60)
    blue = (b > 50) & (b < 160) & (r < 45) & (g < 45)
    view = np.zeros(r.shape, bool); view[60:1045, 460:1750] = True   # the render view of the maximized window, scalar bar excluded
    red &= view; blue &= view
    res = {}
    for name, m in (("near_red", red), ("far_blue", blue)):
        cols = m.sum(axis=0); rows = m.sum(axis=1)
        # the square is the widest run: columns with many pixels, rows with many pixels
        xs = np.nonzero(cols > 0.3 * cols.max())[0]; ys = np.nonzero(rows > 0.3 * rows.max())[0]
        if len(xs) == 0:
            res[name] = None; continue
        res[name] = {"x0": int(xs.min()), "x1": int(xs.max()), "y0": int(ys.min()), "y1": int(ys.max()), "pixels": int(m.sum())}
    return res
L, R = boxes(eyes[0]), boxes(eyes[1])
out["left"], out["right"] = L, R
if L["near_red"] and L["far_blue"] and R["near_red"] and R["far_blue"]:
    disp = {}
    for k in ("near_red", "far_blue"):
        disp[k] = {"x0": R[k]["x0"] - L[k]["x0"], "x1": R[k]["x1"] - L[k]["x1"], "y0": R[k]["y0"] - L[k]["y0"], "y1": R[k]["y1"] - L[k]["y1"]}
    out["disparity"] = disp
    wn = (L["near_red"]["x1"] - L["near_red"]["x0"] + R["near_red"]["x1"] - R["near_red"]["x0"]) / 2 + 1
    wf = (L["far_blue"]["x1"] - L["far_blue"]["x0"] + R["far_blue"]["x1"] - R["far_blue"]["x0"]) / 2 + 1
    rr = (wf / wn) * (0.8 / 2.0)
    if 0 < rr < 1:
        dn = rr / (1 - rr); f = wn * dn / 0.8; D = dn + 0.5
        k = 2 * f * math.tan(math.radians(1.0))
        out["prediction"] = {"f_px": round(f, 1), "near_depth": round(dn, 4), "D": round(D, 4),
                             "near": round(k * (1 - D / dn), 3), "far": round(k * (1 - D / (dn + 1)), 3)}
        meas_n = (disp["near_red"]["x0"] + disp["near_red"]["x1"]) / 2; meas_f = (disp["far_blue"]["x0"] + disp["far_blue"]["x1"]) / 2
        out["measured"] = {"near": meas_n, "far": meas_f}
diff = np.any(eyes[0] != eyes[1], axis=2)
out["differing_pixels"] = int(diff.sum())
if diff.any():
    ys, xs = np.nonzero(diff); out["differing_bbox"] = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
    vm = np.zeros(diff.shape, bool); vm[60:1045, 460:1750] = True
    out["differing_outside_view"] = int((diff & ~vm).sum())
print(json.dumps(out))
sys.exit(0 if out["stereo"] else 1)
