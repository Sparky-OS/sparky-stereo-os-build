# a mono sphere whose colour tells the latitude: bands of 30 degrees centred on -90..90 in steps of 30, red family
import sys, math
from PIL import Image, ImageDraw
W, H = 2304, 1152
im = Image.new('RGB', (W, H)); d = ImageDraw.Draw(im)
for y in range(H):
    lat = 90 - 180.0 * (y + .5) / H
    band = math.floor((lat + 15) / 30)                   # -3 .. 3, band 0 is -15 .. 15 degrees
    d.line([0, y, W, y], fill=(255, 20 + 30 * (band + 3), 30))
im.save(sys.argv[1] + '/mono360lat.png')
