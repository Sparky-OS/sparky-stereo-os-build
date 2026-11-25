# SPDX-License-Identifier: GPL-2.0-or-later
"""XScreenSaver's Xlib savers, which draw one view: run on the private display and read back.

A saver of the stereo catalogue is drawn by the layer as a pair. Every other
saver XScreenSaver ships draws with Xlib on a window; this module makes that
window on the private display, starts the saver on it (-window-id) and reads
the window back as one frame of the show's frame channel. The show hands the
greeter the same picture in both halves, so it stands at the screen in both
eyes; the settings page asks for one view.
"""
import ctypes
import ctypes.util
import fcntl
import os
from pathlib import Path
import re

HACKS = Path(os.environ.get('GL_STEREO_FLAT_HACKS', '/usr/libexec/xscreensaver'))
CONFIG = Path(os.environ.get('GL_STEREO_FLAT_CONFIG', '/usr/share/xscreensaver/config'))
NAME = re.compile(r'[a-z0-9][a-z0-9-]{0,40}')
SEALS = fcntl.F_SEAL_WRITE | fcntl.F_SEAL_GROW | fcntl.F_SEAL_SHRINK | fcntl.F_SEAL_SEAL


def installed(name):
    """A saver program with its XScreenSaver description file, by its own name only."""
    program = HACKS / name
    return bool(NAME.fullmatch(name)) and program.is_file() and os.access(program, os.X_OK) and (CONFIG / (name + '.xml')).is_file()


def names():
    """Every installed saver program that has a description file."""
    try:
        found = sorted(path.stem for path in CONFIG.glob('*.xml'))
    except OSError:
        return []
    return [name for name in found if installed(name)]


def command(name, window, options=()):
    if not installed(name):
        raise ValueError('not an installed saver: %r' % (name,))
    return [str(HACKS / name), '-window-id', '0x%x' % window, *options]


def sealed(data):
    fd = os.memfd_create('gl-stereo-flat', os.MFD_CLOEXEC | os.MFD_ALLOW_SEALING)
    try:
        os.write(fd, data)
        fcntl.fcntl(fd, fcntl.F_ADD_SEALS, SEALS)
    except OSError:
        os.close(fd)
        raise
    return fd


class _XImage(ctypes.Structure):
    _fields_ = [('width', ctypes.c_int), ('height', ctypes.c_int), ('xoffset', ctypes.c_int), ('format', ctypes.c_int),
                ('data', ctypes.POINTER(ctypes.c_char)), ('byte_order', ctypes.c_int), ('bitmap_unit', ctypes.c_int),
                ('bitmap_bit_order', ctypes.c_int), ('bitmap_pad', ctypes.c_int), ('depth', ctypes.c_int),
                ('bytes_per_line', ctypes.c_int), ('bits_per_pixel', ctypes.c_int)]


class Grabber:
    """A window on the private display, read back as bottom-up RGBA (the frame channel's format 1)."""

    def __init__(self, display, width, height):
        if not (2 <= width <= 4096 and 1 <= height <= 4096) or width % 2:
            raise ValueError('invalid view size')
        x11 = ctypes.CDLL(ctypes.util.find_library('X11') or 'libX11.so.6')
        x11.XOpenDisplay.restype = ctypes.c_void_p
        x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
        x11.XDefaultRootWindow.restype = ctypes.c_ulong
        x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        x11.XCreateSimpleWindow.restype = ctypes.c_ulong
        x11.XCreateSimpleWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_uint,
                                            ctypes.c_uint, ctypes.c_uint, ctypes.c_ulong, ctypes.c_ulong]
        x11.XMapWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        x11.XDestroyWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        x11.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
        x11.XGetImage.restype = ctypes.POINTER(_XImage)
        x11.XGetImage.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_uint,
                                  ctypes.c_ulong, ctypes.c_int]
        x11.XFree.argtypes = [ctypes.c_void_p]
        self.x11, self.width, self.height = x11, width, height
        self.display = x11.XOpenDisplay(display.encode())
        if not self.display:
            raise RuntimeError('cannot open the private display')
        self.window = x11.XCreateSimpleWindow(self.display, x11.XDefaultRootWindow(self.display), 0, 0, width, height, 0, 0, 0)
        x11.XMapWindow(self.display, self.window)
        x11.XSync(self.display, 0)

    def close(self):
        if self.display:
            self.x11.XDestroyWindow(self.display, self.window)
            self.x11.XCloseDisplay(self.display)
            self.display = None

    def picture(self, twice=False):
        """The window's picture; with TWICE the same picture in both halves (two views wide)."""
        image = self.x11.XGetImage(self.display, self.window, 0, 0, self.width, self.height, 0xffffffff, 2)
        if not image:
            return None
        try:
            info = image.contents
            if info.bits_per_pixel != 32 or info.width != self.width or info.height != self.height:
                return None
            stride = info.bytes_per_line
            raw = ctypes.string_at(info.data, stride * info.height)
        finally:
            self.x11.XFree(ctypes.cast(image.contents.data, ctypes.c_void_p))
            self.x11.XFree(ctypes.cast(image, ctypes.c_void_p))
        row = self.width * 4
        rows = [raw[y * stride:y * stride + row] for y in range(self.height - 1, -1, -1)]
        bgrx = b''.join(line + line for line in rows) if twice else b''.join(rows)
        out = bytearray(len(bgrx))
        out[0::4] = bgrx[2::4]
        out[1::4] = bgrx[1::4]
        out[2::4] = bgrx[0::4]
        out[3::4] = b'\xff' * (len(bgrx) // 4)
        return bytes(out)
