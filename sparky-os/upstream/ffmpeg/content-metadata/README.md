# MP4 stereo metadata

`retain-st3d-with-vexu.patch` applies to the edition's FFmpeg 9.0.2 `libavformat/mov.c` and `isom.h`.
It preserves complementary `st3d` packing and `vexu` view metadata in either box order and reads Spherical Video V2's custom and right-first modes.
It retains the duplicate-st3d rejection with a dedicated presence flag.

The normative type values are in [Spherical Video V2, Stereoscopic 3D Video Box](https://github.com/google/spatial-media/blob/master/docs/spherical-video-v2-rfc.md#stereoscopic-3d-video-box-st3d).
Custom layout remains unspecified; it is not assumed to be a native multiview pair.
The regression fixtures and metadata assertions live in stereo-layer's `autotests/content/`.

The edition recipe now appends the fix and generated FATE coverage to the published `ffmpeg-dmo` source package.
Run `build-source.sh PUBLISHED-SOURCE NEW-SOURCE-DIR` once, then `build-binary.sh NEW-SOURCE-DIR NEW-ARCH-DIR -b` on amd64 and `build-binary.sh NEW-SOURCE-DIR NEW-ARCH-DIR -B` on i386.
The shared descriptor is version `10:9.0.2-dmo1+stereo3d7+lc1`.
The existing Lean Code projection, restore and package hooks are retained.
Use each architecture's complete published +stereo3d6 cohort as the predecessor for `lean.release check-link`, including `ffmpeg-doc` for the architecture-independent package, and run `check-debs` on every final archive.

The upstream review series is based on `d31915e9dce4d33676fadc6c3e08965b4acc132b`.
Its correction is `ca5dbc9` and its separate generated FATE test is `19e75ab`.
The edition backport also supplies the eyes packing preservation absent from 9.0.2.
The test covers all five st3d modes, either box order, inversion, complementary eye/camera fields and plain, reserved and duplicate controls.
It exercises the demuxer and compares observed metadata with an independent reference; no external FATE samples are required.
