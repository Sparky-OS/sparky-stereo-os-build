# vtk9 (ORDER 50, step 5)

vtk9 9.6.2+ds-3+stereo3d1+lc1: Debian testing's own source, with one patch to VTK's Qt windows.

## Why

ParaView in Crystal Eyes stereo (a quad-buffered window, which the edition's Mesa packs and declares to Stereo KWin as full side by side) opened an "Output Messages" window at every start, filled with 16 to 25 lines of `Generic Warning: ... vtkOpenGLState.cxx ... Error in cache state for GL_DRAW_BUFFER got 1027 expected1029`.
The pair itself was right; the window was a fault the person did nothing to cause.
ParaView issue 19038 (Mathieu Westphal, open since 2019) records the same warnings on another vendor's driver.

Debian's paraview carries no Qt widget code of its own: `/usr/bin/paraview` NEEDs `libvtkGUISupportQt-9.6.so.1` and `libvtkRenderingOpenGL2-9.6.so.1`, from this source's `libvtk9.6-qt` and `libvtk9.6`.
So the fix is here, and every program that loads VTK's Qt support gets it.

## The cause

`QVTKOpenGLWindow::paintGL` (GUISupport/Qt/QVTKOpenGLWindow.cxx) resets VTK's OpenGL state cache, renders, then blits the left eye into `GL_BACK_LEFT` and the right eye into `GL_BACK_RIGHT` through `QVTKRenderWindowAdapter::blit` (GUISupport/Qt/QVTKRenderWindowAdapter.cxx).
`blit` bound the target and set its draw buffer with Qt's OpenGL functions (`glBindFramebuffer`, `glDrawBuffers`), outside `vtkOpenGLState`, so the cache kept the `GL_BACK` it read at the reset.
The first VTK call of `vtkOpenGLRenderWindow::BlitDisplayFramebuffer` runs `vtkOpenGLState::CheckState`, which reads `GL_DRAW_BUFFER` from OpenGL and compares (Rendering/OpenGL2/vtkOpenGLState.cxx, the `GL_DRAW_BUFFER` block): 1027 is `GL_BACK_RIGHT`, 1029 `GL_BACK`.
The left eye and a mono window never warned, because the check counts `GL_BACK_LEFT` as `GL_BACK`.
VTK's own hardware blit (`vtkOpenGLRenderWindow::BlitDisplayFramebuffersToHardware`) sets `GL_BACK_RIGHT` through the state object; only the Qt adapter went around it.

## The fix (`patches/0001-...`)

`blit` binds the target and sets its draw buffer through `vtkOpenGLState` (`vtkglBindFramebuffer`, `vtkglDrawBuffer`), as the same function already disables the scissor test, and as VTK merge request 4818 (Cory Quammen, 2018) moved `QVTKOpenGLNativeWidget`'s blit off a direct `glDisable` that left the cache stale "with every render".
The state object makes the OpenGL call when its cache differs and keeps the draw buffer of every stacked entry of that framebuffer, so the `Pop` at the end of `paintGL` leaves the cache as OpenGL has it.

Upstream searched on 2026-11-21: VTK master (3b39346a) has the same `blit` and `paintGL` as 9.6.2; no commit since 2025-06 touches the Qt adapter; no merge request or issue of VTK names this desync; ParaView issue 19038 has no fix.
Sibling fixes in the same cache, none for this case: VTK 7707f9c5 / 0f639534 (Sankhesh Jhaveri, GL ES draw buffer re-read at bind), 15ecae03 (Jaswant Panchumarti, a spurious clear-colour warning).

## Build

`build.sh DEBIAN.dsc WORK` in a disposable container with vtk9's build dependencies and the Lean Code tools.
`--build=source,any`: vtk9-doc and vtk9-examples (Architecture: all) stay Debian's.
The debug information is kept, compressed in the objects and the linked files (`-gz=zstd`, `-Wl,--compress-debug-sections=zstd` through `DEB_*_MAINT_APPEND`, as the KiCad recipe does): Debian's own amd64 build needed 32.5 GB, most of it debug information; the `-dbgsym` packages carry all of it.

## Test

`sparky-os/tests/paraview-stereo/`: ParaView in Crystal Eyes in a virtual Stereo KWin on both routes (native Wayland, the GLX child on Xwayland) and both cards; the count of `Error in cache state for GL_DRAW_BUFFER` is 16 to 25 per start on Debian's vtk9 and 0 on this one, with the pair unchanged.

## Retirement

When VTK takes the fix and Debian ships a vtk9 that contains it.
