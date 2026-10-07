#!/bin/sh
# usage: analyze-all.sh <evidence/proof dir>   the numbers of Part 3 from the captures (run from part3/proof; needs python3, numpy, PIL)
E=${1:-../evidence/proof}
H=$(cd "$(dirname "$0")" && pwd)
rect=$(grep -o "QRect([0-9,]* [0-9x]*)" $E/s-pair/run.client.log | head -1)
echo "canvas layer (the log, in the window's own coordinates): $rect; the window capture adds Qt's decoration margin (3, 30): rect x 75 y 117 498x402"
echo "== stereo pair (GPU, no shim)"; python3 $H/analyze_p3.py $E/s-pair/run.window.png 75 117 498 402
echo "== declarations (WAYLAND_DEBUG)"; python3 $H/wlproof.py $E/s-pair/run.client.log
echo "== popup palette over the stereo canvas"; python3 $H/analyze_overlay.py $E/s-pair/run.screen.png $E/s-palette/run.screen.png
echo "== 16-bit ramp on the stereo canvas (left eye = run.1, right eye = run.2)"; python3 $H/analyze2.py $E/s-ramp/run | sed -n '/run.1.txt/,$p'
echo "== stereo off, this package against the Part 1 package (+stereo3d1)"; python3 - $E <<'PY'
import sys, numpy as np
from PIL import Image
E = sys.argv[1]
for k in ('window', 'screen'):
    a = np.asarray(Image.open('%s/off-new/run.%s.png' % (E, k)).convert('RGB')).astype(int)
    b = np.asarray(Image.open('%s/off-old/run.%s.png' % (E, k)).convert('RGB')).astype(int)
    print('%s capture %s: differing pixels %s' % (k, a.shape[1::-1] if a.shape == b.shape else (a.shape, b.shape), int((a != b).any(axis=2).sum()) if a.shape == b.shape else 'sizes differ'))
PY
echo "== Qt's xcb platform, stereo on (as Part 2)"; python3 $H/analyze_p3.py $E/s-xcb/run.window.png 72 87 498 402 | head -5
