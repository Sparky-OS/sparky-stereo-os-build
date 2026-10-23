#!/usr/bin/env python3
"""Check decoded frames, precision, marks and presentation against software."""
import argparse
import array
import csv
import hashlib
from pathlib import Path
import struct
import zlib

p = argparse.ArgumentParser()
p.add_argument('work', type=Path)
a = p.parse_args()
w = a.work
size = 640 * 192
names = ['h264-eyes8', 'h264-eyes10', 'hevc-eyes10', 'hevc-eyes12',
         'h264-right8', 'h264-2d8', 'h264-cancel8', 'mpeg2-eyes8', 'vp9-eyes8', 'vp9-eyes10']

def depth(name):
    return 12 if name.endswith('12') else 10 if name.endswith('10') else 8

def count(name):
    return 96 if 'cancel' in name else 48

def rows(path):
    return list(csv.reader(path.read_text().splitlines()))

def luma(path, bits):
    data = path.read_bytes()
    step = size * 3 // 2 * (2 if bits > 8 else 1)
    assert len(data) % step == 0, path
    values = array.array('H' if bits > 8 else 'B')
    for start in range(0, len(data), step):
        values.frombytes(data[start:start + size * (2 if bits > 8 else 1)])
    return array.array('H', values).tobytes()

def marks(data, name, mark_col, flag_col):
    for i, r in enumerate(data):
        if '2d' in name or ('cancel' in name and i >= 48):
            assert int(r[mark_col]) in (-1, 0), (name, i, r)
        else:
            assert int(r[mark_col]) == 1, (name, i, r)
        assert int(r[flag_col]) == int('right' in name), (name, i, r)

def png(path):
    data = path.read_bytes()
    pos = 8
    blocks = b''
    while pos < len(data):
        length = int.from_bytes(data[pos:pos+4], 'big')
        kind = data[pos+4:pos+8]
        chunk = data[pos+8:pos+8+length]
        if kind == b'IHDR':
            width, height, bits, colour, _, _, interlace = struct.unpack('>IIBBBBB', chunk)
            assert colour == 2 and interlace == 0, path
        if kind == b'IDAT':
            blocks += chunk
        pos += length + 12
    compressed = zlib.decompress(blocks)
    bpp = 3 * bits // 8
    stride = width * bpp
    previous = bytearray(stride)
    output = bytearray()
    for y in range(height):
        offset = y * (stride + 1)
        mode = compressed[offset]
        row = bytearray(compressed[offset+1:offset+1+stride])
        for x in range(stride):
            left = row[x-bpp] if x >= bpp else 0
            up = previous[x]
            upperleft = previous[x-bpp] if x >= bpp else 0
            if mode == 1: prediction = left
            elif mode == 2: prediction = up
            elif mode == 3: prediction = (left + up) // 2
            elif mode == 4:
                q = left + up - upperleft
                distances = [abs(q-left), abs(q-up), abs(q-upperleft)]
                prediction = [left, up, upperleft][distances.index(min(distances))]
            else:
                assert mode == 0
                prediction = 0
            row[x] = (row[x] + prediction) & 255
        output.extend(row)
        previous = row
    return width, height, bits, bytes(output)

