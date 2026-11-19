#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
"""The build dependencies of +stereo3d28 (ORDER 50c), for next-source-stereo3d28.sh.

debian-changes-stereo3d28.py DEBIAN OVERLAY: reads debian/control and control.in of the +stereo3d26 source and writes them,
with libudev-dev and libxcb-keysyms1-dev declared, into OVERLAY. Debian's source lists neither: meson finds them only when
another build dependency happens to install them, so a build one day later lost them silently (the compile log says
"Run-time dependency libudev found: NO"). libudev gives the Vulkan WSI's VK_KHR_display a udev monitor for display hotplug
(src/vulkan/wsi/wsi_common_display.c, HAVE_LIBUDEV); libxcb-keysyms gives the X11 Vulkan WSI the F1 capture hotkey
(src/vulkan/wsi/wsi_common_x11.c, XCB_KEYSYMS_AVAILABLE). Both link into every libvulkan_*.so of mesa-vulkan-drivers.
Each anchor must be there exactly once, so a source this recipe does not know stops the build.
"""
import sys

PAIRS = [
    (' libva-dev (>= 1.6.0) [linux-any],\n', ' libudev-dev [linux-any],\n libva-dev (>= 1.6.0) [linux-any],\n'),
    (' libxcb-present-dev,\n', ' libxcb-keysyms1-dev,\n libxcb-present-dev,\n'),
]


def change(source, overlay, name):
    text = open(f'{source}/{name}', encoding='utf-8').read()
    for old, new in PAIRS:
        if text.count(old) != 1:
            sys.exit(f'debian/{name} is not the one this recipe knows: {old!r} is there {text.count(old)} times')
        text = text.replace(old, new)
    open(f'{overlay}/{name}', 'w', encoding='utf-8').write(text)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    source, overlay = sys.argv[1:]
    change(source, overlay, 'control')
    change(source, overlay, 'control.in')


if __name__ == '__main__':
    main()
