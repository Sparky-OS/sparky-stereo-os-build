# paraview (ORDER 50, step 5)

ParaView 6.1.1+dfsg1-3+stereo3d2+lc1: Debian testing's own source, offering one stereo output, the declared pair.
+stereo3d2 adds kde-cli-tools, kscreen and libkf6kcmutils-bin to paraview's Depends: the View menu's "3D display settings..." runs kcmshell6 (libkf6kcmutils-bin) with KScreen's page (kcm_kscreen, in kscreen), and a dependency a designed feature needs is a Depends (memory design-check-every-default; the main session's ruling, continuation 2).

## Design followed
- /K3D/CLAUDE.md: every source hands Stereo KWin full side by side, left eye first, declared once; a program's 3D options are only enable 3D, render resolution per eye and a shortcut to Display Settings; a program that renders its own 3D scene offers no swap.
- A program's own output modes go (Daniel, 2026-10-10, 10-14, 10-31): the edition package offers exactly one output, the declared pair; every input and every other function stays.
- A program that draws its own pair keeps its own separation (Daniel, 2026-11-18): ParaView's EyeAngle and `--eye-separation` stay as upstream has them; no separation setting is added.
- No silent fallbacks (Daniel, 2026-11-01): a view the desktop shows flat is said once; an old setting or state that names an output format is said once.

## What the patch does (`patches/0001-...`)
- **Enable 3D**: a Render View setting (Settings, Render View), on by default, with ParaView's own "restart required" notice. At start, without `--stereo` on the command line, it makes the render views stereo-capable with Crystal Eyes, as `--stereo --stereo-type="Crystal Eyes"` does. The View menu has "Enable 3D" (the same setting, applied at the next start, said once) and "3D display settings..." (`kcmshell6 kcm_kscreen`).
  Why at the next start: ParaView picks each view's widget (stereo-capable or not) when it makes the view, and nothing replaces a view's widget afterwards; a stereo window drawing one picture would show a stale right eye, and "Convert To" makes an empty view.
- **Not offered**: `--stereo-type` takes 'Crystal Eyes' only (the default type when `--stereo` is given) and refuses the six output formats with a sentence that says what to use instead; the Render View's StereoType and ServerStereoType keep Crystal Eyes, Left, Right and None (Same As Client for the server) and are not shown in the properties panel; the screenshot's stereo modes keep No change, No stereo, Left Eye Only, Right Eye Only and Both Eyes.
- **Old settings and state files**: a StereoType or ServerStereoType that names one of the six becomes the pair (Crystal Eyes; None with Enable 3D off) and the person is told once; a saved screenshot mode among them saves the picture as the view shows it, with a warning.
- **A desktop without 3D areas**: when the stereo-capable window gets a context without two views, the person is told once that the 3D views are flat.
- **What stays in the binary**: VTK's vtkRenderWindow (Debian's shared vtk9) keeps every stereo type for the other programs that load it; ParaView no longer offers the six. `paraview.simple`'s SaveScreenshot documentation names the modes offered.

## Patch 0002: ParaView's Wayland caution in the log
On Wayland ParaView logs "ParaView is not fully tested on Wayland ... export QT_QPA_PLATFORM=xcb" as a warning at every start (CMake/paraview_client_main.cxx.in), which opens the Output Messages window, mono views included (measured on Debian's 6.1.1 in a virtual Stereo KWin). Wayland is the route the edition tests and ships (EGL, which the same block selects), so the caution is logged at INFO: in the log at that verbosity, no window at start. Separate from patch 0001 so it can be dropped on its own.

## Sentences
Gettext domain `paraview-stereo` (`vtkPVStereoEdition.h`), catalogues from `../../translations/paraview-stereo.po.patch` (Clients/ParaView/stereo-po, built with msgfmt by the patched CMakeLists.txt, installed in /usr/share/locale). The Settings dialog's label and description of Enable 3D are translated through a QTranslator that answers ParaView's `ServerManagerXML` context for those two strings. "Enable 3D", "3D display settings..." and "The display settings could not be opened." are the edition's words from KiCad's and Jmol's catalogues, in all ten languages; the other sentences are in English and pt_BR, with a table for the translations lane in the lane report.

## Build
`build.sh DEBIAN.dsc WORK` in a disposable container with ParaView's build dependencies, gettext and the Lean Code tools. `--build=source,any`: paraview-doc stays Debian's. Build-Depends gains `gettext`; `debian/paraview.install` gains the catalogues. Debug information compressed, as in the vtk9 and KiCad recipes.

## Test
`sparky-os/tests/paraview-stereo/`: ParaView in a virtual Stereo KWin on both routes and both cards (the pair against step 4's numbers, Enable 3D off flat and equal to Debian's mono picture, the menus, each refused type's sentence, a desktop with no 3D areas).
