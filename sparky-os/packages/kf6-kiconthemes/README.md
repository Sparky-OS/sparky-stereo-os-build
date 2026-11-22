# kf6-kiconthemes, the edition's successors

The edition's KIconThemes is KDE's library with the stereo icon themes of the edition: folders of pairs listed under `X-StereoDirectories`, read only by stereo lookups.
The 6.32 base (`+stereo3d1`) is made by `sparky-os/release/frameworks-successors/kiconthemes` from Debian's 6.32.0-1 and the published patches.
Each later step adds patches here, one step on from its predecessor pinned by hash, in the shape of `packages/plasma-workspace/build-job-tray-menu.sh`.

## +stereo3d2 (queue row 77 milestone 1, row 752)

- `patches/s2-0001-stereo-icons-refused-folder-is-told.patch`: a stereo folder the loader refuses is told as a warning in the `kf.iconthemes` category, with the index file, the folder's section and the key to add or correct.
- `patches/s2-0002-stereo-icons-each-eye-its-view.patch`: while the edition's Qt draws a window once per eye (`_q_stereo_eye` on the window), `KIconEngine` loads each eye's view of an icon the theme has in stereo; an item that draws itself once per eye names its eye on the application (`_q_stereo_icon_eye`). Everything else is the plain icon, so a 2D output is unchanged.
- Autotest: `autotests/kiconengine_stereotest.cpp` (fails on +stereo3d1, passes here).

## +stereo3d3 (queue row 77 milestone 2)

- `patches/s3-0001-stereo-icons-a-drawing-is-counted.patch`: while `KIconEngine` draws, the loader also says whether the icon it gives has a stereo picture (in either eye, or as the plain icon outside an eye pass), and the engine adds one to the application's `_q_stereo_icons_drawn`; the KDE platform theme and Kirigami's Icon learn from it which windows show such icons (`packages/plasma-integration`). The check is remembered under the plain icon's cache key and skipped, with no lookup, when no theme in the tree has stereo folders.
- Autotest: `kiconengine_stereotest` gains `drawingAStereoIconIsCounted` and `aThemeWithoutStereoFoldersCountsNothing` (fail on +stereo3d2, pass here).

Build: `STEP=3 IMAGE=BUILDER bash build.sh WORK PREDECESSOR_DIR PUBLISHED_TREE ARCHIVE_DIR` (STEP 2 builds +stereo3d2 from the round's +stereo3d1) (the arguments are described at the top of `build.sh`).
The job checks the predecessor's `.dsc` by its SHA-256 and every file it names, applies the two patches, writes the changelog and provenance, prepares Lean Code and builds amd64.
