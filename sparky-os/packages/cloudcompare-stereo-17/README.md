# cloudcompare-stereo-17 (ORDER 17, milestone 5)

CloudCompare 2.13.2+git20240821+ds-7+stereo3d1+lc1, built from Debian's own source package (Qt 5), in stereo as the edition has it.

Design followed:
- /K3D/CLAUDE.md: a program's 3D options are only enable 3D, render resolution per eye and a shortcut to Display Settings; a program that renders its own 3D scene offers no swap; every source hands KWin full side by side, declared once.
- Daniel 2026-11-10 (memory ours-first-upstream-second): "all other settings are up to kwin into the depht setting": no separation, device type or output format in our package, by any route that writes options.
- The 3D view is its own child window, the one the compositor sees declared (skill stereo-window-3d-area); a whole window is never declared instead of its 3D area.

## Patches (`patches/`)
1. The stereo window sets its `QSurfaceFormat` on the `QWindow`: Qt picks the native window's visual from the window's own format, so the window had no GLX_STEREO visual and `isQuadBufferSupported()` answered no.
2. One 3D mode: Enable 3D draws the quad-buffered stereo of the program (its generic stereo display path); the stereo dialog, the glass type, the physical parameters and the exclusive full screen requirement are not built.
3. The separation is the person's depth limits: the largest under which the farthest and nearest displayed point stay inside the sunk and popped limits (libstereo-declare 1.10, polled every 250 ms, ten-language sentences when none); the physical parameters leave `StereoParams`.

Upstream's side-by-side stereo mode (CloudCompare pull request 2274, Daniel Girardeau-Montaut, merged 2026-02-03) was read: it does not apply to Debian's 2024-08 source (11 of 17 hunks fail in the renderer) and the edition does not need it, since its Mesa declares a quad-buffered stereo window and Stereo KWin packs it. Credit stays in ATTRIBUTIONS.md.

## Build
`build.sh DEBIAN.dsc WORK` (as the user `builder`, container with the build dependencies, libstereo-declare-dev and libqt5x11extras5-dev), then the link gate and `lean.release check-debs`.
