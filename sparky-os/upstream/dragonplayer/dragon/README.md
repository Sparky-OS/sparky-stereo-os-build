# Superseded: Dragon Player's first stereo patches (history)

These two patches and `build.sh` are the +stereo3d1 and +stereo3d2 state of 5 to 7 October 2026, when Dragon Player carried its own stereo layer.
Since 7 October Dragon draws and declares 3D through Qt Multimedia's `VideoOutput` stereo layer and keeps only its menu, its settings window and its per-file choices.

The shipped recipe is elsewhere; do not build the package from this folder:

- `sparky-os/upstream/qtmultimedia/dragon`: the menu bound to the video output (patch 0001) and the series that follows it;
- `sparky-os/packages/depth-source/patches/dragon`: Dragon's depth patches 0002 to 0009 (picture plus depth, the offer to save the correction into the file, the way of drawing, the refused declaration shown) and its translations, made into a source by `sparky-os/packages/depth-source/next-source.sh dragon`.

Found by listing the published source's `debian/patches/series` (`dragon_26.04.0-1+stereo3d9+lc1.debian.tar.xz` of the published pool) and not by the folder names: ORDER 453 was briefed from these folders and spent a run finding that they no longer ship.
