# mesa recipe

+stereo3d29 (ORDER 39) is +stereo3d28 plus patch 0047: a new Vulkan X11 surface starts with no doubled window (the three fields of patch 0041 were left unset, so a surface reported half its window's width when its memory held old bytes; `tests/vk-x11-surface-extent.c` is the test).
`next-source-stereo3d29.sh PREVIOUS.dsc OUT` makes the source from +stereo3d28+lc1 with `changelog-stereo3d29.txt`; it builds with the +stereo3d28 build scripts. Not built yet: proved with a development build of RADV and lavapipe from the +stereo3d26 source with the patch, mounted in the proof rig.

+stereo3d28 (ORDER 50c) is +stereo3d26 plus patches 0045 (a GL child of a Tk window, Netgen's drawing area, is declared once its window is viewable) and 0046 (a stereo child whose window is unmapped or minimised and comes back is declared again), and the build dependencies libudev-dev and libxcb-keysyms1-dev (`debian-changes-stereo3d28.py`).
`next-source-stereo3d28.sh PREVIOUS.dsc OUT` makes the source from the published +stereo3d26+lc1 one, with `changelog-stereo3d28.txt`; `build-stereo3d28.sh` and `build-stereo3d28-in-container.sh` build it for one architecture. The fifth argument of `build-stereo3d28.sh` (a file listing `/repo/pool/...` .deb files, `sparky-stereo-problems` for amd64) is given to the link gate as siblings and as previous siblings, in the build and in the last `check-link`.
Tests: `tests/glx-child-late-map.c` with `tests/check-glx-child-late-map.py` (window mapped late, unmapped and mapped again).
