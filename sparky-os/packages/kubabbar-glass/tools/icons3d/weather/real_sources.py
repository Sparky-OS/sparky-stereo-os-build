# SPDX-License-Identifier: GPL-3.0-only
"""Derive the textures of Sparky Stereo Real Weather from NASA's downloaded files. Run inside Blender.

blender -b --python-exit-code 1 --python weather/real_sources.py -- DOWNLOADS OUT

The Moon: NASA's Scientific Visualization Studio, CGI Moon Kit (svs.gsfc.nasa.gov/4720): the 2025 colour
map as a 16-bit sRGB TIFF and the LOLA displacement map at 4 pixels per degree, in kilometres.
The Sun: STEREO Ahead, SECCHI EUVI, 304 Angstrom browse image (stereo-ssc.nascom.nasa.gov/browse).
"""
import json
from pathlib import Path
import hashlib
import struct
import sys
import zlib

import bpy
import numpy as np

MOON_COLOUR = 'lroc_color_16bit_srgb_4k.tif'
MOON_HEIGHT = 'ldem_4.tif'
# The colour map's smallest size whose texels are finer than a rendered pixel at 256 px per eye.
MOON_SIZE = (1024, 512)


def to_linear(srgb):
    return np.where(srgb <= .04045, srgb/12.92, ((srgb+.055)/1.055)**2.4)


def to_srgb(linear):
    linear = np.clip(linear, 0, 1)
    return np.where(linear <= .0031308, linear*12.92, 1.055*linear**(1/2.4)-.055)


def chunk(kind, data):
    return struct.pack('>I', len(data))+kind+data+struct.pack('>I', zlib.crc32(kind+data))


def write_png16(path, image):
    """A 16-bit PNG of a top-down array (grey, RGB or RGBA), with the sRGB chunk."""
    height, width = image.shape[:2]
    channels = 1 if image.ndim == 2 else image.shape[2]
    colour_type = {1: 0, 3: 2, 4: 6}[channels]
    rows = np.rint(np.clip(image, 0, 1)*65535).astype('>u2').reshape(height, -1)
    raw = b''.join(b'\0'+row.tobytes() for row in rows)
    header = struct.pack('>IIBBBBB', width, height, 16, colour_type, 0, 0, 0)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', header)+chunk(b'sRGB', b'\0') +
                     chunk(b'IDAT', zlib.compress(raw, 9))+chunk(b'IEND', b''))


def tiff_float(path):
    """An uncompressed single-channel 32-bit float TIFF, as LOLA's grids are stored (TIFF 6.0 tags 256 to 339)."""
    data = path.read_bytes()
    order = {b'II': '<', b'MM': '>'}[data[:2]]
    offset = struct.unpack(order+'I', data[4:8])[0]
    count = struct.unpack(order+'H', data[offset:offset+2])[0]
    tags = {}
    sizes = {3: ('H', 2), 4: ('I', 4)}
    for index in range(count):
        tag, kind, number, value = struct.unpack(order+'HHI4s', data[offset+2+12*index:offset+14+12*index])
        if kind not in sizes:
            continue
        code, size = sizes[kind]
        where = value if number*size > 4 else None
        raw = data[struct.unpack(order+'I', value)[0]:][:number*size] if where else value[:number*size]
        tags[tag] = struct.unpack(order+code*number, raw)
    width, height = tags[256][0], tags[257][0]
    if tags[258][0] != 32 or tags.get(259, (1,))[0] != 1 or tags.get(339, (1,))[0] != 3:
        raise ValueError(f'{path}: not an uncompressed 32-bit float TIFF')
    strips = b''.join(data[start:start+length] for start, length in zip(tags[273], tags[279]))
    return np.frombuffer(strips, dtype=order+'f4').reshape(height, width).astype(np.float32)


def blender_pixels(path):
    """The stored samples of an image Blender reads, top row first, without any colour transform."""
    image = bpy.data.images.load(str(path))
    image.colorspace_settings.name = 'Non-Color'
    width, height = image.size
    values = np.empty(width*height*4, dtype=np.float32)
    image.pixels.foreach_get(values)
    depth = image.depth
    bpy.data.images.remove(image)
    return values.reshape(height, width, 4)[::-1], depth


