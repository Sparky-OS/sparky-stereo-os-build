#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""check.py RUN_DIR/boot1.log EXPECT.json : compares the 3D modes the kernel listed (lines BENCH|log|edid3d|EDID3D|mode|...) with what the test EDID declares
(expect.json, worked out in make_edid.py from the HDMI 1.4b rules) and checks the CRTC timings of the stereo modes. One PASS/FAIL line per check; exit status 1 on a FAIL."""
import json, re, sys
log, exp = sys.argv[1], json.load(open(sys.argv[2]))
modes, upd, add = [], None, None
for l in open(log, errors='replace'):
    m = re.search(r'EDID3D\|mode\|(.*)$', l)
    if m:
        modes.append([int(x) for x in m.group(1).strip().split('|')])
    m = re.search(r'EDID3D\|update\|rc=(-?\d+)\|is_hdmi=(\d)', l)
    if m:
        upd = (int(m.group(1)), int(m.group(2)))
    m = re.search(r'EDID3D\|add_modes\|returned=(-?\d+)', l)
    if m:
        add = int(m.group(1))
fails = 0
def res(name, ok, detail=''):
    global fails
    print('%-4s %-34s %s' % ('PASS' if ok else 'FAIL', name, detail))
    fails += 0 if ok else 1
res('edid_parsed', upd is not None and upd[0] == 0 and upd[1] == 1, 'drm_edid_connector_update rc=%s is_hdmi=%s' % (upd[0] if upd else '?', upd[1] if upd else '?'))
res('modes_added', bool(add) and add > 0, '%s modes returned, %d in the list' % (add, len(modes)))
# fields: w h refresh interlaced 3d clock htotal vtotal crtc_clock crtc_hdisplay crtc_htotal crtc_vdisplay crtc_vtotal
names = {1: 'frame packing', 4: 'side by side (full)', 7: 'top and bottom', 8: 'side by side (half)'}
got = {(m[0], m[1], m[2], m[3], m[4]) for m in modes if m[4] != 0}
want = {tuple(e) for e in exp['expected_3d_modes']}
def fmt(t): return '%dx%d%s@%d %s' % (t[0], t[1], 'i' if t[3] else 'p', t[2], names.get(t[4], 'layout %d' % t[4]))
res('3d_modes_listed', want <= got, 'expected %d unique 3D modes, found %d of them' % (len(want), len(want & got)))
miss = sorted(want - got)
extra = sorted(got - want)
res('no_missing_3d_modes', not miss, 'missing: ' + '; '.join(fmt(t) for t in miss) if miss else 'none missing')
res('no_unexpected_3d_modes', not extra, 'unexpected: ' + '; '.join(fmt(t) for t in extra) if extra else 'none unexpected')
sbsf = [t for t in got if t[4] == 4]
res('side_by_side_full_listed', len(sbsf) >= 2, '%d side by side (full) modes (series patch "drm: list and time HDMI 3D side by side (full)")' % len(sbsf))
# timings
bad = []
for m in modes:
    w, h, hz, il, s, clk, ht, vt, cclk, chd, cht, cvd, cvt = m
    if s == 1:      # frame packing: two frames, the blanking between them counted once (HDMI 1.4b Table 8-14: 1080p24 FP is 1920x2205 in 2250 lines at 148.5 MHz)
        okk = cclk == 2 * clk and cvt == 2 * vt and cvd == h + vt and chd == w and cht == ht
    elif s == 4:    # side by side (full), as the series patch defines it: width doubled, blanking kept, clock grows with the total width
        okk = chd == 2 * w and cht == ht + w and abs(cclk - clk * (ht + w) / ht) <= 1 and cvd == h and cvt == vt
    else:           # everything else keeps the 2D timing
        okk = cclk == clk and chd == w and cht == ht and cvd == h and cvt == vt
    if not okk:
        bad.append(fmt((w, h, hz, il, s)) + ' %s' % m[5:])
res('stereo_timings', not bad, ('wrong: ' + '; '.join(bad[:3])) if bad else 'frame packing, side by side (full) and the layouts that keep the 2D timing all computed as defined')
fp = [m for m in modes if m[4] == 1 and m[0] == 1920 and m[1] == 1080 and m[2] == 24]
if fp:
    m = fp[0]
    res('1080p24_frame_packing_numbers', m[8] == 148500 and m[11] == 2205 and m[12] == 2250 and m[9] == 1920, '%d kHz, 1920x%d in %d lines (HDMI 1.4b: 148500 kHz, 2205 active of 2250)' % (m[8], m[11], m[12]))
sys.exit(1 if fails else 0)
