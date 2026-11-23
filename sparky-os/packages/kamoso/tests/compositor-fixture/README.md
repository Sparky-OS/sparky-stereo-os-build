The isolated compositor fixture enumerates the installed stereo policy list.
`matrix-inputs.cpp` writes each synthetic packing, its native expected picture
and a manifest. `matrix-camera.cpp` supplies those frames through Kamoso's real
camera pipeline, including frame ordinals and the two native separated-view
metas. It replaces only the synthetic GstDevice source. `matrix-state.cpp`
reads the real QML video sink, state and geometry; its integral 640×480 video
rectangle separates packing tests from the toolkit's fractional edge rounding.

Record every submitted child buffer and its viewport with the proof rig's wlrec.
`compare-matrix.py` requires exact native samples, one child declaration, only
Qt's own wl_output binding and each compositor eye against one reference resize.
`check-child-declaration.py` verifies that the declaration belongs to the child,
never its parent. A marked stereo capture is a scene witness, not scanout proof.

For a 2D output, nest installed KWin fullscreen on a separate private 1920×1080
compositor. Capture the outer compositor's ordinary surface, and retain both
output modes, renderer strings and window geometries. The left-eye notice is
checked separately at its actual QML bounds; the remaining view is compared
against the complete left source eye. A software-rendered scene capture does
not establish output presentation when the backend cannot allocate its buffer.

Invoke the shared Enable 3D action with desired-state acknowledgements fifty
times off and on. Wait for each actual child destruction and new declaration,
then check the last pair with `check-lifecycle.py`. Run with the pinned declaration
library and the repaired GStreamer Qt material. No extra CPU load is needed.

Ordinary controls use QT_HASH_SEED=0 for published and changed processes alike:
five pairs of published starts, changed 3D-off against published, and enabled
against disabled outside the viewfinder, all with zero differing pixels.
The mono control keeps Enable 3D on and reads back ordinary JPEG and Ogg films;
`verify-mono-negative.py` checks that its failing predecessor reached a live mono
preview and the requested saving action, rather than failing setup.
