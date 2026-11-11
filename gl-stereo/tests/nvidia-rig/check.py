import sys, json
import numpy as np
sys.path.insert(0, '/rig')
from capture import capture
info, px = capture()
h, w, _ = px.shape
half = w // 2
stereo = w >= 2 * 1280
def share(a, ch):
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    m = {'red': (r > 200) & (g < 60) & (b < 60), 'blue': (b > 200) & (r < 60) & (g < 60), 'green': (g > 200) & (r < 60) & (b < 60)}[ch]
    return int(m.sum())
L, R = px[:, :half], px[:, half:]
res = dict(width=w, height=h, stereo_capture=bool(stereo), left_red=share(L, 'red'), left_blue=share(L, 'blue'),
           right_red=share(R, 'red'), right_blue=share(R, 'blue'), left_green=share(L, 'green'), right_green=share(R, 'green'))
ok = res['left_red'] > int(__import__("os").environ.get("MINPX","5000")) and res['right_blue'] > int(__import__("os").environ.get("MINPX","5000")) and res['left_blue'] < 500 and res['right_red'] < 500
res['left_nonblack'] = int((L.astype(int).sum(axis=2) > 60).sum()); res['right_nonblack'] = int((R.astype(int).sum(axis=2) > 60).sum())
res['nonblack'] = int((px.astype(int).sum(axis=2) > 60).sum())
res['verdict'] = 'GOOD' if ok else ('SWAPPED' if res['left_blue'] > int(__import__("os").environ.get("MINPX","5000")) and res['right_red'] > int(__import__("os").environ.get("MINPX","5000")) else ('RIGHT-EYE-MISSING' if res['left_red'] > int(__import__("os").environ.get("MINPX","5000")) and res['right_blue'] <= 500 else 'BAD'))
if res['verdict'] == 'BAD' and res['left_red'] > int(__import__('os').environ.get('MINPX','5000')) and res['right_green'] > int(__import__('os').environ.get('MINPX','5000')): res['verdict'] = 'GOOD-RG'
print('CHECK ' + json.dumps(res))
if len(sys.argv) > 1:
    from PIL import Image
    Image.fromarray(px).save(sys.argv[1])
