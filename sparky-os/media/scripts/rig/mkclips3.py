#!/usr/bin/env python3
# Placement clips for fault 2: Matroska with a StereoMode element; each view carries LEFT / RIGHT, the frame number, the blocks and the corner marks.
import subprocess, sys, os
sys.argv = [sys.argv[0], sys.argv[1]]
exec(open('/w/scripts/mkclips2.py').read().split('def frame(')[0].replace("OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)", "OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)"))
def clip(name, kind, w, h, mode, n=100, first='L'):
    global W, H
    W, H = w, h
    p = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{w}x{h}', '-r', '25', '-i', '-', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '12',
                          '-pix_fmt', 'yuv444p', '-g', '25', '-metadata:s:v:0', 'stereo_mode=' + mode, '-f', 'matroska', f'{OUT}/{name}.mkv'], stdin=subprocess.PIPE)
    for i in range(n):
        second = 'R' if first == 'L' else 'L'
        im = Image.new('RGB', (w, h))
        if kind == 'sbs':
            im.paste(view(w // 2, h, i, first), (0, 0)); im.paste(view(w - w // 2, h, i, second), (w // 2, 0))
        else:
            im.paste(view(w, h // 2, i, first), (0, 0)); im.paste(view(w, h - h // 2, i, second), (0, h // 2))
        p.stdin.write(im.tobytes())
    p.stdin.close(); p.wait()
clip('f2-sbs-600x200', 'sbs', 600, 200, 'left_right')
clip('f2-sbs-1280x720', 'sbs', 1280, 720, 'left_right')
clip('f2-sbs-1920x540', 'sbs', 1920, 540, 'left_right')
clip('f2-tb-400x600', 'tb', 400, 600, 'top_bottom')
print('done')
