# Depth as a 3D source in Qt Multimedia and Dragon (ORDER 151, step R part 2, group 2)

qt6-multimedia 6.11.2-3+stereo3d14+lc1 and dragon 4:26.04.0-1+stereo3d6+lc1.
A picture with its depth map (2D plus depth) is decoded like any other packing and handed to Stereo KWin as full side by side, each eye at the size the video holds.

Design followed (Daniel's words, as recorded):
- Engine, not per program (2026-10-07): "intervene in the engine instead of per case ... qt multimedia it is."
- Depth is a stereo format (2026-10-16): "it's fundamental, don't you think? LG will like to see it there".
- A program's 3D options are only enable 3D, render resolution per eye and a shortcut to Display Settings; a player adds the input packing and a per-file swap of left and right eyes (2026-10-31).
- Never touch the user's file (2026-10-23): the packing and the swap are kept in the program's per-file store.

## Files

- `patches/qt6-multimedia/0016-0024`: the depth series, rebased on the published stack (patches 0001 to 0015 and qt-mvhevc); `git format-patch` of branch `depth-6.11.2-stereo3d14` of invent/github danielcamposramos/qtmultimedia over `b13-stack` (the published stack as commits).
- `patches/dragon/0002, 0003, dragon-3d-video.po.patch`: branch `depth-stereo3d6` of danielcamposramos/dragon over `b5-stack` (the published +stereo3d5); the translations are the edition's `translations/dragon-3d-video.po.patch`.
- `changelog/*.items`: the changelog items, one paragraph per item.
- `next-source.sh PACKAGE PUBLISHED.dsc OUT [SYMBOLS]`: the next +lc1 source (`repo/lc-successor.py --in-place --overlay`): the published history stays a byte identical suffix of the new changelog, the toolkit is this tree's, and nothing else of debian/ changes but the patches, the series, the symbols file and the dependency texts the script names.
- `build.sh` and `build-in-container.sh`: the Lean Code build in `sparky-lc-migration:20261020` with the link and start gate against the published +lc1 build (`SPARKY_LC_ARCHIVE_CONFIG`, `SPARKY_LC_SCRATCH`), then `lean.release check-debs`.

## Order

1. `next-source.sh qt6-multimedia` then `build.sh qt6-multimedia`; the debs go into a flat repository (`apt-ftparchive packages . > Packages`, `Release`).
2. `next-source.sh dragon` then `build.sh dragon ... NEW_DIR` with that repository: dragon builds against qt6-multimedia-dev +stereo3d14.

## Dependencies added or changed

- qt6-multimedia Build-Depends: libstereo-dibr-dev (>= 1.9.0), from the edition's repository (1.12.0-5+lc1 published; checked with apt-cache policy in the build container).
- dragon: qt6-multimedia-dev, libqt6multimedia6 and qml6-module-qtmultimedia raised to 6.11.2-3+stereo3d14+lc1; Depends kde-cli-tools (kcmshell6) and kscreen (kcm_kscreen), which the Display Settings shortcut starts; both are Debian packages, checked with apt-cache policy.
