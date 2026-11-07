#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Capture the active screen through KWin's ScreenShot2 (org.kde.KWin.ScreenShot2.CaptureActiveScreen).

Stereo KWin returns a stereo screen as one picture of both eyes side by side, left eye first,
each at the output's size.  Writes a PNG (8 bits per channel) and prints KWin's results as JSON.
Needs KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 in KWin's environment.
"""
import json, os, sys, threading
import numpy as np
from PIL import Image
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib


def capture(method="CaptureActiveScreen", args=()):
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    r, w = os.pipe()
    fds = Gio.UnixFDList.new()
    index = fds.append(w)
    os.close(w)
    options = {"native-resolution": GLib.Variant("b", True), "include-cursor": GLib.Variant("b", False)}
    signature = {"CaptureActiveScreen": "(a{sv}h)", "CaptureScreen": "(sa{sv}h)", "CaptureWorkspace": "(a{sv}h)"}[method]
    params = GLib.Variant(signature, tuple(args) + (options, index))
    data = bytearray()

    def drain():
        with os.fdopen(r, "rb") as f:
            while True:
                chunk = f.read(1 << 20)
                if not chunk:
                    break
                data.extend(chunk)

    reader = threading.Thread(target=drain)
    reader.start()  # KWin writes the picture before it replies
    result, _ = bus.call_with_unix_fd_list_sync("org.kde.KWin", "/org/kde/KWin/ScreenShot2", "org.kde.KWin.ScreenShot2",
                                                method, params, GLib.VariantType("(a{sv})"), Gio.DBusCallFlags.NONE,
                                                30000, fds, None)
    info = result.unpack()[0]
    del fds  # our end of the write side, so the reader sees the end
    reader.join(30)
    width, height, stride, fmt = info["width"], info["height"], info["stride"], info["format"]
    raw = np.frombuffer(bytes(data[: stride * height]), np.uint8).reshape(height, stride)
    if fmt in (4, 5, 6):            # QImage::Format_RGB32, ARGB32, ARGB32_Premultiplied: B G R A in memory
        px = raw[:, : 4 * width].reshape(height, width, 4)[..., [2, 1, 0]]
    elif fmt in (16, 17, 18):       # RGBX8888, RGBA8888, RGBA8888_Premultiplied
        px = raw[:, : 4 * width].reshape(height, width, 4)[..., :3]
    elif fmt in (25, 26, 27):       # RGBX64, RGBA64, RGBA64_Premultiplied: 16 bits each
        px16 = np.frombuffer(raw[:, : 8 * width].tobytes(), "<u2").reshape(height, width, 4)[..., :3]
        px = ((px16.astype(np.uint32) * 255 + 32767) // 65535).astype(np.uint8)
    else:
        raise SystemExit("unhandled QImage format %d" % fmt)
    return info, np.ascontiguousarray(px)


if __name__ == "__main__":
    out = sys.argv[1]
    info, px = capture()
    Image.fromarray(px, "RGB").save(out)
    print(json.dumps({k: (v if isinstance(v, (int, float, str, bool)) else str(v)) for k, v in info.items()}))
