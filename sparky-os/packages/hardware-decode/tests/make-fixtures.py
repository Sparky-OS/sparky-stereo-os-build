#!/usr/bin/env python3
"""Recorded, disjoint eye identities and low-bit ramps, without a display."""
from pathlib import Path
import array
import subprocess
out = Path('/w/fixtures')
out.mkdir(exist_ok=True)
for depth, codec in [(8, 'libx264'), (10, 'libx264'), (10, 'libx265'), (12, 'libx265')]:
    stem = ('h264' if codec == 'libx264' else 'hevc') + f'-eyes{depth}'
    raw = out / (stem + '.yuv')
    data = array.array('H' if depth > 8 else 'B')
    w, h, frames = 640, 192, 48
    for n in range(frames):
        for y in range(h):
            for x in range(w):
                eye_x = x % (w // 2)
                base = 64 if x < w // 2 else 144
                if y < 8 and eye_x < 48:
                    base += 16 * ((n >> (eye_x // 8)) & 1)
                data.append((base << (depth - 8)) + ((x + y + n) % (1 << (depth - 7))))
        for component in (0, 1):
            for y in range(h // 2):
                for x in range(w // 2):
                    eye = x >= w // 4
                    base = 120 if eye == component else 136
                    data.append((base << (depth - 8)) + ((x + 3 * y + n) % (1 << (depth - 7))))
    raw.write_bytes(data.tobytes())
    pixfmt = 'yuv420p' if depth == 8 else f'yuv420p{depth}le'
    params = ['-x264-params', 'frame-packing=3:keyint=24'] if codec == 'libx264' else ['-x265-params', 'pools=4:frame-threads=1:keyint=24:lossless=1']
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', pixfmt,
                    '-s', f'{w}x{h}', '-r', '24', '-i', str(raw), '-frames:v', str(frames),
                    '-c:v', codec, '-threads', '4', '-preset', 'fast', *params,
                    *(['-qp', '1', '-profile:v', 'high' if depth == 8 else 'high10'] if codec == 'libx264' else []), str(out / (stem + '.mkv'))], check=True)
    raw.unlink()
# The control has the same pictures and no stereoscopic declaration.
subprocess.run(['ffmpeg','-v','error','-y','-i',str(out/'h264-eyes8.mkv'),'-vf','sidedata=mode=delete:type=STEREO3D','-map_metadata','-1','-metadata:s:v','stereo_mode=mono','-c:v','libx264',
                '-threads','4','-qp','1','-profile:v','high','-preset','fast',str(out/'h264-2d8.mkv')],check=True)
# Declare HEVC once per ordinary GOP with the edition metadata bitstream filter.
for depth in (10,12):
    p = out / f'hevc-eyes{depth}.mkv'
    tmp = out / f'hevc-eyes{depth}-marked.mkv'
    subprocess.run(['ffmpeg','-v','error','-y','-i',str(p),'-c','copy','-bsf:v',
                    'hevc_metadata=frame_packing=insert:frame_packing_type=side_by_side:frame_packing_view=left_first',str(tmp)],check=True)
    tmp.replace(p)
