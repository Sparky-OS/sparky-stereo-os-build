# openscad (queue row 50, step 4)

OpenSCAD 2026.11~rc1-0+stereo3d1+lc1: upstream's tag `openscad-2026.11-RC1` (commit 2127234b, 2026-11-23), packaged for the edition, with the 3D view drawn as a stereo pair.

Why this source (the main session's ruling for row 50 step 4, not Daniel's words): Debian testing has no OpenSCAD since 2026-10-26 (serious bug 1149820, a build test of the 2021 source; unstable still has 2021.01-14), SparkyLinux's repositories carry none, and the roles scientist, designer and maker name `openscad` (lists/roles.tsv).
Debian's source is the release of 2021 (Qt 5, qmake); the stereo work stands on upstream's current tree (Qt 6, CMake).
Daniel, 2026-11-17: "why you keep binding us to debian testing, partner? it's missing there for a good reason? if not, we keep it if sparkylinux itself won't host it".

## Version
`2026.11~rc1-0+stereo3d1`: the `~` sorts below `2026.11` (Debian Policy 5.6.12), so upstream's final release, packaged as `2026.11-0+stereo3d1`, replaces it, and the Debian revision `0` sorts below Debian's own first packaging of 2026.11 (`2026.11-1`), as the edition's formula asks for an upstream update packaged for the first time.
Debian itself packaged a release candidate this way once (`2019.01~RC2-2`).

## Source
`prepare-source.sh OUTDIR [UPSTREAM_CLONE]` makes `openscad_2026.11~rc1.orig.tar.xz` (sha256 23152b5f...1d183c23, the same bytes on every run): the tag's commit, checked against the commit recorded in the script, plus the two submodules the build takes from source at the commits the tag pins, Manifold v3.5.4 (Debian has no manifold package) and sanitizers-cmake (CMake modules read at configuration), and `VERSION.txt` and `COMMIT.txt`, which upstream's version module reads.
RC1 has no upstream tarball (RC0 has one, signed); the bundled Clipper2, OpenCSG and mimalloc are not taken, Debian's are linked.

## Packaging (debian/)
Debian's 2021.01-14 packaging by Kristian Nielsen and Christian M. Amsüss is the base where it still fits: the package description, the hardening, the removal of the bundled Liberation fonts and of the examples' licence copy, the MCAD library left to `openscad-mcad` (Recommends), the GLES-free dependency, `debian/copyright` (with the 2026 tree's bundled code added and addresses removed), the reportbug script and the documentation link.
Departures, each named: CMake and Ninja instead of qmake (upstream dropped qmake); Qt 6 and QScintilla for Qt 6; the catalogues compiled by `msgfmt` in `debian/rules` (upstream runs a script before a release build); Manifold built from its submodule; the test suite not built, so Debian's `openscad-testing` and `openscad-testing-data` are not made; `contrib/scad-mode.el` gone (upstream moved Emacs's SCAD mode to its own repository, commit 22dfb86e, #4414), so the Emacs files go too; no `Original-Maintainer` field, since a file of ours carries no other person's address (Debian's maintainers are named in `debian/copyright` instead).

## Patches (`patches/`, in series order)
1. Add a sideways eye offset to the 3D view camera (our fork Sparky-OS/openscad, branch `stereo3d-pr`, ffb2ee2a9; pull request openscad/openscad#7112).
2. Draw the 3D view for each eye with a stereo preference (fca8b176a, #7112).
3. Gray out the stereo 3D options when OpenGL has no stereo buffers (c810a549d, #7112).
4. The edition's stereo 3D view: the orthographic eyes become a shear about the point looked at (parallel views); the separation is the person's depth limits, read through libstereo-declare (Wayland: the top-level window's surface; X11: the view's declared stereo window), fitted so every pixel of the view stays inside them (a pass from the camera between the eyes reads the nearest and farthest pixel before the left eye); the eye separation setting is gone; Enable 3D is on by default and asks for stereo buffers in the 3D view's own format only; Display Settings opens from Preferences; a double click reads the depth of the camera between the eyes; what cannot be shown in 3D is said once in the console.
Then `../../translations/openscad-3d-view-stereo.po.patch`: the nine sentences in pl, pt_BR, fr, de, es, ja, ko, zh_CN and zh_TW (five are KiCad's sentences word for word; ja and ko get catalogues of their own).

Design followed:
- /K3D/CLAUDE.md: every source hands Stereo KWin full side by side, declared once (here Qt's stereo `QOpenGLWidget`, which the edition's Qt makes a stereo window of its own that Mesa declares); a program's 3D options are only Enable 3D, render resolution per eye and a shortcut to Display Settings; a program that renders its own 3D scene offers no swap.
- One separation, one place (Daniel, 2026-11-19): the separation is the person's depth limits, converted by the library, never scaled by the view's width in the program.
- Scenes where we add the two cameras are fitted to the limits (Daniel, 2026-11-18): the separation is the largest for which every pixel of the 3D area stays inside them. Upstream OpenSCAD draws no pair (RC1: `QGLView`'s format has no stereo buffers, `paintGL()` draws once, `GLView::setupCamera()` has one eye).
- Enable 3D on by default; a screen with no stereo visual gives one view and nothing is said; a person who ticks Enable 3D there is told (as the KiCad recipe's README quotes Daniel's rule of 2026-10-14).

## Build
`prepare-source.sh`, then `build.sh ORIG_DIR WORK` in a disposable container with the build dependencies of `debian/control`, `libstereo-declare-dev` 1.12.2 or later, bubblewrap, clang, nodejs, node-acorn, python3-yaml and devscripts (SPARKY_LC_* as the build record route needs them), then `lean.release check-debs`.
The debug information is compressed in the objects and linked files (`-gz=zstd`, `-Wl,--compress-debug-sections=zstd`), as in KiCad's recipe.
