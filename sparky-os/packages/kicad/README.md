# kicad (ORDER 50, step 3)

KiCad 10.0.6+dfsg-1+stereo3d1+lc1: Debian testing's own source, with the 3D viewer's OpenGL view drawn as a stereo pair.

Design followed:
- /K3D/CLAUDE.md: every source hands Stereo KWin full side by side, declared once (here a quad buffer, which the edition's Mesa packs and declares); a program's 3D options are only Enable 3D, render resolution per eye and a shortcut to Display Settings; a program that renders its own 3D scene offers no swap.
- One separation, one place (Daniel, 2026-11-19): the separation is the person's depth limits from the desktop, never scaled by the view's width in the program (libstereo-declare 1.11 converts them to the view's pixels).
- Scenes where we add the two cameras are fitted to the limits (Daniel, 2026-11-18): the separation is the largest for which every pixel of the 3D area stays inside them. KiCad upstream draws no stereo pair (10.0.6 has none), so the October percent setting is gone.
- stereo-integrations-auto-enable (Daniel, 2026-10-14, as the PyMOL recipe quotes it): Enable 3D is on by default; a screen with no stereo visual gives one view and nothing is said; a person who ticks Enable 3D there is told.

## Patches (`patches/`, in series order)
1. Add a stereo eye to the 3D camera (October, our fork gitlab.com/danielcamposramos/kicad, branch stereo3d).
2. 3D viewer: render the OpenGL view in stereo (October).
3. 3D viewer: light the navigator gizmo from the camera between the eyes (October).
4. 3D camera: the stereo disparity of a distance, and the separation that fits limits (the orthographic eyes become a shear).
5. 3D viewer: the stereo separation is the person's depth limits (a first pass from the camera between the eyes reads the nearest and farthest pixel; the limits are read again four times a second; Enable 3D and the Display Settings button are the options).
6. 3D viewer: a translucent model counts in the depth fit by its share of each pixel (that first pass is drawn into an off-screen float framebuffer; the transparent models are drawn there as the eyes draw them, with each fragment's colour its distance, so every pixel ends as the contribution-weighted mean distance of what it shows).
Then `../../translations/kicad-3d-viewer-stereo.po.patch`: the seven new sentences in pl, pt_BR, fr, de, es, ja, ko, zh_CN and zh_TW (the three "3D depth" sentences are CloudCompare's, "3D display settings..." is PyMOL's).

Rule of the fit (Daniel, 2026-11-18): every pixel of the 3D area stays inside the person's limits, a translucent pixel's depth being its contribution-weighted mean.

Debian's wxWidgets 3.2 is built without its EGL GL canvas, so KiCad runs on Xwayland (it sets GDK_BACKEND=x11 itself) and the 3D view is a GLX child window: Stereo KWin's declared X11 child, with the limits written on it (KWin +stereo3d59, support 11).

## Build
The recipe adds `-DKICAD_BUILD_QA_TESTS=OFF` to Debian's CMake options in debian/rules (DEB_KICAD_CMAKE_OPTS): Debian builds the QA test programs even under nocheck, they are never run here and install nothing (qa/ has no install rule), and with them the build tree reached 31.5 GB.

`build.sh DEBIAN.dsc WORK` in a disposable container with the build dependencies, `libstereo-declare-dev` 1.11 or later, bubblewrap, clang, python3 and devscripts (SPARKY_LC_* as the build record route needs them), then `lean.release check-debs`.
