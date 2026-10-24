# MP4 stereo metadata

`retain-st3d-with-vexu.patch` applies to the edition's FFmpeg 9.0.2 `libavformat/mov.c` and `isom.h`.
It preserves complementary `st3d` packing and `vexu` view metadata in either box order and reads Spherical Video V2's custom and right-first modes.
It retains the duplicate-st3d rejection with a dedicated presence flag.

The normative type values are in [Spherical Video V2, Stereoscopic 3D Video Box](https://github.com/google/spatial-media/blob/master/docs/spherical-video-v2-rfc.md#stereoscopic-3d-video-box-st3d).
Custom layout remains unspecified; it is not assumed to be a native multiview pair.
The regression fixtures and metadata assertions live in stereo-layer's `autotests/content/`.
This patch has no standalone package recipe; it joins the FFmpeg owner's source series.
