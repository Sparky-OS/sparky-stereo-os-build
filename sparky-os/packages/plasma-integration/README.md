# plasma-integration and kf6-kirigami, the edition's builds

The edition builds Debian's plasma-integration 6.7.4-1 and kf6-kirigami 6.32.0-1 with one patch each, so that a stereo icon is drawn as a pair in an unmodified program's window and in plasmashell (queue row 77 milestone 2).
Both start from Debian's `.dsc`, pinned by its SHA-256 in `build.sh`; `packages/kf6-kirigami/build.sh` is a link to this folder's `build.sh`, which reads the package from the folder it is called through, and both run `build-job-stereo3d1.sh`.

- `patches/s1-0001-stereo-icons-window-drawn-once-per-eye.patch` (plasma-integration): KIconEngine counts each drawing of an icon the theme has in stereo on the application (`_q_stereo_icons_drawn`, KIconThemes `+stereo3d3`); the KDE platform theme marks the widget window being painted then (`_q_stereo_icon`), and gives a marked window `_q_stereo_depth`, which makes the edition's Qt draw it once per eye, while `Stereo::ScreenMode` says its screen shows two eyes; it takes the property away again on a 2D output, unless something else (a depth style) set it.
- `../kf6-kirigami/patches/s1-0001-icon-each-eye-its-view.patch` (Kirigami): an Icon whose icon has a stereo picture makes its image again for each eye inside the eye's pass (`_q_stereo_eye` on its window, `_q_stereo_icon_eye` on the application while it asks), and marks its window.
- `control-edits.py` (each folder): plasma-integration Build-Depends on `libstereo-layer-dev (>= 1.22.0)` and Depends on `libkf6iconthemes6 (>= 6.32.0-1+stereo3d3~)`; Kirigami changes no field.

Build: `IMAGE=BUILDER POOL=FOLDER_WITH_KICONTHEMES_3 bash build.sh WORK DEBIAN_SOURCE_DIR DEBIAN_BINARY_DIR PUBLISHED_TREE ARCHIVE_DIR` (the arguments are described at the top of `build.sh`).
The proof is the lane's rig, not a unit test inside the package build (Debian builds with `nocheck`).
