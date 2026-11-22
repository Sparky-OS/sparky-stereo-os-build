# vtk9 (ORDER 50, step 5)

vtk9 9.6.2+ds-3+stereo3d2+lc1: Debian testing's own source, with two patches: VTK's Qt windows set their blit's draw buffer through VTK's state cache (0001, +stereo3d1), and the colour sizes of a missing colour attachment are not queried (0002, +stereo3d2).

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

## The colour-size warnings (`patches/0002-...`, +stereo3d2)

A flat ParaView view on Wayland (Enable 3D off, or Debian's own mono start) opened Output Messages with eight lines: four "Failed to get red color buffer size (1282)" (and green, blue, alpha) and four "GL Message" lines from VTK's debug callback for `GL_INVALID_OPERATION in glGetFramebufferAttachmentParameteriv`.
`vtkOpenGLRenderWindow::OpenGLInitState` calls `GetColorBufferSizes` while `QVTKRenderWindowAdapter` is made, with the context current on Qt's offscreen surface; the function queries the sizes of `GL_BACK_LEFT` of the bound default framebuffer.
On Wayland that surface has no colour buffer (the attachment's object type is `GL_NONE`, EGL has no draw surface), and the OpenGL specification makes a size query on such an attachment an INVALID_OPERATION; on xcb the surface has one (`GL_FRAMEBUFFER_DEFAULT`) and nothing is printed.
The patch reads `GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE` first and, with `GL_NONE`, leaves the sizes at 0 without querying: the technique of VTK's dc7b841a (Spiros Tsalikis, 2026-11-04, "Do not query a missing depth attachment") for the depth size. An error from the object-type query falls through to the old queries and their warnings. The alpha bit planes stay as before (0 on Wayland, 8 on xcb).
Upstream searched on 2026-11-21: VTK master unchanged here; 29fc5a9b (Jaswant Panchumarti, issue 19474) fixed only macOS; no issue or merge request names Wayland.

## Build

`build.sh DEBIAN.dsc WORK` in a disposable container with vtk9's build dependencies and the Lean Code tools.
`--build=source,any`: vtk9-doc and vtk9-examples (Architecture: all) stay Debian's.
The debug information is kept, compressed in the objects and the linked files (`-gz=zstd`, `-Wl,--compress-debug-sections=zstd` through `DEB_*_MAINT_APPEND`, as the KiCad recipe does): Debian's own amd64 build needed 32.5 GB, most of it debug information; the `-dbgsym` packages carry all of it.

## Test

`sparky-os/tests/paraview-stereo/`: ParaView in Crystal Eyes in a virtual Stereo KWin on both routes (native Wayland, the GLX child on Xwayland) and both cards; the count of `Error in cache state for GL_DRAW_BUFFER` is 16 to 25 per start on Debian's vtk9 and 0 on this one, with the pair unchanged.

The colour sizes (+stereo3d2): `sparky-os/tests/paraview-stereo/vtk-native-colour-size` (a mono QVTKOpenGLNativeWidget, 60 frames) prints 4 warnings and exits 1 on Wayland on Debian's vtk9 and on +stereo3d1, on both cards, and 0 on +stereo3d2 on both routes and both cards; a flat ParaView on Wayland opens no Output Messages window on +stereo3d2 (`tests/paraview-stereo/rig/review_rows.py`, rows `pv-off-*` and `ref-off-*`).

## Retirement

When VTK takes the fix and Debian ships a vtk9 that contains it.
