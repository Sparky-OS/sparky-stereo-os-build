#!/usr/bin/env python3
import argparse
import json
import os
import select
import sys

import dbus
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output")
    args = parser.parse_args()

    read_fd, write_fd = os.pipe()
    bus = dbus.SessionBus()
    interface = bus.get_object(
        "org.kde.KWin.ScreenShot2",
        "/org/kde/KWin/ScreenShot2",
    )
    options = {
        "include-decoration": dbus.Boolean(False),
        "include-shadow": dbus.Boolean(False),
        "include-cursor": dbus.Boolean(False),
        "hide-caller-windows": dbus.Boolean(False),
    }
    metadata = interface.CaptureActiveScreen(
        options,
        dbus.types.UnixFd(write_fd),
        dbus_interface="org.kde.KWin.ScreenShot2",
    )
    os.close(write_fd)

    width = int(metadata["width"])
    height = int(metadata["height"])
    stride = int(metadata["stride"])
    expected = stride * height
    data = bytearray()
    while len(data) < expected:
        ready, _, _ = select.select([read_fd], [], [], 5.0)
        if not ready:
            raise RuntimeError("timed out reading KWin capture")
        chunk = os.read(read_fd, expected - len(data))
        if not chunk:
            break
        data.extend(chunk)
    os.close(read_fd)
    if len(data) != expected:
        raise RuntimeError(f"short KWin capture: {len(data)}/{expected} bytes")

    image = Image.frombytes("RGBA", (width, height), bytes(data), "raw", "BGRA", stride, 1)
    image.convert("RGB").save(args.output)
    with open(args.output + ".json", "w", encoding="utf-8") as output:
        json.dump({key: str(value) for key, value in metadata.items()}, output, sort_keys=True)
    print(f"capture {width}x{height} stereo={metadata.get('stereo', '')}")


if __name__ == "__main__":
    sys.exit(main())
