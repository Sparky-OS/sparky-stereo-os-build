# SPDX-License-Identifier: MIT
"""An interactive Matplotlib figure shown as a declared pair: its 3D area in both eyes, its toolbar flat.

Measured backends: TkAgg (always X11), QtAgg when Qt runs on xcb.  Others, and Qt on native Wayland, show the figure
flat and say why, once.  The 3D options are the edition's three: Enable 3D, the display settings, and (here) none
for the render resolution, which is the figure's own size.
"""
import gettext
import json
import os
import subprocess
import sys

import numpy as np

from . import cameras
from .x11area import X11Area, AreaUnavailable

__all__ = ['StereoFigure', 'render_pair']

_ = gettext.translation('stereo-matplotlib', fallback=True).gettext
_TOLD = set()


def tell(kind, text, toolbar=None):
    """Say a sentence once per session and kind: on the figure's toolbar and in the log (stderr)."""
    if kind in _TOLD:
        return
    _TOLD.add(kind)
    print('stereo-matplotlib: ' + text, file=sys.stderr, flush=True)
    if toolbar is not None and hasattr(toolbar, 'set_message'):
        try:
            toolbar.set_message(text)
        except Exception:
            pass


def _render(figure, width, height, dpi):
    from matplotlib.backends.backend_agg import RendererAgg
    renderer = RendererAgg(width, height, dpi)
    figure.draw(renderer)
    return np.asarray(renderer.buffer_rgba()).copy()


def render_pair(figure, limits, width=None, height=None, dpi=None):
    """Left and right pictures of the figure, each width x height pixels at dpi, the cameras fitted to limits
    (sunk, popped) in those pixels.  Returns (left, right, offsets)."""
    from matplotlib.backends.backend_agg import RendererAgg
    dpi = dpi or figure.dpi
    width = width or int(round(figure.bbox.width))
    height = height or int(round(figure.bbox.height))
    points = cameras.projected_points(figure, RendererAgg(width, height, dpi))
    offsets = cameras.fit(points, limits, (width, height))
    with cameras.StereoCameras(figure, offsets) as eyes:
        eyes.set_eye('right')
        right = _render(figure, width, height, dpi)
        eyes.set_eye('left')
        left = _render(figure, width, height, dpi)
    return left, right, offsets


def _backend(canvas):
    if hasattr(canvas, 'get_tk_widget'):
        return 'tk'
    if hasattr(canvas, 'winId') and hasattr(canvas, 'setAttribute'):
        return 'qt'
    return None


