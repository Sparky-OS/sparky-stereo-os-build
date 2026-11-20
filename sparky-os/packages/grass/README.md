# grass (ORDER 50, step 3)

GRASS GIS 8.5.0-1+stereo3d1+lc1: Debian testing's own source, with the 3D view (NVIZ) drawn as a stereo pair.

Design followed:
- /K3D/CLAUDE.md: every source hands Stereo KWin full side by side, declared once (here a quad buffer, which the edition's Mesa packs and declares); a program's 3D options are only Enable 3D, render resolution per eye and a shortcut to Display Settings; a program that renders its own 3D scene offers no swap.
- One separation, one place (Daniel, 2026-11-19): the separation is the person's depth limits from the desktop, never scaled by the view's width in the program (libstereo-declare 1.11 converts them to the view's pixels).
- Scenes where we add the two cameras are fitted to the limits (Daniel, 2026-11-18). GRASS upstream draws no stereo pair (8.5.0 has none; the ORDER 750 audit's "exception" row cited our own October patch), so the October percent setting is gone.
- stereo-integrations-auto-enable (Daniel, 2026-10-14, as the PyMOL recipe quotes it): Enable 3D is on by default; a screen with no stereo visual gives one view and nothing is said; a person who ticks Enable 3D there is told.

## Patches (`patches/`, in series order)
1. to 3. The October work (fork github.com/Sparky-OS/grass, branch stereo3d): the eyes in ogsf's camera, the wxGUI's per-eye draw, and stereo only when the setting asks.
4. ogsf: GS_get_depth_range() (nearest and farthest pixel of the view) and GS_get_stereo_separation() (the largest separation under which they stay inside the limits); GS_set_eye_separation() now takes a fraction of the focus distance.
5. wxGUI/nviz: the separation is the person's depth limits (a first pass from the camera between the eyes; the limits read through libstereo-declare by ctypes, as GRASS reaches its own C libraries, and again four times a second); Enable 3D and the display settings button are the options; the console says once why there are no limits.
6. ogsf: the fit's inputs and result at debug level 3 (g.gisenv set="DEBUG=3").
7. wxGUI: run on X11 when wxWidgets' GL canvas has no EGL (Debian's 3.2 has none): without it the 3D view stopped the whole GUI on a Wayland desktop with wx's fatal error.
Then `../../translations/grass-3d-view-stereo.po.patch`: the seven new sentences in the ten languages (a new zh_TW catalogue that holds only them; Python's gettext chains it before GRASS's zh catalogue).

grass-gui Depends on grass-core of the same version (the GUI calls the new ogsf functions) and on libstereo-declare1 (>= 1.11.0), which it loads at run time.

## Build
`build.sh DEBIAN.dsc WORK` in a disposable container with the build dependencies, bubblewrap, clang, python3 and devscripts (SPARKY_LC_* as the build record route needs them), then `lean.release check-debs`.