assert not [p for p in (w/'final').rglob('*.exit') if p.parent.name != 'fallback'], 'a process failed; inspect the .exit files'
assert (w/'final/fallback/before.exit').read_text().strip() == '134'
assert (w/'final/fallback/after.exit').read_text().strip() == '0'
assert (w/'final/fallback/after.raw').read_bytes() == (w/'final/nvidia/hevc-eyes10-software.raw').read_bytes()
for gpu in ['amd', 'nvidia']:
    for name in names:
        bits = depth(name)
        frames = count(name)
        ref = w/'final'/gpu/f'{name}-software.raw'
        y = luma(ref, bits)
        assert len(y) == size * 2 * frames, ref
        samples = array.array('H'); samples.frombytes(y)
        # Distinct eyes and per-frame identities are part of the input, not inferred from metadata.
        for f in range(frames):
            frame = samples[f*size:(f+1)*size]
            left = sum(frame[20*640:20*640+320])
            right = sum(frame[20*640+320:21*640])
            assert (left > right) == ('right' in name), name
        if 'cancel' not in name:
            assert len({hashlib.sha256(y[i*size*2:(i+1)*size*2]).digest() for i in range(frames)}) == frames, name
        hwref = ref.with_name(ref.name.replace('-software', '-hardware'))
        if hwref.exists():
            assert hwref.read_bytes() == ref.read_bytes(), ('all YUV components', hwref)
            c = rows(hwref.with_suffix('.csv'))
            assert len(c) == frames and all(int(r[5]) == 1 and int(r[2]) == bits for r in c)
            assert [r[0] for r in c] == [r[0] for r in rows(ref.with_suffix('.csv'))]
            marks(c, name, 3, 4)
        hw = not (name == 'h264-eyes10' or (gpu == 'amd' and name == 'hevc-eyes12'))
        folder = f'{gpu}-cancel-recorded' if 'cancel' in name else f'{gpu}-more' if name.startswith(('mpeg2', 'vp9')) else f'{gpu}-engines'
        for engine in ['qt', 'mlt']:
            for mode in ['software', 'hardware']:
                stem = f'{engine}-{mode}' if 'cancel' in name else f'{engine}-{name}-{mode}'
                actual = w/'final'/folder/f'{stem}.raw'
                assert actual.read_bytes() == y, actual
                trace = rows(actual.with_suffix('.trace'))[-frames:]
                assert len(trace) == frames
                assert all(int(r[4]) == bits and int(r[7]) == (hw and mode == 'hardware') for r in trace), actual
                marks(trace, name, 5, 6)
                log = actual.with_suffix('.log').read_text()
                presented = [r for r in log.splitlines() if r.startswith('FRAME ')]
                assert len(presented) == frames, actual
                for i, line in enumerate(presented):
                    mono = '2d' in name or ('cancel' in name and i >= 48)
                    if engine == 'qt':
                        assert ('StereoMode::SideBySide' in line) != mono, (actual, line)
                        assert ('RightEyeFirst' in line) == ('right' in name), (actual, line)
                    else:
                        assert ('side_by_side' in line) != mono, (actual, line)
        mpvfolder = f'{gpu}-cancel-recorded' if 'cancel' in name else f'{gpu}-more' if name.startswith(('mpeg2', 'vp9')) else gpu
        stem = 'mpv-hardware' if 'cancel' in name else f'mpv-{name}'
        trace = rows(w/'final'/mpvfolder/f'{stem}.trace')[-frames:]
        assert len(trace) == frames and all(int(r[4]) == bits and int(r[7]) == hw for r in trace), (gpu, name, 'mpv')
        # mpv owns the Matroska demuxer and puts its VP9 container mark on MPImage, not AVFrame.
        if name.startswith('vp9'):
            log = (w/'final'/mpvfolder/f'{stem}.log').read_text()
            assert 'stereo=sbs2l' in log and 'stereo=sbsl' in log
        else:
            marks(trace, name, 5, 6)
        if name.startswith(('mpeg2', 'vp9')):
            continue
        vlchw = hw and name != 'hevc-eyes12' # VLC 3 has no P012 chroma mapping.
        trace = rows(w/'final'/f'{gpu}-vlc'/f'{name}.trace')[-frames:]
        assert len(trace) == frames and all(int(r[4]) == bits and int(r[7]) == vlchw for r in trace), (gpu, name, 'vlc')
        marks(trace, name, 5, 6)
        if vlchw:
            copied = w/'final'/f'{gpu}-vlc'/f'{name}.raw'
            assert copied.read_bytes() == y, copied
            trace = rows(copied.with_name(f'{name}-copy.trace'))
            assert len(trace) == frames and all(int(r[2]) == bits for r in trace)
            marks(trace, name, 3, 4)
        # Video outputs can drop/repeat presentation frames. Every presented picture must
        # still be a source picture, with its low bits and eye identities unchanged.
        references = {y[i*size*2:(i+1)*size*2] for i in range(frames)}
        for mode in ['none', 'any']:
            actual = w/'final'/f'{gpu}-vlc-vmem'/f'{name}-{mode}.raw'
            data = actual.read_bytes()
            assert len(data) % (size*2) == 0 and len(data) >= size*2, actual
            assert all(data[i:i+size*2] in references for i in range(0, len(data), size*2)), actual
    trace = rows(w/'final'/f'{gpu}-vlc'/'explicit-none.trace')
    assert trace and all(r[7] == '0' for r in trace)
    for name in ['h264-eyes8', 'hevc-eyes10', 'hevc-eyes12', 'h264-right8', 'h264-2d8']:
        no = sorted((w/'final'/f'{gpu}-images'/f'{name}-no').glob('*.png'))
        auto = sorted((w/'final'/f'{gpu}-images'/f'{name}-auto').glob('*.png'))
        assert len(no) == len(auto) == 3
        for sw, hw in zip(no, auto):
            decoded = png(sw)
            assert decoded == png(hw), (sw, hw)
            width, height, bits, data = decoded
            assert (width, height) == (640, 192) and bits == (16 if depth(name)>8 else 8)
            # The edition handoff is left eye first, even when the source is right first.
            sample = list(struct.unpack('>'+('H' if bits==16 else 'B')*(width*height*3), data))
            row = sample[20*width*3:21*width*3]
            assert sum(row[:width//2*3]) < sum(row[width//2*3:]), sw
    print(f'{gpu}: pixels, all-component reference, depth, decoder, stereo persistence/cancel, eye order and 2D PASS')
print('PASS: shared libmpv, Qt Multimedia, MLT and VLC decode paths')
