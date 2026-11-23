# TORCS in stereo: it starts in stereo, with a screen plane for each camera mode

The source producer starts from the published TORCS 1.3.7+dfsg-5+stereo3d3+lc1 and verifies its descriptor.
That source already carries the screen planes by camera mode and the owning libtgfclient Xrandr link correction (the patches this recipe held for +stereo3d3 are in its series now).

## What +stereo3d4 adds (queue row 693)

Daniel, 2026-10-10: stereo by default. Until +stereo3d3 the game drew in stereo only when the person set `PLIB_SSG_STEREO=ON` by hand.

- `launcher-starts-in-stereo.patch`: `/usr/games/torcs` sets `PLIB_SSG_STEREO=ON` when the environment does not set it. `PLIB_SSG_STEREO=OFF torcs` starts the game in 2D; a value the person set is kept.
- `stereo-drawable-only-where-offered.patch`: before the game picks its video mode it tests whether the display offers a stereo drawable. Where it does not, the game prints one line ("This display offers no stereo drawable: TORCS draws in 2D.") and goes on in 2D with its usual video mode, so the default never stops the game from starting.

Still open in row 693: an "Enable 3D" entry in the game's own options as the visible off switch, and the same default for the other programs built on plib.

## The screen planes (+stereo3d3)

The driver profile uses a 1.8 m screen plane and 0.065 m separation; chase uses 2 m and 0.10 m.
The sky uses the world camera's infinity disparity.

`build.sh PUBLISHED.dsc WORK POOL IMAGE ARCHIVE PLIB_DEBS` prepares the source and builds it with the current toolkit and the new plib packages supplied to both APT and the archive gate.
The plib folder's README describes the shared arguments.
This recipe needs plib 1.8.5-15+stereo3d3+lc1 or newer for its additive per-draw interfaces.

The Graphic section of a person's ~/.torcs/config/graph.xml accepts stereo cockpit convergence, stereo chase convergence, stereo cockpit eye separation and stereo chase eye separation.
Package defaults and code fallbacks agree; existing personal files are left alone.
Explicit PLIB_SSG_CONVERGENCE and PLIB_SSG_EYE_SEPARATION settings override both profiles.
The existing PLIB_SSG_STEREO option enables native rendering; do not also enable a second camera-injection layer.
