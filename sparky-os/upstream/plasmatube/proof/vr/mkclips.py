#!/usr/bin/env python3
# Equirectangular test pictures: sectors of equal longitude, left sphere reds, right sphere blues, labelled with the eye and the longitude
# at the sector's centre. 360: 9 sectors of 40 deg, centres -160..160. VR180: 5 sectors of 36 deg, centres -72..72.
import sys
from PIL import Image, ImageDraw, ImageFont
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 70)
small = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 40)
def sphere(eye, n, width, height):
    im = Image.new('RGB', (width, height)); d = ImageDraw.Draw(im)
    sw = width / n
    for i in range(n):
        g = (40 + 20 * i) if n == 9 else (40 + 40 * i)
        col = (255, g, 30) if eye == 'L' else (30, g, 255)
        d.rectangle([i * sw, 0, (i + 1) * sw, height], fill=col)
        lon = round((-180 + (i + .5) * 360 / n) if n == 9 else (-90 + (i + .5) * 180 / n))
        name = 'LEFT' if eye == 'L' else 'RIGHT'
        for y, txt, f in ((height * .30, name, font), (height * .45, 'lon %+d' % lon, small)):
            d.text((i * sw + sw / 2, y), txt, fill=(255, 255, 255), font=f, anchor='mm')
    for y in (height * .25, height * .75):
        d.line([0, y, width, y], fill=(255, 255, 255), width=3)
    return im
def stack(a, b, vertical):
    w, h = a.size
    im = Image.new('RGB', (w, 2 * h) if vertical else (2 * w, h)); im.paste(a, (0, 0)); im.paste(b, (0, h) if vertical else (w, 0)); return im
out = sys.argv[1]
s360 = stack(sphere('L', 9, 2304, 1152), sphere('R', 9, 2304, 1152), True); s360.save(out + '/s360-tb.png')
sphere('L', 9, 2304, 1152).save(out + '/mono360.png')
stack(sphere('L', 5, 1080, 1080), sphere('R', 5, 1080, 1080), False).save(out + '/vr180-sbs.png')
