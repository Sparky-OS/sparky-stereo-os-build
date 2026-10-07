#!/bin/sh
# usage: analyze-all.sh <evidence/proof dir>   the numbers of Part 3c (run from part3c/proof; needs python3, numpy, PIL)
E=${1:-../evidence/proof}
H=$(cd "$(dirname "$0")" && pwd)
echo "== colour management: the image description of every surface that got one (wp_color_management_surface_v1), per mode"
for m in rec709g22 rec709g10 rec2020pq; do
  echo "-- mode $m"
  for k in on mono off; do echo "  [$k] $( [ $k = on ] && echo 'stereo pair, session started for stereo' || { [ $k = mono ] && echo 'normal document, session started for stereo' || echo 'stereo off, native canvas surface'; } )"; python3 $H/cmdesc.py $E/c-$k-$m/run.client.log | sed 's/^/      /'; done
done
echo "== the layer's description against the native canvas surface's, per mode (the subsurface lines)"
for m in rec709g22 rec709g10 rec2020pq; do
  a=$(python3 $H/cmdesc.py $E/c-on-$m/run.client.log | grep subsurface | sed 's/^wl_surface#[0-9]* //' | sort -u); b=$(python3 $H/cmdesc.py $E/c-mono-$m/run.client.log | grep subsurface | sed 's/^wl_surface#[0-9]* //' | sort -u); c=$(python3 $H/cmdesc.py $E/c-off-$m/run.client.log | grep subsurface | sed 's/^wl_surface#[0-9]* //' | sort -u)
  [ "$a" = "$c" ] && [ "$b" = "$c" ] && echo "$m: stereo layer == mono layer == native canvas surface: $c" || { echo "$m: DIFFERENT"; echo "  stereo layer: $a"; echo "  mono layer:   $b"; echo "  native:       $c"; }
done
echo "== the layer surfaces are declared / not declared (stereo pair run)"; python3 $H/wlproof.py $E/c-on-rec709g22/run.client.log
echo "== eye checks in every mode (stereo pair): differing pixels outside the canvas, mean colour of each eye in the canvas rectangle"
for m in rec709g22 rec709g10 rec2020pq; do python3 - $E/c-on-$m/run.window.png $m <<'PY'
import sys, numpy as np
from PIL import Image
a = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(int); W = a.shape[1] // 2
L, R = a[:, :W], a[:, W:]
x, y, w, h = 75, 117, 498, 402
ins = np.zeros(L.shape[:2], bool); ins[y:y+h, x:x+w] = True
d = (L != R).any(axis=2)
print('%s: window %dx%d, one eye %d wide; outside the canvas %d differing pixels; left eye mean RGB %s, right eye %s' % (sys.argv[2], a.shape[1], a.shape[0], W, (d & ~ins).sum(), L[ins].mean(0).round(0).astype(int).tolist(), R[ins].mean(0).round(0).astype(int).tolist()))
PY
done
echo "== stereo pair, default mode (GPU, no shim)"; python3 $H/analyze_p3.py $E/s-pair/run.window.png 75 117 498 402
echo "== popup palette over the stereo canvas"; python3 $H/analyze_overlay.py $E/s-pair/run.screen.png $E/s-palette/run.screen.png
echo "== 16-bit ramp, stereo document (run.1 left eye, run.2 right eye)"; python3 $H/analyze2.py $E/s-ramp/run | grep -E "^---|1/256"
echo "== 16-bit ramp, normal document, session started for stereo"; python3 $H/analyze2.py $E/m-ramp/run | grep -E "^---|1/256"
echo "== 16-bit ramp, normal document, stereo off, this package and the Part 1 package (run.1 is the canvas's surface)"; python3 $H/analyze2.py $E/off-ramp/run | sed -n '/run.1.txt/,$p' | grep -E "^---|1/256"; python3 $H/analyze2.py $E/off-ramp-old/run | sed -n '/run.1.txt/,$p' | grep -E "^---|1/256"
echo "== stereo off, this package against the Part 1 package: the pair document"; python3 - $E <<'PY'
import sys, numpy as np
from PIL import Image
E = sys.argv[1]
for k in ('window', 'screen'):
    a = np.asarray(Image.open('%s/off-new/run.%s.png' % (E, k)).convert('RGB')).astype(int)
    b = np.asarray(Image.open('%s/off-old/run.%s.png' % (E, k)).convert('RGB')).astype(int)
    print('%s capture %s: differing pixels %s' % (k, a.shape[1::-1] if a.shape == b.shape else (a.shape, b.shape), int((a != b).any(axis=2).sum()) if a.shape == b.shape else 'sizes differ'))
PY
echo "== two documents, the normal one's tab clicked"; head -2 $E/s-switch/run.capture.txt
echo "== Qt's xcb platform"; python3 $H/analyze_p3.py $E/s-xcb/run.window.png 72 87 498 402 | head -5
