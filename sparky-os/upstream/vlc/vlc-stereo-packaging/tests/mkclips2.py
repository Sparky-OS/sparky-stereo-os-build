#!/usr/bin/env python3
# LEFT/RIGHT clips: red left view, blue right view, big black letters LEFT/RIGHT and the frame number, 16 frame-number blocks on top,
# green block bottom-left, yellow bottom-right. Ordinary x264 encode (GOP 250, 3 B-frames): the frame packing SEI only on keyframes.
import subprocess, sys
from PIL import Image, ImageDraw, ImageFont
OUT = sys.argv[1]; N = 250; W, H = 1280, 720
FW, FH = 2560, 720   # full side by side: each view 1280x720
F1 = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 150)
F2 = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 90)
def view(w, h, n, eye):
    im = Image.new('RGB', (w, h), (200, 40, 40) if eye == 'L' else (40, 40, 200)); d = ImageDraw.Draw(im)
    bw, bh = w // 16, h // 8
    for i in range(16):
        d.rectangle([i * bw, 0, (i + 1) * bw - 1, bh - 1], fill=(255, 255, 255) if (n >> (15 - i)) & 1 else (0, 0, 0))
    d.rectangle([0, h - h // 4, w // 8 - 1, h - 1], fill=(40, 200, 40)); d.rectangle([w - w // 8, h - h // 4, w - 1, h - 1], fill=(230, 230, 40))
    t = 'LEFT' if eye == 'L' else 'RIGHT'
    d.text((w // 2, h * 0.42), t, font=F1, fill=(0, 0, 0), anchor='mm')
    d.text((w // 2, h * 0.68), '%04d' % n, font=F2, fill=(0, 0, 0), anchor='mm')
    return im
def flat(n):
    im = Image.new('RGB', (W, H), (128, 128, 128)); d = ImageDraw.Draw(im); bw, bh = W // 16, H // 8
    for i in range(16):
        d.rectangle([i * bw, 0, (i + 1) * bw - 1, bh - 1], fill=(255, 255, 255) if (n >> (15 - i)) & 1 else (0, 0, 0))
    d.text((W // 2, H * 0.42), '2D', font=F1, fill=(0, 0, 0), anchor='mm'); d.text((W // 2, H * 0.68), '%04d' % n, font=F2, fill=(0, 0, 0), anchor='mm')
    return im
def frame(kind, first, n):
    if kind == '2d': return flat(n)
    a, b = view(W // 2 if kind == 'sbs' else W, H if kind == 'sbs' else H // 2, n, first), view(W // 2 if kind == 'sbs' else W, H if kind == 'sbs' else H // 2, n, 'R' if first == 'L' else 'L')
    im = Image.new('RGB', (W, H))
    if kind == 'sbs': im.paste(a, (0, 0)); im.paste(b, (W // 2, 0))
    else: im.paste(a, (0, 0)); im.paste(b, (0, H // 2))
    return im
def enc(name, kind, first, fp, full=False):
    xp = 'keyint=250:min-keyint=250:scenecut=0:bframes=3' + (':frame-packing=%d' % fp if fp else '')
    p = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', '25', '-i', '-', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '16',
                          '-pix_fmt', 'yuv420p', '-x264-params', xp, f'{OUT}/{name}.mp4'], stdin=subprocess.PIPE)
    for n in range(N): p.stdin.write(frame(kind, first, n).tobytes())
    p.stdin.close(); p.wait()
enc('x264-sbs', 'sbs', 'L', 3); enc('x264-tb', 'tb', 'L', 4); enc('x264-2d', '2d', 'L', 0)

def frame_full(kind, n):
    a, b = view(1280, 720, n, 'L'), view(1280, 720, n, 'R')
    if kind == 'sbs':
        im = Image.new('RGB', (2560, 720)); im.paste(a, (0, 0)); im.paste(b, (1280, 0))
    else:
        im = Image.new('RGB', (1280, 1440)); im.paste(a, (0, 0)); im.paste(b, (0, 720))
    return im
def enc_full(name, kind, fp):
    w, h = (2560, 720) if kind == 'sbs' else (1280, 1440)
    p = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{w}x{h}', '-r', '25', '-i', '-', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '16',
                          '-pix_fmt', 'yuv420p', '-x264-params', 'keyint=250:min-keyint=250:scenecut=0:bframes=3:frame-packing=%d' % fp, f'{OUT}/{name}.mp4'], stdin=subprocess.PIPE)
    for n in range(N): p.stdin.write(frame_full(kind, n).tobytes())
    p.stdin.close(); p.wait()
enc_full('x264-fsbs', 'sbs', 3); enc_full('x264-ftb', 'tb', 4)
