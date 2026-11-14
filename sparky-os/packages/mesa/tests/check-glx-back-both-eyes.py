#!/usr/bin/python3
# check-glx-back-both-eyes.py SHOT.png X Y W H: the capture must be a stereo pair; says which colour the middle of each eye's window and its corner hold.
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB'); W, H = im.size
if W != 3840: print('NOT-STEREO', W, H); sys.exit(2)
def name(p):
    r, g, b = p
    return 'red' if r > 200 and g < 60 and b < 60 else 'blue' if b > 200 and r < 60 and g < 60 else 'green' if g > 200 and r < 60 and b < 60 else str(p)
x0, y0, w, h = [int(v) for v in sys.argv[2:6]]
res = {}
for eye, off in (('left', 0), ('right', 1920)):
    res[eye] = (name(im.getpixel((off + x0 + 20, y0 + 20))), name(im.getpixel((off + x0 + w // 2, y0 + h // 2))))
    print(eye, 'corner', res[eye][0], 'middle', res[eye][1])
ok = res['left'] == ('red', 'green') and res['right'] == ('blue', 'green')
print('PASS: fragment colour zero reached both back buffers' if ok else 'FAIL: the GL_BACK drawing is missing from an eye')
sys.exit(0 if ok else 1)