class StereoFigure:
    """Attach to a figure shown in a Tk or Qt window; on by default."""

    def __init__(self, figure, enabled=True):
        self.figure = figure
        self.canvas = figure.canvas
        self.kind = _backend(self.canvas)
        self.toolbar = getattr(self.canvas, 'toolbar', None) or getattr(getattr(self.canvas, 'manager', None), 'toolbar', None)
        self.enabled = enabled
        self.by_hand = False
        self.area = None
        self.limits = None
        self.offsets = {}
        self._busy = False
        self._pending = False
        self._closed = False
        self._connections = [self.canvas.mpl_connect('draw_event', self._on_draw),
                             self.canvas.mpl_connect('resize_event', self._on_resize),
                             self.canvas.mpl_connect('close_event', lambda event: self.close())]
        self._add_controls()
        self._tick()

    # the person's controls
    def _add_controls(self):
        if self.toolbar is None:
            return
        if self.kind == 'tk':
            import tkinter
            self._var = tkinter.IntVar(master=self.toolbar, value=1 if self.enabled else 0)
            tkinter.Checkbutton(self.toolbar, text=_('Enable 3D'), variable=self._var,
                                command=lambda: self.set_enabled(bool(self._var.get()), by_hand=True)).pack(side='left')
            tkinter.Button(self.toolbar, text=_('3D display settings...'), command=self.open_display_settings).pack(side='left')
        elif self.kind == 'qt':
            self.toolbar.addSeparator()
            action = self.toolbar.addAction(_('Enable 3D'))
            action.setCheckable(True)
            action.setChecked(self.enabled)
            action.toggled.connect(lambda on: self.set_enabled(on, by_hand=True))
            self.toolbar.addAction(_('3D display settings...'), self.open_display_settings)

    def open_display_settings(self):
        try:
            subprocess.Popen(['kcmshell6', 'kcm_kscreen'], stdin=subprocess.DEVNULL)
        except OSError as error:
            tell('settings-%s' % error.errno, _('The display settings could not be opened: %s') % error.strerror, self.toolbar)

    def set_enabled(self, on, by_hand=False):
        self.enabled = bool(on)
        self.by_hand = self.by_hand or by_hand
        if not self.enabled:
            self._drop_area()
        self.canvas.draw_idle()

    # the 3D area
    def _native(self):
        if self.kind == 'tk':
            widget = self.canvas.get_tk_widget()
            if widget.tk.call('tk', 'windowingsystem') != 'x11':
                raise AreaUnavailable('Tk does not draw on X11 here', 'not-x11')
            return int(widget.winfo_id())
        if self.kind == 'qt':
            from matplotlib.backends.qt_compat import QtCore, QtGui
            if QtGui.QGuiApplication.platformName() != 'xcb':
                raise AreaUnavailable('Qt runs on %s, not on X11' % QtGui.QGuiApplication.platformName(), 'not-x11')
            self.canvas.setAttribute(QtCore.Qt.WidgetAttribute.WA_NativeWindow)
            return int(self.canvas.winId())
        raise AreaUnavailable('the %s window has no X11 window to hold a 3D area' % type(self.canvas).__name__, 'not-x11')

    def _ensure_area(self, width, height):
        if self.area is not None:
            self.area.resize(width, height)
            return True
        try:
            self.area = X11Area(self._native(), width, height)
            return True
        except AreaUnavailable as error:
            not_x11 = error.kind == 'not-x11'
            stereo_desktop = not (error.kind == 'support' and error.support == 0)
            print('stereo-matplotlib: %s' % error, file=sys.stderr, flush=True)
            if not_x11:
                tell('not-x11', _('This figure is shown flat: its window cannot hold a 3D area. '
                                  'The Tk and Qt windows on X11 can.'), self.toolbar)
            elif stereo_desktop or self.by_hand:
                tell('no-area', _('This figure is shown flat: this desktop does not show 3D areas inside windows.'),
                     self.toolbar)
            self.enabled = False
            return False

    def _drop_area(self):
        if self.area is not None:
            self.area.close()
            self.area = None

    def _on_resize(self, event):
        if self.area is not None:
            w, h = self.canvas.get_width_height(physical=True)
            self.area.resize(w, h)

    def _on_draw(self, event):
        if self._busy or not self.enabled or self._pending:
            return
        self._pending = True
        self._later(self.draw_pair)

    def _later(self, function, ms=0):
        if self.kind == 'tk':
            self.canvas.get_tk_widget().after(ms, function)
        elif self.kind == 'qt':
            from matplotlib.backends.qt_compat import QtCore
            QtCore.QTimer.singleShot(ms, function)

    def _read_limits(self):
        import stereo_declare
        try:
            return tuple(self.area.limits())
        except stereo_declare.DepthLimitsNotOffered:
            tell('no-limits', _('This desktop does not offer depth limits, so both eyes show the same picture.'),
                 self.toolbar)
            return (0.0, 0.0)
        except stereo_declare.DepthLimitsNotDelivered:
            return None

    def draw_pair(self):
        self._pending = False
        if not self.enabled or self._busy:
            return
        w, h = self.canvas.get_width_height(physical=True)
        if not self._ensure_area(w, h):
            return
        self._busy = True
        try:
            limits = self._read_limits()
            self.limits = limits
            left, right, self.offsets = render_pair(self.figure, limits or (0.0, 0.0), w, h,
                                                    self.figure.dpi * getattr(self.canvas, 'device_pixel_ratio', 1))
            self.area.show(np.concatenate([left, right], axis=1))
            if os.environ.get('STEREO_MATPLOTLIB_TRACE'):
                print('stereo-matplotlib trace: ' + json.dumps({
                    'size': [w, h], 'limits': self.limits, 'support': self.area.support,
                    'offsets': [[i, b] for i, ax in enumerate(self.figure.axes) for a, b in self.offsets.items() if a is ax]}),
                    file=sys.stderr, flush=True)
        finally:
            self._busy = False

    def _tick(self):
        """Four times a second: a live change of the person's limits redraws the pair."""
        if self._closed:
            return
        if self.area is not None and self.enabled and not self._busy:
            limits = self._read_limits()
            if limits != self.limits:
                self._on_draw(None)
        self._later(self._tick, 250)

    def close(self):
        self._closed = True
        self._drop_area()
        for cid in self._connections:
            self.canvas.mpl_disconnect(cid)
        self._connections = []
