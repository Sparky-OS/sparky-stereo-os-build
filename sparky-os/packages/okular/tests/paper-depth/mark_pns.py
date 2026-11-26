import sys, struct, zlib
# usage: mark_pns.py IN.png OUT.pns   -- a full side by side capture, left eye first: PNG sTER chunk mode 1 (divergent-fused, PNG Extensions 1.4.0 3.6)
data = open(sys.argv[1], 'rb').read()
assert data[:8] == b'\x89PNG\r\n\x1a\n'
out = [data[:8]]; pos = 8; done = False; width = None
while pos < len(data):
    n, = struct.unpack('>I', data[pos:pos+4]); typ = data[pos+4:pos+8]; chunk = data[pos:pos+12+n]
    if typ == b'IHDR': width = struct.unpack('>I', data[pos+8:pos+12])[0]
    if typ == b'IDAT' and not done:
        body = b'\x01'; out.append(struct.pack('>I', 1) + b'sTER' + body + struct.pack('>I', zlib.crc32(b'sTER' + body))); done = True
    if typ != b'sTER': out.append(chunk)
    pos += 12 + n
assert width % 16 == 0, 'sTER needs a width divisible by 16 (3.6)'
open(sys.argv[2], 'wb').write(b''.join(out))
# check: parse back
d = open(sys.argv[2], 'rb').read(); pos = 8; kinds = []
while pos < len(d):
    n, = struct.unpack('>I', d[pos:pos+4]); kinds.append(d[pos+4:pos+8].decode()); pos += 12 + n
assert 'sTER' in kinds and kinds.index('sTER') < kinds.index('IDAT')
print(sys.argv[2], 'chunks', kinds[:4], 'width', width)
