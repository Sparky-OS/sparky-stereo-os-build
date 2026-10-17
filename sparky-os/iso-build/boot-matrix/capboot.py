#!/usr/bin/env python3
"""capboot.py DIR SECONDS [INTERVAL] : screendumps of DIR/qmp.sock's screen every INTERVAL s (default 1) for
SECONDS, kept only when the picture changed (DIR/frames/fNNNN-<t>.png); DIR/frames.txt lists time, size and
mean brightness of each kept frame. Connects to QMP for each picture (one client at a time)."""
import hashlib
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vmctl import Qmp  # noqa: E402
from PIL import Image  # noqa: E402

d, secs = sys.argv[1], float(sys.argv[2])
ivl = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
os.makedirs(os.path.join(d, "frames"), exist_ok=True)
log = open(os.path.join(d, "frames.txt"), "a")
t0 = time.time()
last = None
n = 0
tmp = os.path.join(d, "frames", ".shot.png")
while time.time() - t0 < secs:
    t = time.time() - t0
    try:
        Qmp(os.path.join(d, "qmp.sock")).cmd("screendump", filename=tmp, format="png")
        im = Image.open(tmp)
        h = hashlib.sha1(im.tobytes()).hexdigest()
    except (Exception, SystemExit) as e:  # the VM is starting, rebooting or gone
        log.write("%7.1f  no picture (%s)\n" % (t, type(e).__name__))
        log.flush()
        time.sleep(ivl)
        continue
    if h != last:
        name = "f%04d-%06.1f.png" % (n, t)
        os.replace(tmp, os.path.join(d, "frames", name))
        g = im.convert("L")
        mean = sum(g.getdata()) / (g.width * g.height)
        log.write("%7.1f  %s  %dx%d  mean %.0f\n" % (t, name, im.width, im.height, mean))
        log.flush()
        last = h
        n += 1
    time.sleep(max(0, ivl - (time.time() - t0 - t)))
