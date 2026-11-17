# Icons from a model

The optional `STUDIO_MODELS` layer imports glTF 2.0 and GLB through VTK 9.6.
It is a process boundary: the Widgets shell does not link to VTK.
An ordinary build uses `STUDIO_MODELS=OFF` and `STUDIO_STEREO=OFF`.
The model and its local resources are read only; a saved project carries independent copies.
Test models are CC0 camera fixtures, never installed artwork.

One importer creates one scene with its source transforms, materials and lights.
An assembly moves the model along Z; source lights move with that assembly.
A fixed scene light is added only when the model supplies none.
Two cameras retain parallel axes and the same up vector, field of view and clipping planes.
Each camera renders that scene into a native-size offscreen EGL target.
Only the readback row order changes from OpenGL's bottom origin to QImage's top origin.

For a source point at centred model depth z, model translation t, camera distance D,
focal length F in render pixels and camera separation e, left-minus-right disparity is:

`d(z) = F e [1/(D-z-t) - 1/D]`.

The cameras sit at x = -e/2 and +e/2, with their focal points displaced by the same x.
VTK's window centres are `-2 F x / (N D)`.
A point on the screen plane has z+t=0 and zero disparity.
Vertical coordinates use the same projection in both eyes.
Positive disparity pops; negative disparity sinks.

`camera.h` takes the bounds from the importer and budgets from the shared Depth interface.
Exports use source-derived reference width/default limits; preview uses the physical output width and owner limits.
The maximum nonnegative separation is the minimum of the near/far depth bounds and each projected canvas margin.
Output pixels and render pixels are converted through the displayed width, not confused with the icon size.
A nonzero authored placement whose centre rounds flat is compensated by moving further within its signed range.
A zero owner limit and no room in the drawing remain distinct notices.
The disparity is monotone in z, so rounding cannot reverse depth order.

Framing is a fixed initial studio view: camera distance eight bounding radii, a 28-percent half-frame fit,
and an authored travel of twice the depth extent (at least a quarter radius for a planar model).
These are implementation choices, not a larger desktop depth range.
The table exposes the actual fitted far/near pixels for every size.

The GLB BIN chunk is optional (glTF 2.0 sections 3.6.1.2 and 5).
VTK's file path assumes it exists; a JSON-only GLB is therefore passed to its public memory-stream importer,
with a native URI loader rooted at the unchanged source filename.
Unknown container chunks are ignored; malformed lengths are refused.
No source model is rewritten for that dispatch.
