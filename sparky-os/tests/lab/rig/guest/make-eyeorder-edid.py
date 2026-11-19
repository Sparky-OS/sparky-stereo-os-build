#!/usr/bin/python3 -I
"""make-eyeorder-edid.py IN.bin OUT.bin: the bench's 3D television EDID (edid/stereo-full.bin: HDMI 3D side by side half and full, top and
bottom, frame packing) with 1920x1080 at 120 Hz added (CTA-861 VIC 63, 297 MHz, inside the 300 MHz the EDID declares) and the
range limit descriptor's vertical maximum raised to 125 Hz. KWin offers its frame sequential twins from 100 Hz, so the eye order
matrix needs the mode; the eyeorder recipe of the vkms-stereo skill calls this EDID stereo-full-120."""
import sys

d = bytearray(open(sys.argv[1], "rb").read())
if len(d) != 256:
    sys.exit("expected a base block and one CTA-861 block")
base, cta = d[:128], d[128:]
for off in (54, 72, 90, 108):
    if base[off:off + 4] == b"\x00\x00\x00\xfd":
        base[off + 6] = 125
base[127] = (256 - sum(base[:127]) % 256) % 256
end = cta[2]
blocks = bytearray()
i = 4
done = False
while i < end:
    tag, n = cta[i] >> 5, cta[i] & 31
    body = bytes(cta[i + 1:i + 1 + n])
    if tag == 2 and not done:
        body += bytes([63])
        done = True
    blocks += bytes([(tag << 5) | len(body)]) + body
    i += 1 + n
if not done:
    sys.exit("no video data block")
out = bytearray(128)
out[0:4] = bytes([cta[0], cta[1], 4 + len(blocks), cta[3]])
out[4:4 + len(blocks)] = blocks
out[127] = (256 - sum(out[:127]) % 256) % 256
open(sys.argv[2], "wb").write(bytes(base + out))
