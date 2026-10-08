#!/usr/bin/env python3
# list the boxes of an MP4 (names and sizes), descending into the containers that matter; prints the video sample entry's children
import struct, sys
CONT = {b'moov', b'trak', b'mdia', b'minf', b'stbl', b'edts', b'udta', b'meta0', b'vexu', b'eyes', b'proj', b'hfov0', b'sv3d'}
def walk(data, off, end, depth, out, path=''):
    while off + 8 <= end:
        size, typ = struct.unpack('>I4s', data[off:off+8]); hdr = 8
        if size == 1: size = struct.unpack('>Q', data[off+8:off+16])[0]; hdr = 16
        if size == 0: size = end - off
        if size < hdr or off + size > end: break
        t = typ.decode('latin1')
        body = data[off+hdr:off+size]
        out.append((depth, path + '/' + t, size, body[:48]))
        if typ in CONT: walk(data, off+hdr, off+size, depth+1, out, path + '/' + t)
        elif typ == b'stsd': walk(data, off+hdr+8, off+size, depth+1, out, path + '/' + t)
        elif typ in (b'avc1', b'hvc1', b'hev1', b'avc3', b'dvh1', b'vvc1'): walk(data, off+hdr+78, off+size, depth+1, out, path + '/' + t)
        off += size
for f in sys.argv[1:]:
    d = open(f, 'rb').read(); out = []; walk(d, 0, len(d), 0, out)
    print('==', f)
    for depth, p, size, body in out:
        if any(k in p for k in ('/stsd/', '/udta/', '/meta')) or p.endswith('/ftyp'):
            print('  ' * depth, p.split('/')[-1], size, body[:24].hex() if size < 100 else '')
