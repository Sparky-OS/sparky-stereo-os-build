# Superseded: Plank Player's first stereo patches and proof (history)

`patches/` (the stereo layer of Plank Player's own, about 730 lines of C++) and `proof/` are the +stereo3d1 state of 5 October 2026.
Since 7 October Plank Player takes its 3D from Qt Multimedia's `Video` (+stereo3d2) and keeps only its 3D menu.

The shipped recipe is elsewhere; do not build the package from this folder:

- `sparky-os/upstream/qtmultimedia/plank-player`: patches 0001 (the menu bound to the video's stereo properties), 0002 (Return) and 0003 (a refused 3D declaration shown in the window);
- `sparky-os/upstream/qtmultimedia/packaging/plank-player-debian`: its packaging text;
- `sparky-os/packages/depth-source/next-source.sh plank-player PUBLISHED.dsc OUT`: the next +lc1 source, made from the published one (its orig tarball is the published pool's), then `build.sh plank-player` (the build image `plank-build:1` that `build-plank-player.sh` expects is not needed).

`proof/` keeps its fake-input driver and its measurements as history; the proof of the shipped package is lane 453b's `rig/` (Stereo KWin in a container, the refuse shim, both eyes captured).
