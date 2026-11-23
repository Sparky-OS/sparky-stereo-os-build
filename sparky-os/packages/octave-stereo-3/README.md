# GNU Octave 11.3.0-1+stereo3d3+lc1: stereo figures fitted to the person's depth limits

The successor of the published `octave 11.3.0-1+stereo3d2+lc1` (round r1118a), whose source it takes unchanged but for the files of `overlay-stereo3d3/` and three Build-Depends.
Debian testing and unstable carry `octave 11.3.0-1` (binNMU `+b1`), the same base, so there is nothing newer to rebase on.

## What it changes

- **The fit.** Patch 0004 draws a stereo figure once from the camera between the eyes before the left eye (the measuring pass): each 3D axes reads its depth buffer after it is drawn (Octave clears the depth per axes), and its separation is the largest under which every pixel of it stays inside the person's depth limits, read through libstereo-declare 1.12.2 for the figure's window (Wayland: the top-level window's surface; X11: the drawing area's own window), four times a second, so a live change redraws the figure.
  Octave draws orthographic views: each eye's projection is sheared about the camera target, as patch 0002 already did; only the amount changes.
- **The property `stereoeyeseparation`** (patch 0001) stays readable and settable and no longer decides the depth; a script that sets it is told once in the command window.
- **Enable 3D** is on by default: the site `octaverc` sets the default of the figure property `stereo` from the preference `sparky_stereo`/`enable_3d`, which every Qt figure's Tools menu changes ("Enable 3D (applies to new figures)"), beside "3D display settings...", which opens `systemsettings kcm_kscreen`, else `kcmshell6 kcm_kscreen`, and says so when neither exists.
- **The format on the drawing area only.** Patch 0003 had set stereo on Qt's default format while the figure window was made; the edition's Qt gives a stereo `QOpenGLWidget` a native window of its own, so only the drawing area asks.
- **Told once, in ten languages:** the depth limits not offered, not delivered, not readable; the depth not readable; a figure that got no stereo buffers on a desktop that offers them; a desktop without stereo buffers only when the person turned Enable 3D on themselves. The sentences live in `sparky_stereo_text.m`; the C++ side hands a key to `sparky_stereo_tell` through the interpreter's event queue.
- **Qt's private ABI.** The figure reads the window system's handles through Qt's private `QPlatformNativeInterface`, so `octave` depends on `qt6-base-private-abi (= the Qt it was built with)`, as OpenSCAD's recipe does: the overlay's `debian/rules` is the published one with that substitution beside the `octave-abi` Provides, and `--depends` adds `${qt6:private-abi}` to the package's Depends.
- **Octave's own Wayland display code is built.** `libstereo-declare-dev` brings `wayland-client.h`, so Octave's configure turns on `cdisplay.c`'s Wayland path, which Debian's build leaves off: in a session without X11 Octave reads the screen from Wayland and draws figures, where the published build has no graphics toolkit.
- **The welcome** (Daniel, 2026-10-10: "Octave: opens with a nice 3D example as an invitation, with an "Open empty" option"), as in +stereo3d2, now in ten languages and following Enable 3D and the fitted depth.

## Build

From the lane's scratch (row 50 step 5): `tools/run-octave-package.sh` runs `prepare-source-stereo3d3.sh` (the published `.dsc`, its sha256 checked) and `build-stereo3d3.sh` in a builder image with the source's build dependencies and `qt6-base-private-dev`, then `lean.release check-debs`, which writes the build record.
`DEB_BUILD_OPTIONS=parallel=4 nocheck`, as the edition's other recipes of this row.

## Credits

GNU Octave by John W. Eaton and the Octave Project Developers; Debian's packaging by the Debian Octave Group (Sébastien Villemot, Rafael Laboissière).
