#!/usr/bin/python3 -I
"""deep_judge.py RESULTS LAYOUT...: judges the deep colour steps (rig/guest/deep-steps.sh). For each layout (2d, sbs-half) and each ramp
client the frame the output scanned out was read at 16 bits per channel (a binary PPM, maxval 65535); the judge counts the distinct
values of the red channel inside the eye's columns that fall in the band the client drew (256 values of a 16 bit channel):
  shm 16 bit  (wl_shm AB48 or XB48, the ramp 0x8000..0x80ff): expected 256 levels in each eye, the holds line is 200 or more
              (a path that keeps 16 bits shows them all; at 10 bits the band holds 4, at 8 bits 1)
  shm 10 bit  (XR30) and shm 8 bit (XR24): printed for the record (4 and 1 are what the clients draw; a count above them
              would mean the compositor invented levels)
  stereo      (a declared two view EGL surface with 16 bit fixed point channels; the left view the ramp 0x8000.., the right
              view 0x9000..): 200 or more levels of the left ramp in the left eye and of the right ramp in the right eye, none
              of the other ramp in either eye. In a 2D mode the left view only: the right ramp must not appear.
The grey check: red, green and blue of every counted pixel are within 2 codes of each other (the half side by side filter rounds each channel on its own).
Exit 0 every layout holds, 1 one does not, 77 the guest did not run to the compositor (no frames), 2 a crash."""
import os
import sys
import traceback


def _crash(*a):
    traceback.print_exception(*a)
    os._exit(2)


sys.excepthook = _crash

import array
import re

results = sys.argv[1]
layouts = sys.argv[2:]
run = os.path.dirname(os.path.abspath(results))
lines = [l.strip() for l in open(results, errors="replace") if l.startswith("STEREO|")]
LEVELS_OK = 200


def read_rows(path, ys):
    """The rows ys of a binary P6 PPM at 16 bits per channel: {y: array('H') of width*3 samples, native order}."""
    with open(path, "rb") as f:
        tok = []
        while len(tok) < 4:
            line = f.readline()
            tok += line.split()
        w, h, maxval = int(tok[1]), int(tok[2]), int(tok[3])
        if tok[0] != b"P6" or maxval != 65535:
            raise ValueError("%s: not a 16 bit P6 PPM" % path)
        base = f.tell()
        out = {}
        for y in ys:
            f.seek(base + y * w * 6)
            a = array.array("H")
            a.frombytes(f.read(w * 6))
            if sys.byteorder == "little":
                a.byteswap()
            out[y] = a
    return w, h, out


def count(path, x0, x1, lo, hi):
    """Distinct red values in [lo, hi] inside columns x0..x1 over every 20th row; and the pixels in the band that are not grey."""
    w, h = read_rows(path, [0])[:2]
    w, h, rows = read_rows(path, range(0, h, 20))
    seen = set()
    notgrey = 0
    for a in rows.values():
        for x in range(x0, x1):
            r, g, b = a[3 * x], a[3 * x + 1], a[3 * x + 2]
            if lo <= r <= hi:
                seen.add(r)
                if max(r, g, b) - min(r, g, b) > 2:
                    notgrey += 1
    return len(seen), notgrey, w, h


if not any(l.startswith("STEREO|deep|kwin exit") for l in lines):
    print("SKIP: the deep steps wrote no 'kwin exit' line (the guest or the compositor did not start): %s" % "; ".join(lines[-3:]))
    sys.exit(77)
ok = True
for lay in layouts:
    skip = [l for l in lines if l.startswith("STEREO|skip|deep/%s|" % lay)]
    if skip:
        print("%-9s %s: nothing to show" % (lay, skip[0].split("|", 3)[3]))
        ok = False
        continue
    first = None
    for tag in ("shm-auto", "shm-xr30", "shm-xr24", "stereo"):
        name = "%s-%s" % (lay, tag)
        ppm = os.path.join(run, name + ".ppm")
        clog = os.path.join(run, "client-%s.log" % name)
        client = open(clog, errors="replace").read().replace("\n", "; ") if os.path.exists(clog) else "no client log"
        if not os.path.exists(ppm):
            print("%-9s %-9s no frame (%s)" % (lay, tag, client[:140]))
            if tag in ("shm-auto", "stereo"):
                ok = False
            continue
        w, h = read_rows(ppm, [0])[:2]
        eyes = [(0, w)] if lay == "2d" else [(0, w // 2), (w // 2, w)]
        names = ["the picture"] if lay == "2d" else ["left eye", "right eye"]
        if tag == "stereo":
            # left ramp from 0x8000, right ramp from 0x9000
            for i, (x0, x1) in enumerate(eyes):
                mine = (0x8000, 0x80ff) if i == 0 else (0x9000, 0x90ff)
                other = (0x9000, 0x90ff) if i == 0 else (0x8000, 0x80ff)
                n, ng, _, _ = count(ppm, x0, x1, *mine)
                m, _, _, _ = count(ppm, x0, x1, *other)
                if lay == "2d":
                    good = n >= LEVELS_OK and m == 0 and ng == 0
                    print("%-9s %-9s %s: %d levels of the left view's ramp, %d of the right view's -> %s" % (lay, tag, names[i], n, m, "holds" if good else "does not hold"))
                else:
                    good = n >= LEVELS_OK and m == 0 and ng == 0
                    print("%-9s %-9s %s: %d levels of its own view's ramp, %d of the other's -> %s" % (lay, tag, names[i], n, m, "holds" if good else "does not hold"))
                ok = ok and good
        else:
            fmt = re.search(r"format (\w+) \((\d+) bits\)", client)
            bits = int(fmt.group(2)) if fmt else 0
            if not fmt:
                print("%-9s %-9s the client did not draw: %s" % (lay, tag, client[:160]))
                if tag == "shm-auto":
                    ok = False
                continue
            for i, (x0, x1) in enumerate(eyes):
                n, ng, _, _ = count(ppm, x0, x1, 0x8000, 0x80ff)
                if tag == "shm-auto":
                    good = bits == 16 and n >= LEVELS_OK and ng == 0
                    print("%-9s %-9s %s: a %d bit client, %d levels of 256 -> %s" % (lay, tag, names[i], bits, n, "holds" if good else "does not hold"))
                    ok = ok and good
                else:
                    print("%-9s %-9s %s: a %d bit client draws %d level(s), the output shows %d (for the record)" % (lay, tag, names[i], bits, 1 << (bits - 8) if bits == 10 else 1, n))
sys.exit(0 if ok else 1)
