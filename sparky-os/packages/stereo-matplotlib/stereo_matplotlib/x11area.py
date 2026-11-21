# SPDX-License-Identifier: MIT
"""A 3D area inside a toolkit's X11 window, declared to Stereo KWin as full side by side.

The recipe of the edition's native-linux skill (an X11 child window of a program's own): the toolkit's canvas is a
native X window whose size the toolkit owns, so a window of our own is made inside it, two views wide, with no event
mask (the pointer and the keys reach the canvas by X's own propagation), drawn with XPutImage, and declared on the
managed top-level with libstereo-declare's stereo_declare_x11_child() and the size one view is shown at.  Stereo
KWin then shows the left view to the left eye and the right view to the right eye at the canvas's place, each once,
at the size it was drawn, and writes the person's depth limits on the declared window.
"""
import ctypes

__all__ = ['X11Area', 'AreaUnavailable', 'NEEDED_SUPPORT']

NEEDED_SUPPORT = 8      # stereo_declare_x11_child() with a shown size
STEREO_SBS_FULL = 3
STEREO_CLASS_SCIENTIFIC = 4
ZPixmap = 2


class AreaUnavailable(RuntimeError):
    """The desktop or the toolkit gives no 3D area here; the message says why, kind says which case:
    'not-x11' (the toolkit's window is not an X11 window), 'support' (the desktop's declaration support, in
    .support, is under NEEDED_SUPPORT; 0 is a desktop without Stereo KWin), 'library', 'declaration'."""

    def __init__(self, message, kind='library', support=None):
        super().__init__(message)
        self.kind, self.support = kind, support


_ERROR_HANDLER = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)


def _x11():
    lib = ctypes.CDLL('libX11.so.6')
    v, ul, i, u = ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_uint
    sig = {
        'XOpenDisplay': ([ctypes.c_char_p], v), 'XCloseDisplay': ([v], i), 'XDefaultScreen': ([v], i),
        'XDefaultVisual': ([v, i], v), 'XInternAtom': ([v, ctypes.c_char_p, i], ul),
        'XQueryTree': ([v, ul, ctypes.POINTER(ul), ctypes.POINTER(ul), ctypes.POINTER(ctypes.POINTER(ul)), ctypes.POINTER(u)], i),
        'XGetWindowProperty': ([v, ul, ul, ctypes.c_long, ctypes.c_long, i, ul, ctypes.POINTER(ul), ctypes.POINTER(i),
                                ctypes.POINTER(ul), ctypes.POINTER(ul), ctypes.POINTER(ctypes.c_void_p)], i),
        'XGetGeometry': ([v, ul, ctypes.POINTER(ul), ctypes.POINTER(i), ctypes.POINTER(i), ctypes.POINTER(u),
                          ctypes.POINTER(u), ctypes.POINTER(u), ctypes.POINTER(u)], i),
        'XCreateSimpleWindow': ([v, ul, i, i, u, u, u, ul, ul], ul), 'XMapWindow': ([v, ul], i),
        'XResizeWindow': ([v, ul, u, u], i), 'XDestroyWindow': ([v, ul], i), 'XFlush': ([v], i), 'XSync': ([v, i], i),
        'XCreateGC': ([v, ul, ul, v], v), 'XFreeGC': ([v, v], i),
        'XCreateImage': ([v, v, u, i, i, ctypes.c_char_p, u, u, i, i], v),
        'XPutImage': ([v, ul, v, v, i, i, i, i, u, u], i), 'XFree': ([v], i),
        'XSetErrorHandler': ([ctypes.c_void_p], ctypes.c_void_p),
    }
    for name, (args, res) in sig.items():
        f = getattr(lib, name)
        f.argtypes, f.restype = args, res
    return lib


def _declare_library():
    try:
        lib = ctypes.CDLL('libstereo-declare.so.1')
    except OSError as error:
        raise AreaUnavailable('libstereo-declare is not installed: %s' % error, 'library') from error
    v, ul, u, i = ctypes.c_void_p, ctypes.c_ulong, ctypes.c_uint, ctypes.c_int
    lib.stereo_supported_x11.argtypes, lib.stereo_supported_x11.restype = [v], u
    lib.stereo_declare_x11_child.argtypes = [v, ul, ul, i, i, u, u, u]
    lib.stereo_declare_x11_child.restype = i
    lib.stereo_declare_x11_one_view_size.argtypes = [v, ul, u, u]
    lib.stereo_declare_x11_one_view_size.restype = i
    lib.stereo_remove_x11_child.argtypes, lib.stereo_remove_x11_child.restype = [v, ul, ul], i
    return lib


@_ERROR_HANDLER
def _ignore_errors(display, event):
    return 0


class _Quiet:
    """Ignore X errors of our own calls (the toolkit may have destroyed the canvas, and our window with it), then put
    back the handler that was there: the handler is global to the process and the toolkit's Xlib shares it."""

    def __init__(self, x, display):
        self.x, self.display = x, display

    def __enter__(self):
        self.previous = self.x.XSetErrorHandler(ctypes.cast(_ignore_errors, ctypes.c_void_p))
        return self

    def __exit__(self, *exc):
        self.x.XSync(self.display, 0)
        self.x.XSetErrorHandler(self.previous)
        return False


