#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""make-edid.py OUT.bin: the EDID of the virtual DisplayPort sink of vkms-frame-sequential.

An E-EDID 1.4 base block of a digital DisplayPort display (8 bits per colour) with two detailed
timings: 1024x768 at 60 Hz, the preferred 2D mode, and 640x480 at 60 Hz with the stereo bits of
byte 17 set to "field sequential stereo, right image when stereo sync = 1" (E-EDID 1.4,
Table 3.22, bits 6:5 = 01b and bit 0 = 0, the 0x20 that edid-decode prints as field sequential).
No continuous frequency flag and no established or standard timings, so the sink lists exactly
these modes. The small frame-sequential mode keeps VKMS's composer ahead of the frames.
"""
import sys


def dtd(clock_khz, ha, hb, hfp, hs, va, vb, vfp, vs, flags, wmm=520, hmm=320):
    c = clock_khz // 10
    b = [c & 0xff, c >> 8,
         ha & 0xff, hb & 0xff, ((ha >> 8) << 4) | (hb >> 8),
         va & 0xff, vb & 0xff, ((va >> 8) << 4) | (vb >> 8),
         hfp & 0xff, hs & 0xff, ((vfp & 0xf) << 4) | (vs & 0xf),
         ((hfp >> 8) << 6) | ((hs >> 8) << 4) | ((vfp >> 4) << 2) | (vs >> 4),
         wmm & 0xff, hmm & 0xff, ((wmm >> 8) << 4) | (hmm >> 8), 0, 0, flags]
    assert len(b) == 18
    return b


def name_desc(name):
    s = name.encode()[:13]
    s = s + (b'\n' if len(s) < 13 else b'')
    s = s + b' ' * (13 - len(s))
    return [0, 0, 0, 0xfc, 0] + list(s)


def range_desc(vmin, vmax, hmin, hmax, pclk_mhz):
    # Display Range Limits, "Range Limits Only" (no timing formula)
    return [0, 0, 0, 0xfd, 0, vmin, vmax, hmin, hmax, (pclk_mhz + 9) // 10, 0x01, 0x0a] + [0x20] * 6


DIGITAL_SEPARATE_SYNC = 0x18   # bits 4:3 = 11b, both polarities negative
FIELD_SEQUENTIAL_RIGHT = 0x20  # bits 6:5 = 01b, bit 0 = 0

base = [0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00,
        0x31, 0xd8, 0x57, 0x02, 0x00, 0x00, 0x00, 0x00,   # LNX, product 0x0257
        0x00, 0x24, 0x01, 0x04,                           # week 0, 2026, EDID 1.4
        0xa5, 0x34, 0x20, 0x78, 0x0e,                     # digital, 8 bpc, DisplayPort; 52x32 cm; gamma 2.2; RGB 4:4:4, sRGB
        0xee, 0x91, 0xa3, 0x54, 0x4c, 0x99, 0x26, 0x0f, 0x50, 0x54,
        0x00, 0x00, 0x00]                                 # no established timings
base += [0x01, 0x01] * 8                                  # no standard timings
base += dtd(65000, 1024, 320, 24, 136, 768, 38, 3, 6, DIGITAL_SEPARATE_SYNC)
base += dtd(25175, 640, 160, 16, 96, 480, 45, 10, 2, DIGITAL_SEPARATE_SYNC | FIELD_SEQUENTIAL_RIGHT)
base += name_desc('FS DP SINK')
base += range_desc(50, 75, 30, 60, 70)
base += [0]                                               # no extension blocks
base += [(-sum(base)) & 0xff]
assert len(base) == 128

with open(sys.argv[1], 'wb') as f:
    f.write(bytes(base))
