#!/usr/bin/env python3
"""jmol_analyze.py RUNDIR [SHOT]: Jmol's six atoms measured from the compositor's capture.

The 3D area is the declared window (props.json); without one (Debian's jmol, Enable 3D off) the whole eye is searched.
Each atom's centroid in each eye (flat CPK colours). Disparity = right eye minus left eye (negative: in front).
Prediction (orthographic, perspectiveDepth off): Jmol turns the right eye's picture by -angle about the vertical axis
through the centre of rotation (TransformManager.getStereoRotationMatrix, setAsYRotation(-stereoRadians)), so
disparity = s (x (cos a - 1) - z sin a) for an atom at (x, z) from the centre (Angstrom), s the pixels per Angstrom
measured in the left eye from sulfur (x = 3) and chlorine (x = -3). Prints one JSON line."""
import json, math, sys
import numpy as np
from PIL import Image

run = sys.argv[1]; shot = sys.argv[2] if len(sys.argv) > 2 else 'shot1.png'
ATOMS = {'O': ((0, 0, 3), (255, 13, 13)), 'N': ((0, 0, -3), (48, 80, 248)), 'S': ((3, 0, 0), (255, 255, 48)),
         'Cl': ((-3, 0, 0), (31, 240, 31)), 'P': ((0, 3, 0), (255, 128, 0)), 'Na': ((3, 3, 3), (171, 92, 242))}
a = np.asarray(Image.open(f'{run}/{shot}').convert('RGB')).astype(int)
h, w, _ = a.shape
out = {'capture': [w, h], 'stereo': w == 3840}
props = json.load(open(f'{run}/props.json'))
declared = [x for x in props.get('windows', []) if x['props'].get('_KDE_NET_WM_STEREO_CONTENT') == [3]]
out['declared'] = [{'id': x['id'], 'abs': x['abs'], 'geom': x['geom'], 'one_view': x['props'].get('_KDE_NET_WM_STEREO_CONTENT_ONE_VIEW_SIZE'),
                    'limits': x['props'].get('_KDE_NET_WM_STEREO_DEPTH_LIMITS')} for x in declared]
out['children_listed'] = [x['props'].get('_KDE_NET_WM_STEREO_CONTENT_CHILDREN') for x in props.get('windows', []) if '_KDE_NET_WM_STEREO_CONTENT_CHILDREN' in x['props']]
eyes = [a[:, :1920], a[:, 1920:]] if out['stereo'] else [a]
if declared:
    x0, y0 = out['declared'][0]['abs']; aw, ah = out['declared'][0]['one_view'] or [out['declared'][0]['geom'][2] // 2, out['declared'][0]['geom'][3]]
    area = (slice(y0, y0 + ah), slice(x0, x0 + aw)); out['area'] = [x0, y0, aw, ah]
else:
    area = (slice(0, h), slice(0, 1920))
cents = []
for eye in eyes:
    c = {}
    for name, (p, colour) in ATOMS.items():
        mask = np.all(np.abs(eye[area] - np.array(colour)) < 12, axis=2)
        ys, xs = np.nonzero(mask)
        c[name] = (float(xs.mean()), float(ys.mean()), int(mask.sum())) if len(xs) > 30 else None
    cents.append(c)
out['found_left'] = {k: (v[2] if v else 0) for k, v in cents[0].items()}
if len(eyes) == 2:
    diff = np.any(eyes[0] != eyes[1], axis=2)
    inside = np.zeros(diff.shape, bool); inside[area] = True
    out['differing_inside'] = int((diff & inside).sum()); out['differing_outside'] = int((diff & ~inside).sum())
    L, R = cents
    if L['S'] and L['Cl']:
        s = (L['S'][0] - L['Cl'][0]) / 6.0; ang = math.radians(float(sys.argv[3]) if len(sys.argv) > 3 else 5.0)
        out['px_per_angstrom'] = round(s, 3)
        rows = {}
        for name, (p, _) in ATOMS.items():
            if L[name] and R[name]:
                x, y, z = p
                rows[name] = {'measured': round(R[name][0] - L[name][0], 3), 'vertical': round(R[name][1] - L[name][1], 3),
                              'predicted': round(s * (x * (math.cos(ang) - 1) - z * math.sin(ang)), 3)}
        out['atoms'] = rows
        # the left eye's picture is the unrotated view: chlorine left of sulfur, oxygen and nitrogen at the centre column
        out['left_eye_unrotated'] = bool(L['Cl'][0] < L['S'][0] and abs(L['O'][0] - L['N'][0]) < 1.0) if L['O'] and L['N'] else None
print(json.dumps(out))
