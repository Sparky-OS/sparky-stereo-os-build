# freecad (row 50, step 5)

FreeCAD 1.1.3+dfsg-3+stereo3d2+lc1: Debian testing's own source, with the 3D view drawn as a stereo pair (+stereo3d1 was staged and never published; its changelog entry is kept).

Design followed:
- /K3D/CLAUDE.md: every source hands Stereo KWin full side by side, declared once (here the two buffers of the view's own OpenGL viewport, which the edition's Qt shows as a stereo window of its own and Mesa declares); a program's 3D options are only Enable 3D, render resolution per eye and a shortcut to Display Settings; a program that renders its own 3D scene offers no swap; a program's own output modes are not offered in the edition's build.
- One separation, one place (Daniel, 2026-11-19): the separation is the person's depth limits from the desktop, never scaled by the view's width in the program; FreeCAD's own "eye to eye distance" preference is not offered.
- Scenes where we add the two cameras are fitted to the limits (Daniel, 2026-11-18): the separation is the largest for which every pixel of the 3D area stays inside them. Upstream FreeCAD draws no working pair: 1.1.3's quad-buffer entry draws nothing (queue row 724), and upstream removed its stereo views on 2026-06-09 (pull request 30634).
- A translucent pixel's depth is its contribution-weighted mean (the fit rule, Daniel 2026-11-18; KiCad's patch 0006 in this tree is the worked case): single faint layers inside a pixel may pass a limit, no pixel does.
- A render type in which both eyes would show one picture is made a pair (no-silent-fallbacks): FreeCAD's Framebuffer render type keeps a picture per eye.
- Enable 3D is on by default and is the off switch (Daniel, 2026-11-18); on a screen with no stereo buffers the view stays one picture without a word, and it is said only when the person turns Enable 3D on there; every other failure is told once (no-silent-fallbacks).

## Patches

1. `patches/0001-*`: the stereo 3D view (`src/Gui/View3DStereo.*`, `View3DStereoLimits.*`, Quarter's paint event, the viewer's measuring pass, the View, Stereo menu, the Python API, the preference page). Written for the edition; nothing is offered to FreeCAD's upstream (its AI_POLICY.md and AGENTS.md: contributions by people, agents never communicate on its channels).
2. `patches/0002-*`: the fit's per-pixel distances in a function of their own (`src/Gui/View3DStereoFit.*`) with the unit test `tests/src/Gui/View3DStereoFit.cpp` in FreeCAD's `Gui_tests_run`; on this patch alone the test's translucent, annotation and unfogged cases fail.
3. `patches/0003-*`: a translucent pixel counts at the weighted mean: the measuring pass drawn twice into a float framebuffer with linear fog toward white and toward black, their difference read at every pixel (Coin draws transparent shapes without writing depth); without a float framebuffer they write depth in the pass. The fog is the viewer's own `SoEnvironment` node's (Coin's linear HAZE) for the two passes, given back after them: that node is traversed after the pass's callback and would switch a fog set with GL alone off.
4. `patches/0004-*`: the Framebuffer render type keeps one picture per eye (nothing in FreeCAD 1.1.3 selects it but `setRenderType()`); the view's context is made current before the eyes are drawn, since `setRenderType()` may be called outside a paint and the fit reads its depth in that context.
5. `../../translations/freecad-3d-view-stereo.ts.patch`: the twelve new sentences in pl, pt_BR, fr, de, es (es-ES and es-AR), ja, ko, zh_CN and zh_TW, in FreeCAD's own `src/Gui/Language/FreeCAD_*.ts` catalogues, which the build compiles; seven of them are the edition's existing sentences (OpenSCAD's catalogue) word for word.

## Build

`build.sh DEBIAN.dsc WORK` in a disposable container with the build dependencies, `libstereo-declare-dev` 1.12.2 or later, `qt6-base-private-dev`, `pkgconf`, bubblewrap, clang, python3 and devscripts (the SPARKY_LC_* variables as the build record route needs them), then `lean.release check-debs`.
The recipe adds `libstereo-declare-dev (>= 1.12.2)`, `pkgconf` and `qt6-base-private-dev` to Build-Depends and `${qt6:private-abi}` to `libfreecad-python3`'s Depends (set by an `override_dh_gencontrol` appended to Debian's rules): the GUI library reads its window's handles through Qt's private `QPlatformNativeInterface`.
The debug information is compressed in the objects and linked files (`-gz=zstd`), as the KiCad recipe does.
After `dpkg-buildpackage` the recipe runs `Gui_tests_run --gtest_filter='View3DStereoFit.*'` from the build tree under `xvfb-run` (Debian's own test step stays off, `nocheck`) and fails when it fails; the output is `WORK/freecad-view3dstereofit-test.txt`.

## Credits

FreeCAD by its developers and the contributors its `src/Doc/CONTRIBUTORS` names (Jürgen Riegel, Werner Mayer and Yorik van Havre among them); Coin3D and Quarter, copyright Kongsberg Oil & Gas Technologies AS, and the Coin3D developers; Debian's packaging by the FreeCAD Packaging Team (uploaders Tobias Frost and Kurt Kremitzki).
