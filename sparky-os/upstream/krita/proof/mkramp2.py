#!/usr/bin/env python3
# usage: mkramp2.py out.png [width]   16-bit RGB PNG, sRGB (sRGB TRC) profile embedded. Four bands, top to bottom, equal height:
#   full range 0..65535 | 0.40..0.46 | 1/256 of the range (0.5000..0.5039) | 1/1024 of the range (0.5000..0.5010)
# On a canvas about N columns wide a band that spans 1/256 shows about 4 levels at 10 bits, 16 at 12 bits, N levels at 16 bits (up to 256 at 8 bits is
# the whole range, so an 8-bit surface shows 1 or 2).
import zlib, struct, sys
W, H = int(sys.argv[2]) if len(sys.argv) > 2 else 900, 400
icc = open(sys.argv[3] if len(sys.argv) > 3 else '/w/prefix/base/share/color/icc/krita/sRGB-elle-V2-srgbtrc.icc', 'rb').read()
def row(f):
    r = bytearray()
    for x in range(W):
        v = f(x / (W - 1)); r += struct.pack('>HHH', v, v, v)
    return bytes(r)
bands = [row(lambda t: round(t * 65535)),
         row(lambda t: round((0.40 + 0.06 * t) * 65535)),
         row(lambda t: round((0.5 + t / 256) * 65535)),
         row(lambda t: round((0.5 + t / 1024) * 65535))]
raw = b''.join(b'\x00' + bands[y * 4 // H] for y in range(H))
def chunk(t, d): c = struct.pack('>I', len(d)) + t + d; return c + struct.pack('>I', zlib.crc32(t + d))
open(sys.argv[1], 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 16, 2, 0, 0, 0)) + chunk(b'iCCP', b'sRGB\x00\x00' + zlib.compress(icc)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
