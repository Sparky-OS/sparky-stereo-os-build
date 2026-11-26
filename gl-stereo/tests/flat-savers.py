# SPDX-License-Identifier: GPL-2.0-or-later
"""2D savers in the show: the rotation takes the ticked ones, the window is read back, the frame is two equal views.

Run under a private X display (xvfb-run). Uses a real XScreenSaver program when one is installed."""
import os
from pathlib import Path
import random
import socket
import struct
import subprocess
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parent.parent/'savers'))
import flat
from catalogue import Rotation
from frames import Frame, receive, send

# the rotation: none unless ticked; a ticked one comes back marked flat; a failed one leaves
rotation = Rotation([], random.Random(1))
assert rotation.next() is None and rotation.next(flat=()) is None
seen = [rotation.next(flat={'deco', 'maze'}) for _ in range(6)]
assert {entry['id'] for entry in seen} == {'deco', 'maze'} and all(entry == dict(id=entry['id'], flat=True) for entry in seen), seen
assert all(a['id'] != b['id'] for a, b in zip(seen, seen[1:])), 'no immediate repeat'
rotation.exclude('deco')
assert {rotation.next(flat={'deco', 'maze'})['id'] for _ in range(4)} == {'maze'}
print('PASS: the rotation offers only ticked 2D savers, marks them flat and drops one that failed')

# names are the installed programs' own; nothing else becomes a command
for bad in ('../sh', 'Deco', '', 'a b', 'x' * 60):
    assert not flat.installed(bad), bad
    try:
        flat.command(bad, 1)
        raise AssertionError(bad)
    except ValueError:
        pass
print('PASS: a name that is not an installed saver is refused')

display = os.environ.get('DISPLAY')
if not display:
    print('SKIP: no DISPLAY, the read-back part needs xvfb-run'); raise SystemExit(0)
grabber = flat.Grabber(display, 320, 180)
assert not any(grabber.picture()[0::4]), 'a new window is black'
name = next((n for n in ('deco', 'greynetic', 'popsquares', 'halo') if flat.installed(n)), None)
if name is None:
    print('SKIP: no XScreenSaver program installed here, the read-back of a real saver is not run'); raise SystemExit(0)
process = subprocess.Popen(flat.command(name, grabber.window), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    deadline, one = time.monotonic() + 20, None
    while time.monotonic() < deadline:
        one = grabber.picture()
        if one and any(one[index] for index in range(0, len(one), 97) if index % 4 != 3):
            break
        time.sleep(.2)
    else:
        raise AssertionError('%s drew nothing in 20 s' % name)
    assert len(one) == 320*180*4 and set(one[3::4]) == {255}
    two = grabber.picture(twice=True)
finally:
    process.terminate(); process.wait(timeout=5)
assert len(two) == 640*180*4
rows = [two[y*640*4:(y+1)*640*4] for y in range(180)]
assert all(row[:320*4] == row[320*4:] for row in rows), 'both views hold the same picture'
# the frame passes the channel's own checks
a, b = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
frame = Frame(flat.sealed(two), 640, 180, 1)
send(a, frame); frame.close()
got = receive(b)
assert (got.width, got.height, got.sequence) == (640, 180, 1); got.close()
grabber.close()
print('PASS: %s drawn on the private window, read back, and handed over as two equal views in a sealed frame' % name)
