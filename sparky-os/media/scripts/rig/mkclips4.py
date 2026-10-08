#!/usr/bin/env python3
# HEVC clips: ordinary libx265 encodes (B-frames), the frame packing SEI (payload 45, prefix SEI NAL 39) before each IRAP picture only,
# persistence flag 1, written like x264 writes the H.264 one.  Stock x265 cannot write it.
import subprocess, sys, os
OUT = sys.argv[1]; sys.argv = sys.argv[:2]
src = open('/w/scripts/mkclips2.py').read().split('N = 150')[0].replace("OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)", "")
exec(src)
def encode_hevc(dst, kind, first, n0, n1, gop):
    p = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', '25', '-i', '-',
                          '-c:v', 'libx265', '-preset', 'veryfast', '-crf', '14', '-pix_fmt', 'yuv420p', '-x265-params', f'keyint={gop}:min-keyint={gop}:scenecut=0:log-level=error', '-f', 'hevc', dst], stdin=subprocess.PIPE)
    for n in range(n0, n1): p.stdin.write(frame(kind, first, n).tobytes())
    p.stdin.close(); p.wait()
def sei_hevc(arr_type, left_first, cancel=False):
    b = '1' + ('1' if cancel else '0')
    if not cancel:
        b += format(arr_type, '07b') + '0' + format(1 if left_first else 2, '06b') + '000' + '0' + '00' + '0' * 16 + '00000000' + '1'
    b += '0'   # upsampled_aspect_ratio_flag
    while len(b) % 8: b += '0'
    payload = bytes(int(b[i:i + 8], 2) for i in range(0, len(b), 8))
    return b'\x00\x00\x00\x01\x4e\x01' + escape(bytes([45, len(payload)]) + payload + b'\x80')
def inject_hevc(srcf, dst, arr_type, left_first):
    out = bytearray()
    for n in nals(open(srcf, 'rb').read()):
        t = (n[0] >> 1) & 63
        if 16 <= t <= 21: out += sei_hevc(arr_type, left_first)
        out += b'\x00\x00\x00\x01' + n
    open(dst, 'wb').write(out)
def mux_hevc(s, dst):
    mp4 = dst if dst.endswith('.mp4') else dst[:-4] + '.tmp.mp4'
    subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-framerate', '25', '-f', 'hevc', '-i', s, '-c', 'copy', '-tag:v', 'hvc1', mp4])
    if mp4 != dst: subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-i', mp4, '-c', 'copy', dst]); os.remove(mp4)
N = 150; T = OUT + '/tmp4'; os.makedirs(T, exist_ok=True)
for kind, first, gop, ext in (('sbs', 'L', 12, 'mp4'), ('sbs', 'R', 250, 'mkv'), ('tb', 'L', 250, 'mp4'), ('tb', 'R', 12, 'mkv'), ('sbs', 'L', 250, 'mkv'), ('tb', 'L', 12, 'mp4')):
    t = 3 if kind == 'sbs' else 4
    encode_hevc(f'{T}/x.plain', kind, first, 0, N, gop); inject_hevc(f'{T}/x.plain', f'{T}/x.hevc', t, first == 'L')
    mux_hevc(f'{T}/x.hevc', f'{OUT}/hevc-{kind}-{first}-g{gop}.{ext}')
encode_hevc(T + '/p.hevc', '2d', 'L', 0, N, 12); mux_hevc(T + '/p.hevc', OUT + '/hevc-2d.mp4')
encode_hevc(T + '/a.plain', 'sbs', 'L', 0, 75, 12); inject_hevc(T + '/a.plain', T + '/a.hevc', 3, True)
encode_hevc(T + '/b.hevc', '2d', 'L', 75, N, 12)
open(T + '/cat.hevc', 'wb').write(open(T + '/a.hevc', 'rb').read() + open(T + '/b.hevc', 'rb').read()); mux_hevc(T + '/cat.hevc', OUT + '/hevc-cat-3d2d.mp4')
print('done')
