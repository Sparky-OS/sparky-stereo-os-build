#!/usr/bin/python3 -I
"""audio_judge.py follow|dither16 ROWS.jsonl: judges the rows the rig's proof.py wrote (a line per source rate and device).

follow    holds when, for every row, the graph and the device ran at the source's own rate (the device takes it, so
          nothing is resampled). Does not hold when any row's graph ran at another rate. Prints each row and the
          settings read from PipeWire itself (pw-metadata -n settings), never assumed.
dither16  holds when, on a 16 bit only device, every row follows the source rate, the device was opened in S16_LE and the
          sink carries triangular dither (the engine's choice for a device that takes 16 bit only).
Exit 0 holds, 1 does not hold, 77 cannot run (no rows)."""
import os
import sys
import traceback


def _crash(*a):
    traceback.print_exception(*a)
    os._exit(2)


sys.excepthook = _crash

import json
import sys

mode, path = sys.argv[1], sys.argv[2]
rows = [json.loads(l) for l in open(path) if l.startswith("{")]
if not rows:
    print("SKIP: the rig wrote no rows (the private sound session did not start)")
    sys.exit(77)
ok = True
for r in rows:
    follows = r["graph_rate"] == r["source_rate"] and r["device_rate"] == r["source_rate"] and not r["resampled"]
    line = "%s %6d Hz: graph %s, device %s %s, resampled %s, quality %s, allowed %s, clock.rate %s" % (
        r["device"], r["source_rate"], r["graph_rate"], r["device_rate"], r["device_format"], r["resampled"],
        r["stream_resample_quality"], r["settings_clock_allowed_rates"], r["settings_clock_rate"])
    if mode == "dither16":
        follows = follows and r["device_format"] == "S16_LE" and r["sink_props_dither_method"] == "triangular"
        line += ", dither %s" % r["sink_props_dither_method"]
    print(line, "->", "follows" if follows else "does not follow")
    ok = ok and follows
sys.exit(0 if ok else 1)
