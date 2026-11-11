#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Capture the actual output of this test's private virtual QPainter KWin.

ScreenShot2 requires an EGL backend. Without an authorized render device,
KWin 6.7's virtual QPainter backend renders its XRGB8888 output into a
ShmGraphicsBuffer. Read that compositor-owned buffer, not a widget mockup.
Set KWIN_PID and the private XDG_RUNTIME_DIR; dimensions default to 1280x900.
Never point this test at a person's compositor.
"""
import hashlib
import os
from pathlib import Path
import sys
from PIL import Image

pid = int(os.environ['KWIN_PID'])
process = Path('/proc') / str(pid)
command = (process / 'cmdline').read_bytes().split(b'\0')
assert Path(os.fsdecode(command[0])).name == 'kwin_wayland'
assert b'--virtual' in command, 'only the isolated virtual backend is allowed'
environment = (process / 'environ').read_bytes().split(b'\0')
assert ('XDG_RUNTIME_DIR=' + os.environ['XDG_RUNTIME_DIR']).encode() in environment
width = int(os.environ.get('KWIN_CAPTURE_WIDTH', '1280'))
height = int(os.environ.get('KWIN_CAPTURE_HEIGHT', '900'))
stride = width * 4
buffers = []
for descriptor in (process / 'fd').iterdir():
    try:
        # Client buffers are named wayland-shm. The output allocator uses shm.
        if os.readlink(descriptor) == '/memfd:shm (deleted)' and descriptor.stat().st_size == stride * height:
            buffers.append(descriptor)
    except FileNotFoundError:
        pass
assert len(buffers) == 1, f'expected one current compositor output buffer, found {len(buffers)}'
data = buffers[0].read_bytes()
assert len(data) == stride * height
image = Image.frombytes('RGB', (width, height), data, 'raw', 'BGRX', stride)
image.save(sys.argv[1])
print(f'KWin virtual QPainter output: pid={pid}, fd={buffers[0].name}, {width}x{height}, XRGB8888, stride={stride}')
print('Raw compositor buffer SHA256: ' + hashlib.sha256(data).hexdigest())
print('This is the compositor output buffer; ScreenShot2 is unavailable on QPainter.')