def moon(downloads, out):
    pixels, depth = blender_pixels(downloads/MOON_COLOUR)
    height, width = pixels.shape[:2]
    factor = width//MOON_SIZE[0]
    if (width, height) != (MOON_SIZE[0]*factor, MOON_SIZE[1]*factor):
        raise ValueError(f'unexpected colour map size {width}x{height}')
    # Average whole blocks in linear light, then encode again: the map is sRGB-encoded.
    linear = to_linear(pixels[..., :3].astype(np.float64))
    small = linear.reshape(MOON_SIZE[1], factor, MOON_SIZE[0], factor, 3).mean(axis=(1, 3))
    write_png16(out/'moon-colour-1024x512.png', to_srgb(small))
    heights = tiff_float(downloads/MOON_HEIGHT)
    if heights.shape != (720, 1440):
        raise ValueError(f'unexpected displacement map size {heights.shape}')
    (out/'moon-height-1440x720-km.f32').write_bytes(heights.astype('<f4').tobytes())
    return dict(colour=dict(source=MOON_COLOUR, size=[width, height], blender_depth=depth, block=factor,
                            derived='moon-colour-1024x512.png'),
                height=dict(source=MOON_HEIGHT, unit='km above 1737.4 km', minimum=float(heights.min()),
                            maximum=float(heights.max()), derived='moon-height-1440x720-km.f32'))


SUN_RAMP = ((0., (.36, .10, .02)), (.30, (.80, .30, .06)), (.58, (1., .68, .20)),
            (.82, (1., .84, .48)), (1., (1., .96, .84)))


def ramp(value):
    """The colour of a sun on a panel, from the dark to the bright end of the EUV picture's intensity (sRGB)."""
    stops = np.array([s for s, _ in SUN_RAMP])
    colours = np.array([c for _, c in SUN_RAMP])
    return np.stack([np.interp(value, stops, colours[:, i]) for i in range(3)], axis=-1)


def sun(downloads, out):
    from PIL import Image
    source = next(downloads.glob('*_304.jpg'))
    rgb = np.asarray(Image.open(source).convert('RGB'), dtype=np.float64)/255
    grey = rgb.mean(axis=2)
    size = grey.shape[0]
    # The browse picture carries lettering above and below the disc; only the disc is mapped.
    body = grey.copy()
    body[:44] = 0
    body[size-44:] = 0
    yy, xx = np.mgrid[:size, :size]
    level = (np.median(body[body > .35])+np.median(body[(body > .02) & (body < .2)]))/2
    mask = body > level
    for _ in range(3):
        cy, cx = yy[mask].mean(), xx[mask].mean()
        radius = np.sqrt(mask.sum()/np.pi)
        mask = body*((yy-cy)**2+(xx-cx)**2 < (1.08*radius)**2) > level
    # The limb: where the radial profile falls fastest just outside the equal-area radius.
    distance = np.hypot(yy-cy, xx-cx)
    profile = np.array([body[(distance >= r) & (distance < r+1)].mean() for r in range(int(1.3*radius))])
    search = np.arange(int(.9*radius), int(1.2*radius))
    limb = float(search[np.argmin(np.diff(profile)[search])]+.5)
    half = int(np.ceil(limb))
    crop = grey[int(round(cy))-half:int(round(cy))+half, int(round(cx))-half:int(round(cx))+half]
    disc = np.hypot(*np.mgrid[-half+.5:half, -half+.5:half]) <= limb
    scale = np.percentile(crop[disc], 99.5)
    value = np.clip(crop/scale, 0, 1)
    write_png16(out/'sun-304-disc.png', ramp(value))
    return dict(source=source.name, size=[size, size], centre=[float(cx), float(cy)], limb_radius=limb,
                equal_area_radius=float(radius), crop=[int(round(cx))-half, int(round(cy))-half, 2*half],
                intensity_scale=float(scale), ramp=SUN_RAMP, derived='sun-304-disc.png',
                false_colour='EUV 304 A intensity mapped onto an orange-to-white ramp; not the picture\'s own colour table')


def main():
    downloads, out = (Path(a) for a in sys.argv[sys.argv.index('--')+1:][:2])
    out.mkdir(parents=True, exist_ok=True)
    record = dict(moon=moon(downloads, out), sun=sun(downloads, out))
    record['files'] = {path.name: dict(bytes=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest())
                       for path in sorted(out.iterdir()) if path.suffix in ('.png', '.f32')}
    (out/'derivation.json').write_text(json.dumps(record, indent=2)+'\n')
    print(json.dumps(record, indent=2))


if __name__ == '__main__':
    main()
