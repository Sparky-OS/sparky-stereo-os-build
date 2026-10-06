#!/usr/bin/env python3
# usage: mkramp.py out.png [width]  16-bit RGB PNG with the sRGB (sRGB TRC) profile embedded, so Krita opens it without asking:
# top half a full-range ramp (0..65535), bottom half a narrow ramp (0.40..0.46 of full scale)
import zlib, struct, sys
W, H = int(sys.argv[2]) if len(sys.argv) > 2 else 900, 400
icc = open('/w/prefix/base/share/color/icc/krita/sRGB-elle-V2-srgbtrc.icc', 'rb').read()
def row(f):
    r = bytearray()
    for x in range(W):
        v = f(x / (W - 1)); r += struct.pack('>HHH', v, v, v)
    return bytes(r)
full = row(lambda t: round(t * 65535)); narrow = row(lambda t: round((0.40 + 0.06 * t) * 65535))
raw = b''.join(b'\x00' + (full if y < H // 2 else narrow) for y in range(H))
def chunk(t, d): c = struct.pack('>I', len(d)) + t + d; return c + struct.pack('>I', zlib.crc32(t + d))
open(sys.argv[1], 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 16, 2, 0, 0, 0)) + chunk(b'iCCP', b'sRGB\x00\x00' + zlib.compress(icc)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
