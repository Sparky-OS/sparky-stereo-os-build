#!/usr/bin/env python3
# Ordinary clips: libx264 with B-frames, the frame packing SEI only where x264 writes it (on keyframes).
# usage: mkclips2.py <outdir>      (runs in the container, ffmpeg + PIL)
# Each view holds the frame number in 16 binary blocks; left view red, right view blue; green block bottom left, yellow bottom right.
import subprocess, sys, os
from PIL import Image, ImageDraw, ImageFont
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
W, H = 1280, 720

def view(w, h, n, eye):
    im = Image.new('RGB', (w, h), (200, 40, 40) if eye == 'L' else (40, 40, 200)); d = ImageDraw.Draw(im)
    bw, bh = w // 16, h // 8
    for i in range(16):
        d.rectangle([i * bw, 0, (i + 1) * bw - 1, bh - 1], fill=(255, 255, 255) if (n >> (15 - i)) & 1 else (0, 0, 0))
    d.rectangle([0, h - h // 4, w // 8 - 1, h - 1], fill=(40, 200, 40))
    d.rectangle([w - w // 8, h - h // 4, w - 1, h - 1], fill=(230, 230, 40))
    word(d, w, h, 'LEFT' if eye == 'L' else 'RIGHT', n)
    d.rectangle([0, 0, w - 1, h - 1], outline=(255, 0, 255), width=max(3, h // 50))   # exact extent of the picture
    return im

def word(d, w, h, text, n):
    # the view says what it is, large, and the frame number below; kept clear of the blocks and the corners
    big = ImageFont.load_default(size=max(12, min(h // 4, w // 5)))
    small = ImageFont.load_default(size=max(10, h // 8))
    d.text((w // 2, int(h * .45)), text, font=big, fill=(255, 255, 255), anchor='mm', stroke_width=3, stroke_fill=(0, 0, 0))
    d.text((w // 2, int(h * .66)), 'frame %d' % n, font=small, fill=(255, 255, 255), anchor='mm', stroke_width=2, stroke_fill=(0, 0, 0))

def grey(n):
    im = Image.new('RGB', (W, H), (128, 128, 128)); d = ImageDraw.Draw(im)
    bw, bh = W // 16, H // 8
    for i in range(16):
        d.rectangle([i * bw, 0, (i + 1) * bw - 1, bh - 1], fill=(255, 255, 255) if (n >> (15 - i)) & 1 else (0, 0, 0))
    d.rectangle([0, H - H // 4, W // 8 - 1, H - 1], fill=(40, 200, 40))
    d.rectangle([W - W // 8, H - H // 4, W - 1, H - 1], fill=(230, 230, 40))
    word(d, W, H, '2D', n)
    d.rectangle([0, 0, W - 1, H - 1], outline=(255, 0, 255), width=max(3, H // 50))
    return im

def frame(kind, first, n):
    if kind == '2d': return grey(n)
    second = 'R' if first == 'L' else 'L'
    im = Image.new('RGB', (W, H))
    if kind == 'sbs':
        im.paste(view(W // 2, H, n, first), (0, 0)); im.paste(view(W // 2, H, n, second), (W // 2, 0))
    else:
        im.paste(view(W, H // 2, n, first), (0, 0)); im.paste(view(W, H // 2, n, second), (0, H // 2))
    return im

def encode(dst, kind, first, n0, n1, gop, bf=3):
    p = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', '25', '-i', '-',
                          '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '14', '-pix_fmt', 'yuv420p', '-g', str(gop), '-bf', str(bf),
                          '-x264-params', 'scenecut=0', '-bsf:v', 'h264_mp4toannexb', '-f', 'h264', dst], stdin=subprocess.PIPE)
    for n in range(n0, n1):
        p.stdin.write(frame(kind, first, n).tobytes())
    p.stdin.close(); p.wait()

def escape(b):
    out = bytearray(); z = 0
    for x in b:
        if z >= 2 and x <= 3: out.append(3); z = 0
        out.append(x); z = z + 1 if x == 0 else 0
    return bytes(out)

def sei_nal(arr_type, left_first, cancel=False):
    # frame packing arrangement SEI, payload type 45, as x264 writes it: repetition period 1
    b = '1' + ('1' if cancel else '0')
    if not cancel:
        b += format(arr_type, '07b') + '0' + format(1 if left_first else 2, '06b') + '000' + '0' + '00' + '0' * 16 + '00000000' + '010'
    b += '0'
    while len(b) % 8: b += '0'
    payload = bytes(int(b[i:i + 8], 2) for i in range(0, len(b), 8))
    return b'\x00\x00\x00\x01\x06' + escape(bytes([45, len(payload)]) + payload + b'\x80')

def nals(data):
    st = []; i = 0
    while True:
        j = data.find(b'\x00\x00\x01', i)
        if j < 0: break
        st.append(j); i = j + 3
    out = []
    for k, s in enumerate(st):
        e = st[k + 1] if k + 1 < len(st) else len(data)
        n = data[s + 3:e]
        out.append(n.rstrip(b'\x00') if k + 1 < len(st) else n)
    return out

def inject(src, dst, arr_type, left_first, cancel_au=None):
    # the SEI before every IDR picture (that is where x264 writes it); optionally a cancel before AU number cancel_au (decode order)
    out = bytearray(); au = -1
    for n in nals(open(src, 'rb').read()):
        t = n[0] & 31
        if t in (1, 5): au += 1
        if t == 5: out += sei_nal(arr_type, left_first)
        elif t == 1 and cancel_au is not None and au == cancel_au: out += sei_nal(0, True, cancel=True)
        out += b'\x00\x00\x00\x01' + n
    open(dst, 'wb').write(out)

def mux(src, dst, mode=None):
    if dst.endswith('.mp4'):
        subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-framerate', '25', '-f', 'h264', '-i', src, '-c', 'copy', dst])
    else:   # Matroska without a StereoMode element, remuxed from the MP4 (a raw stream with B-frames has no timestamps)
        mp4 = dst[:-4] + '.tmp.mp4'
        subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-framerate', '25', '-f', 'h264', '-i', src, '-c', 'copy', mp4])
        subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-i', mp4, '-c', 'copy', dst]); os.remove(mp4)

N = 150
T = OUT + '/tmp'; os.makedirs(T, exist_ok=True)
for kind, t in (('sbs', 3), ('tb', 4)):
    for first in 'LR':
        for gop in (12, 250):
            base = f'{T}/{kind}-{first}-g{gop}'
            encode(base + '.plain', kind, first, 0, N, gop)
            inject(base + '.plain', base + '.264', t, first == 'L')
            for ext in ('mp4', 'mkv'):
                mux(base + '.264', f'{OUT}/ord-{kind}-{first}-g{gop}.{ext}')
# 2D clip, plain
encode(T + '/2d.264', '2d', 'L', 0, N, 12); mux(T + '/2d.264', OUT + '/ord-2d.mp4')
# 3D for the first coded video sequence, 2D after (two encodes concatenated): frames 0..74 3D, 75..149 2D
for ext in ('mp4', 'mkv'):
    encode(T + '/a.plain', 'sbs', 'L', 0, 75, 12); inject(T + '/a.plain', T + '/a.264', 3, True)
    encode(T + '/b.264', '2d', 'L', 75, N, 12)
    open(T + '/cat.264', 'wb').write(open(T + '/a.264', 'rb').read() + open(T + '/b.264', 'rb').read())
    mux(T + '/cat.264', f'{OUT}/cat-3d2d.{ext}')
# 2D first, then 3D (frame 75 on)
encode(T + '/c.264', '2d', 'L', 0, 75, 12)
encode(T + '/d.plain', 'sbs', 'L', 75, N, 12); inject(T + '/d.plain', T + '/d.264', 3, True)
open(T + '/cat2.264', 'wb').write(open(T + '/c.264', 'rb').read() + open(T + '/d.264', 'rb').read()); mux(T + '/cat2.264', OUT + '/cat-2d3d.mp4')
# arrangement changes at the second sequence: side by side, then top and bottom (frame 75 on)
encode(T + '/e.plain', 'sbs', 'L', 0, 75, 12); inject(T + '/e.plain', T + '/e.264', 3, True)
encode(T + '/f.plain', 'tb', 'L', 75, N, 12); inject(T + '/f.plain', T + '/f.264', 4, True)
open(T + '/cat3.264', 'wb').write(open(T + '/e.264', 'rb').read() + open(T + '/f.264', 'rb').read()); mux(T + '/cat3.264', OUT + '/cat-sbs-tb.mp4')
# a cancel flag in the middle of a sequence: no B-frames, one IDR, the cancel before the picture 60
encode(T + '/g.plain', 'sbs', 'L', 0, N, 250, bf=0); inject(T + '/g.plain', T + '/g.264', 3, True, cancel_au=60); mux(T + '/g.264', OUT + '/cancel-60.mp4')
# the real x264 SEI (frame-packing=3), to compare with ours
p = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', '25', '-i', '-', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '14', '-pix_fmt', 'yuv420p', '-g', '12', '-x264-params', 'scenecut=0:frame-packing=3', OUT + '/x264-sbs-L-g12.mp4'], stdin=subprocess.PIPE)
for n in range(N): p.stdin.write(frame('sbs', 'L', n).tobytes())
p.stdin.close(); p.wait()
print('done')
