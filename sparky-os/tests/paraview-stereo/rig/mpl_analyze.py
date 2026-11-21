#!/usr/bin/env python3
"""mpl_analyze.py RUNDIR [SHOT] [LIMITS_SUNK,POPPED]: one Matplotlib case measured from the compositor's capture.

The 3D area is the declared window (props.json, _KDE_NET_WM_STEREO_CONTENT): its absolute place, one view wide.
Markers: centroid of each colour in each eye inside the area; disparity = right eye minus left eye (negative in front of
the screen), against the prediction b x per_offset (predict.json and the module's trace of b). Block matching (17 x 17,
sum of absolute differences along the same row, a parabola for the sub-pixel) over the textured part of the area gives
the range, the share inside the limits and the share within half a pixel of the screen. Pixels that differ between the
eyes outside the area are counted. Exported files: the PNS chunks and the JPS block. Prints one JSON line."""
import io, json, struct, sys, zlib
import numpy as np
from PIL import Image

run = sys.argv[1]
shot = sys.argv[2] if len(sys.argv) > 2 else 'shot1.png'
limits = tuple(float(v) for v in sys.argv[3].split(',')) if len(sys.argv) > 3 else None
a = np.asarray(Image.open(f'{run}/{shot}').convert('RGB')).astype(int)
h, w, _ = a.shape
out = {'capture': [w, h], 'stereo': w == 3840}
props = json.load(open(f'{run}/props.json'))
declared = [x for x in props.get('windows', []) if x['props'].get('_KDE_NET_WM_STEREO_CONTENT') == [3]]
out['declared'] = [{'id': x['id'], 'abs': x['abs'], 'geom': x['geom'], 'one_view': x['props'].get('_KDE_NET_WM_STEREO_CONTENT_ONE_VIEW_SIZE'),
                    'limits': x['props'].get('_KDE_NET_WM_STEREO_DEPTH_LIMITS')} for x in declared]
out['children_listed'] = [x['props'].get('_KDE_NET_WM_STEREO_CONTENT_CHILDREN') for x in props.get('windows', []) if '_KDE_NET_WM_STEREO_CONTENT_CHILDREN' in x['props']]
trace = [json.loads(l.split('trace: ', 1)[1]) for l in open(f'{run}/mpl.log') if 'stereo-matplotlib trace: ' in l]
out['trace_last'] = trace[-1] if trace else None
out['told'] = [l.strip() for l in open(f'{run}/mpl.log') if l.startswith('stereo-matplotlib: ')]
if not out['stereo'] or not declared:
    print(json.dumps(out)); sys.exit(0)
L, R = a[:, :1920], a[:, 1920:]
ax0, ay0 = out['declared'][0]['abs']; aw, ah = out['declared'][0]['one_view'] or [out['declared'][0]['geom'][2] // 2, out['declared'][0]['geom'][3]]
area = (slice(ay0, ay0 + ah), slice(ax0, ax0 + aw))
diff = np.any(L != R, axis=2); inside = np.zeros(diff.shape, bool); inside[area] = True
out['differing_inside'] = int((diff & inside).sum()); out['differing_outside'] = int((diff & ~inside).sum())
pred = json.load(open(f'{run}/predict.json'))
b = trace[-1]['offsets'][0][1] if trace and trace[-1]['offsets'] else None
out['b'] = b
res = {}
for name, m in pred['markers'].items():
    target = (np.array(m['colour']) * 255).astype(int)
    cs = []
    for eye in (L, R):
        sub = eye[area]
        mask = np.all(np.abs(sub - target) < 45, axis=2)
        ys, xs = np.nonzero(mask)
        cs.append((xs.mean(), ys.mean(), int(mask.sum())) if len(xs) else (np.nan, np.nan, 0))
    res[name] = {'measured': round(cs[1][0] - cs[0][0], 3), 'vertical': round(cs[1][1] - cs[0][1], 3), 'pixels': [cs[0][2], cs[1][2]],
                 'predicted': round(b * m['per_offset'], 3) if b is not None else None}
out['markers'] = res
# block matching over the textured area, the same rows only
gl, gr = L[area].mean(axis=2), R[area].mean(axis=2)
B, S, step = 8, 24, 12
d_list = []
for y in range(B + 2, gl.shape[0] - B - 2, step):
    for x in range(B + S + 2, gl.shape[1] - B - S - 2, step):
        blk = gl[y - B:y + B + 1, x - B:x + B + 1]
        if blk.std() < 6:
            continue
        costs = np.array([np.abs(gr[y - B:y + B + 1, x - B + s:x + B + 1 + s] - blk).mean() for s in range(-S, S + 1)])
        k = int(costs.argmin())
        if 0 < k < len(costs) - 1 and costs[k] < 6:
            den = costs[k - 1] - 2 * costs[k] + costs[k + 1]
            d_list.append(k - S + (0.5 * (costs[k - 1] - costs[k + 1]) / den if den > 0 else 0))
d = np.array(d_list)
if len(d):
    out['blocks'] = len(d); out['range_1_99'] = [round(float(np.percentile(d, 1)), 2), round(float(np.percentile(d, 99)), 2)]
    out['min_max'] = [round(float(d.min()), 2), round(float(d.max()), 2)]
    out['share_within_half_px'] = round(float((np.abs(d) <= 0.5).mean()), 3)
    lim = limits or (tuple(trace[-1]['limits']) if trace and trace[-1]['limits'] else None)
    if lim:
        out['limits_used'] = lim
        out['share_inside_limits_0.25px'] = round(float(((d <= lim[0] + 0.25) & (d >= -lim[1] - 0.25)).mean()), 4)
# exported files
def chunks(data):
    pos, kinds = 8, []
    while pos < len(data):
        n, k = struct.unpack('>I4s', data[pos:pos + 8]); body = data[pos + 8:pos + 8 + n]
        ok = zlib.crc32(k + body) & 0xffffffff == struct.unpack('>I', data[pos + 8 + n:pos + 12 + n])[0]
        kinds.append((k.decode(), ok, body[:1].hex() if k == b'sTER' else None)); pos += 12 + n
    return kinds
try:
    pns = open(f'{run}/figure.pns', 'rb').read()
    out['pns'] = {'chunks': [k for k, ok, _ in chunks(pns)][:4], 'crc_ok': all(ok for _, ok, _ in chunks(pns)),
                  'sTER': [v for k, _, v in chunks(pns) if k == 'sTER'], 'size': Image.open(io.BytesIO(pns)).size}
except OSError:
    out['pns'] = None
try:
    jps = open(f'{run}/figure.jps', 'rb').read(); i = jps.find(b'\xff\xe3')
    out['jps'] = {'app3': jps[i + 4:i + 12].decode('latin-1') if i > 0 else None,
                  'descriptor': hex(struct.unpack('>I', jps[i + 14:i + 18])[0]) if i > 0 else None, 'size': Image.open(io.BytesIO(jps)).size}
except OSError:
    out['jps'] = None
print(json.dumps(out))
