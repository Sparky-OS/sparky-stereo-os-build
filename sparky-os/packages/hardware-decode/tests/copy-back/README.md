# Copy-back hardware decoding, by choice only

The edition's media engines take hardware decoding whose pictures the output uses where they are first, software decoding next, and hardware decoding that copies every picture back to system memory only when the person chooses it, or where the machine's measured record allows it (`CopyBack=true` in group `[Decoding]` of `sparky-stereo-graphicsrc`, read by libmedia-gpu-route).
On the AMD A10-9600P, mpv's vaapi-copy dropped many more frames than software decoding (ORDER 234), because Mesa's RADV offers no `VK_EXT_image_drm_format_modifier` before GFX9 and libplacebo cannot import VA-API surfaces there.

These checks run in containers with a GPU's render node and never touch a desktop session or a screen.
Each mpv case starts its own headless Weston.

- `make-fixtures.sh OUTDIR` records the films: H.264 High 1920x1080 at 24 fps, 2D, side by side left first read as full views (`sbs.mkv`), side by side with the pair's width as display size, as the A10's Life of Pi (`sbs2.mkv`, read as half views), and top and bottom (`tb.mkv`), each declared by Matroska `StereoMode`.
- `hide-modifiers-layer.c` and `.json` are a Vulkan layer that hides `VK_EXT_image_drm_format_modifier` (and, through `SPARKY_TEST_HIDE_EXTENSIONS`, Vulkan Video decode), so a GPU that imports decoded surfaces behaves like the A10's Carrizo: libplacebo logs "no DRM modifiers" and mpv's VA-API interop fails exactly as on the A10.
- `mpv-case.py` plays one case and records mpv's decoder, its output picture and stereo mark, the relevant log lines and, with `--screenshot-at`, a "video" screenshot.
- `run-matrix.sh OUTDIR FIXTURES WORK` runs the matrix: zero-copy present (the GPU as it is, Vulkan and OpenGL), copy-only (`--a10`, the layer; and the null video output), the person's choices (`auto-copy`, `vaapi-copy`, explicit `vaapi`), the machine record (`CopyBack=true` and `false`), and software controls. `NOGPU=1` runs the cases without a GPU (none).
- `check-matrix.py OUTDIR [--before DIR] [--none DIR]` checks the rule, the left-first side by side declaration without a copy, the software decoding that replaces a copy-back for packings the CPU rearranges, and that every way of decoding gives the same picture (identical pixels and display size), against the published packages too with `--before`.
- `engines.sh OUTDIR FILM` checks MLT (`melt`) and VLC Stereo (`cvlc-stereo`), which copy every hardware picture back: software by default, hardware where copying back is allowed, hardware whenever the person names a decoder.
- `qt-route.sh OUTDIR FILM WORK` checks that Qt Multimedia, whose texture converters import decoded surfaces, keeps hardware decoding by default.
- `compare-a10.py BEFORE AFTER [--tolerance R]` compares two phases of the A10 bench (`packaging/a10-matrix.py`): drops per minute on the monotonic clock, restarts of a looping film's counters added, and the decoder and the Vulkan device of each case.

The published packages are expected to fail `check-matrix.py`, `engines.sh` and, with libmedia-gpu-route 0.2.0, `qt-route.sh`; the ORDER 234 cohort passes them.
