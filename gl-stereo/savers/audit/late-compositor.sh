#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# A compositor that answers a stereo declaration late (well past the layer's one-second wait):
# KWin is held still after it has mapped the saver's window and before it reads the declaration,
# for HOLD seconds, while the saver runs. The capture must still be of a frame drawn into the
# window KWin sized for both views, and equal to the same frame without the hold.
# usage (UID 1000 in the audit image, after requalify-steps.sh setup): late-compositor.sh <scratch> [saver]
set -u
B=$1; saver=${2:-moebiusgears}; hold=${HOLD:-8}; A=$(cd "$(dirname "$0")" && pwd)
kwin() { AUDIT_TIMEOUT=120 AUDIT_LIBRARY=/usr/lib/gl-stereo/libgl-stereo.so GL_STEREO_SEPARATION=.5 REFERENCE_SEPARATION=.5 python3 "$A/run-kwin.py" "$@"; }
check() { python3 - "$1/$saver" <<'PY'
import glob, sys
import numpy as np
from PIL import Image
d = sys.argv[1]
line = [l for l in open(d + '/client.log') if l.startswith('dump logical')][-1].split()
dump = np.array(Image.open(sorted(glob.glob(d + '/frame-*.ppm'))[-1]).convert('RGB'))
kwin = np.array(Image.open(d + '/kwin.png').convert('RGB'))
ok = line[4] == '1280x360' and np.array_equal(dump, kwin) and min(dump[:, :640].std(), dump[:, 640:].std()) > 1
print(d.split('/')[-2], 'native', line[4], 'composed equal', np.array_equal(dump, kwin),
      'eye deviations %.1f %.1f' % (dump[:, :640].std(), dump[:, 640:].std()), 'PASS' if ok else 'FAIL')
sys.exit(0 if ok else 1)
PY
}
kwin "$B/plain" "$saver" > "$B/plain.log" 2>&1; check "$B/plain" || exit 1
( log=$B/held/$saver/client.log
  until grep -q 'create window=' "$log" 2>/dev/null; do sleep .001; done
  pid=$(pgrep -x "$saver"); kill -STOP "$pid"
  window=$(grep -o 'create window=[0-9]*' "$log" | head -1 | cut -d= -f2)
  export $(tr '\0' '\n' < /proc/$pid/environ | grep -E '^(DISPLAY|XAUTHORITY)=')
  until xwininfo -id "$window" 2>/dev/null | grep -q IsViewable; do sleep .005; done
  pkill -STOP -x kwin_wayland; kill -CONT "$pid"; sleep "$hold"; pkill -CONT -x kwin_wayland ) &
kwin "$B/held" "$saver" > "$B/held.log" 2>&1; wait
check "$B/held" || exit 1
grep -h 'fixture:' "$B/held/$saver/client.log"
python3 -c "import sys,numpy as np;from PIL import Image;a,b=(np.array(Image.open(p)) for p in sys.argv[1:]);print('held equals plain:',np.array_equal(a,b));sys.exit(0 if np.array_equal(a,b) else 1)" "$B/plain/$saver/kwin.png" "$B/held/$saver/kwin.png"
