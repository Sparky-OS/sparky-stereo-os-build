#!/usr/bin/env python3
# The clips of the earlier proofs, in the new picture: the SEI in every access unit, and Matroska StereoMode without any SEI.
import subprocess, sys, os
OUT = sys.argv[1]; sys.argv = sys.argv[:2]
exec(open('/w/scripts/mkclips2.py').read().split('N = 150')[0])
N = 150; T = OUT + '/tmp5'; os.makedirs(T, exist_ok=True)
def inject_every(src, dst, t, lf):
    out = bytearray()
    for n in nals(open(src, 'rb').read()):
        if (n[0] & 31) in (1, 5): out += sei_nal(t, lf)
        out += b'\x00\x00\x00\x01' + n
    open(dst, 'wb').write(out)
for kind, first, t in (('sbs', 'L', 3), ('tb', 'R', 4)):
    encode(f'{T}/e.plain', kind, first, 0, N, 12); inject_every(f'{T}/e.plain', f'{T}/e.264', t, first == 'L')
    mux(f'{T}/e.264', f'{OUT}/sei-every-{kind}-{first}.mp4')
    mode = {('sbs', 'L'): 1, ('tb', 'R'): 2}[(kind, first)]
    mux(f'{T}/e.plain', f'{OUT}/mkvmode-{kind}-{first}.mkv')
    subprocess.check_call(['mkvpropedit', f'{OUT}/mkvmode-{kind}-{first}.mkv', '--edit', 'track:v1', '--set', f'stereo-mode={mode}'])
print('done')
