#!/usr/bin/env python3
"""classify.py RUNDIR...  : label every screenshot of a boot run by simple pixel statistics and print one line per run.

Labels (checked by eye on contact sheets, see REPORT):
  black     mean brightness < 4
  desktop   a white window on the blue Plasma background (white fraction 4 to 60 %, window rows in the middle), or
            Sparky Stereo OS's: a bright frame with the panel along the bottom (standard deviation of the bottom 5 % over 55)
  menu      boot menu: text near the top and near the bottom of a blue frame
  splash    blue frame with white pixels only in the middle (Plymouth logo and spinner)
  text      white text on black (firmware console, error text)
  garbled   a picture with a wrong stride or format: the mean horizontal pixel step is far above any desktop's
  other
Output: run name, the time of the first menu / splash / desktop frame, the label of the last frame, and the
sequence of labels (one letter per frame: B black, M menu, S splash, D desktop, T text, ? other).
"""
import json, os, sys
import numpy as np
from PIL import Image

LETTER = {"black": "B", "menu": "M", "splash": "S", "desktop": "D", "text": "T", "garbled": "G", "other": "?"}


def label(path):
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.int16)
    h, w, _ = im.shape
    mean = im.mean()
    if mean < 4:
        return "black"
    step = np.abs(np.diff(im.mean(axis=2), axis=1)).mean()
    if step > 25:
        return "garbled"
    white = (im.min(axis=2) >= 190)
    wf = white.mean()
    blue = ((im[:, :, 2] > 60) & (im[:, :, 0] < 60) & (im[:, :, 1] < 60)).mean()
    rows = np.where(white.any(axis=1))[0]
    top = white[: int(h * 0.12)].any()
    bottom = white[int(h * 0.86):].any()
    mid_only = len(rows) and rows.min() > h * 0.25 and rows.max() < h * 0.75
    if blue < 0.15 and mean < 40:
        return "text" if wf > 0 else "black"
    if 0.04 <= wf <= 0.60 and blue > 0.05 and rows.min() < h * 0.45 and not (top and bottom and wf < 0.04):
        return "desktop"
    # Sparky Stereo OS's live session: the panel along the bottom (icons on a dark strip) on a bright frame,
    # whichever welcome window is open (measured: desktop 62 to 64, menus and splash 41 to 42, bare wallpaper 32)
    if mean > 60 and im[int(h * 0.95):].std() > 55:
        return "desktop"
    if blue > 0.35 and top and bottom and wf < 0.04:
        return "menu"
    if blue > 0.35 and mid_only:
        return "splash"
    return "other"


def tkey(name):
    # m10 -> 10, t53 -> 53, menu2 -> 2
    d = "".join(c for c in name if c.isdigit())
    return (0 if name.startswith("m") else 1, int(d) if d else 0)


def main():
    for d in sys.argv[1:]:
        d = d.rstrip("/")
        if not os.path.isdir(d):
            continue
        frames = sorted([f[:-4] for f in os.listdir(d) if f.endswith(".png") and f != "sheet.png"], key=tkey)
        times = {}
        try:
            r = json.load(open(os.path.join(d, "result.json")))
            for s in r.get("steps", []):
                if "shot" in s:
                    times[s["shot"]] = s["t"]
        except Exception:
            r = {}
        labs = [(f, label(os.path.join(d, f + ".png"))) for f in frames]
        first = {}
        for f, l in labs:
            first.setdefault(l, times.get(f))
        seq = "".join(LETTER[l] for _, l in labs)
        last = labs[-1][1] if labs else "-"
        print("%-34s menu@%-6s splash@%-6s desktop@%-6s last=%-8s %s" % (
            os.path.basename(d), first.get("menu"), first.get("splash"), first.get("desktop"), last, seq))


main()