class X11Area:
    """The declared window of our own inside the X window `canvas` (an int window id)."""

    def __init__(self, canvas, width, height):
        self.x = _x11()
        self.declare = _declare_library()
        self.display = self.x.XOpenDisplay(None)
        if not self.display:
            raise AreaUnavailable('no X11 display', 'not-x11')
        self.support = int(self.declare.stereo_supported_x11(self.display))
        if self.support < NEEDED_SUPPORT:
            self.x.XCloseDisplay(self.display)
            self.display = None
            raise AreaUnavailable('the desktop announces stereo declaration support %d; %d is needed for a 3D area '
                                  'inside a window' % (self.support, NEEDED_SUPPORT), 'support', self.support)
        self.canvas = canvas
        self.toplevel = self._managed_toplevel(canvas)
        depth = ctypes.c_uint()
        dummy_w, dummy_i, dummy_u = ctypes.c_ulong(), ctypes.c_int(), ctypes.c_uint()
        self.x.XGetGeometry(self.display, canvas, ctypes.byref(dummy_w), ctypes.byref(dummy_i), ctypes.byref(dummy_i),
                            ctypes.byref(dummy_u), ctypes.byref(dummy_u), ctypes.byref(dummy_u), ctypes.byref(depth))
        self.depth = depth.value
        self.visual = self.x.XDefaultVisual(self.display, self.x.XDefaultScreen(self.display))
        self.width, self.height = max(1, int(width)), max(1, int(height))
        self.window = self.x.XCreateSimpleWindow(self.display, canvas, 0, 0, 2 * self.width, self.height, 0, 0, 0)
        self.gc = self.x.XCreateGC(self.display, self.window, 0, None)
        result = self.declare.stereo_declare_x11_child(self.display, self.toplevel, self.window, STEREO_SBS_FULL,
                                                       STEREO_CLASS_SCIENTIFIC, 0, self.width, self.height)
        if result < 0:
            self.close()
            raise AreaUnavailable('the declaration of the 3D area failed (%d)' % result, 'declaration')
        self.x.XMapWindow(self.display, self.window)
        self.x.XSync(self.display, 0)

    def _managed_toplevel(self, window):
        """ICCCM 4.1.3.1: the nearest ancestor (the window itself counts) that carries WM_STATE, else the last one
        below the root."""
        wm_state = self.x.XInternAtom(self.display, b'WM_STATE', 1)
        current, last = window, window
        while True:
            if wm_state and self._has_property(current, wm_state):
                return current
            root, parent = ctypes.c_ulong(), ctypes.c_ulong()
            children, count = ctypes.POINTER(ctypes.c_ulong)(), ctypes.c_uint()
            if not self.x.XQueryTree(self.display, current, ctypes.byref(root), ctypes.byref(parent),
                                     ctypes.byref(children), ctypes.byref(count)):
                return last
            if children:
                self.x.XFree(children)
            if not parent.value or parent.value == root.value:
                return current
            last, current = current, parent.value

    def _has_property(self, window, atom):
        kind, fmt, n, after = ctypes.c_ulong(), ctypes.c_int(), ctypes.c_ulong(), ctypes.c_ulong()
        data = ctypes.c_void_p()
        self.x.XGetWindowProperty(self.display, window, atom, 0, 0, 0, 0, ctypes.byref(kind), ctypes.byref(fmt),
                                  ctypes.byref(n), ctypes.byref(after), ctypes.byref(data))
        if data:
            self.x.XFree(data)
        return kind.value != 0

    def resize(self, width, height):
        width, height = max(1, int(width)), max(1, int(height))
        if (width, height) == (self.width, self.height):
            return
        self.width, self.height = width, height
        with _Quiet(self.x, self.display):
            self.x.XResizeWindow(self.display, self.window, 2 * width, height)
            self.declare.stereo_declare_x11_one_view_size(self.display, self.window, width, height)

    def show(self, pair_rgba):
        """Put a picture two views wide (height, 2 * width, 4 RGBA bytes) into the window."""
        height, width2 = pair_rgba.shape[:2]
        if self.depth not in (24, 32):
            raise AreaUnavailable('the window has %d bits per pixel; 24 or 32 are drawn' % self.depth)
        bgra = pair_rgba[..., [2, 1, 0, 3]].copy(order='C')
        data = bgra.tobytes()
        image = self.x.XCreateImage(self.display, self.visual, self.depth, ZPixmap, 0, data, width2, height, 32, 0)
        if not image:
            return
        with _Quiet(self.x, self.display):
            self.x.XPutImage(self.display, self.window, self.gc, image, 0, 0, 0, 0, width2, height)
            self.x.XFree(image)

    def limits(self):
        """The person's limits in the pixels of one view as drawn here: stereo_declare.x11_buffer_limits()."""
        import stereo_declare
        return stereo_declare.x11_buffer_limits(self.display, self.window, float(self.width), float(self.width))

    def close(self):
        if not self.display:
            return
        with _Quiet(self.x, self.display):
            if getattr(self, 'window', 0):
                self.declare.stereo_remove_x11_child(self.display, self.toplevel, self.window)
                if getattr(self, 'gc', None):
                    self.x.XFreeGC(self.display, self.gc)
                self.x.XDestroyWindow(self.display, self.window)
                self.window = 0
        self.x.XCloseDisplay(self.display)
        self.display = None
