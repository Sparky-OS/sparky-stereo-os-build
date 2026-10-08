#!/usr/bin/env python3
# HEVC clips with the mark written by the patched x265 (--frame-packing 3 / 4, the x265-frame-packing partner's build), ordinary GOP, B-frames.
import subprocess, sys, os
OUT = sys.argv[1]; sys.argv = sys.argv[:2]
exec(open('/w/scripts/mkclips2.py').read().split('N = 150')[0])
X265 = '/x265/work/b-new-8/x265'; env = dict(os.environ, LD_LIBRARY_PATH='/x265/work/b-new-8')
N = 150; T = OUT + '/tmp6'; os.makedirs(T, exist_ok=True)
def enc(dst, kind, n0, n1, gop, fp):
    y = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', '25', '-i', '-', '-f', 'rawvideo', '-pix_fmt', 'yuv420p', '-'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    x = subprocess.Popen([X265, '--input', '-', '--input-res', f'{W}x{H}', '--fps', '25', '--input-csp', 'i420', '--preset', 'veryfast', '--crf', '14', '--keyint', str(gop), '--min-keyint', str(gop), '--no-scenecut', '--log-level', 'error', '--output', dst] + (['--frame-packing', str(fp)] if fp else []), stdin=y.stdout, env=env)
    for n in range(n0, n1): y.stdin.write(frame(kind, 'L', n).tobytes())
    y.stdin.close(); x.wait(); y.wait()
def mux_h(s, dst):
    mp4 = dst if dst.endswith('.mp4') else dst[:-4] + '.tmp.mp4'
    subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-framerate', '25', '-f', 'hevc', '-i', s, '-c', 'copy', '-tag:v', 'hvc1', mp4])
    if mp4 != dst: subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-i', mp4, '-c', 'copy', dst]); os.remove(mp4)
for kind, fp, gop, ext in (('sbs', 3, 12, 'mp4'), ('sbs', 3, 250, 'mkv'), ('tb', 4, 12, 'mkv'), ('tb', 4, 250, 'mp4')):
    enc(f'{T}/x.hevc', kind, 0, N, gop, fp); mux_h(f'{T}/x.hevc', f'{OUT}/x265-{kind}-L-g{gop}.{ext}')
enc(T + '/a.hevc', 'sbs', 0, 75, 12, 3); enc(T + '/b.hevc', '2d', 75, N, 12, 0)
open(T + '/cat.hevc', 'wb').write(open(T + '/a.hevc', 'rb').read() + open(T + '/b.hevc', 'rb').read()); mux_h(T + '/cat.hevc', OUT + '/x265-cat-3d2d.mp4')
print('done')
