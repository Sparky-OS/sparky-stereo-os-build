# gl-stereo

A GPL-2.0-or-later OpenGL stereo prototype for Linux. Fixed-function mono
programs draw each primitive into two halves of a full side-by-side window.
Native GLX stereo programs supply their own left and right views. The layer
uses the shared stereo-declare library; KWin chooses the display format.

```
./gl-stereo-run --settings -- glxgears
./gl-stereo-run -- glxgears -stereo
```

The settings are Enable 3D, Render resolution per eye, and Display settings.
Native stereo visuals are offered only with compositor support version 2.
The test helper announces that capability on its private Xvfb, never on the
host's desktop.

Build with `make -j4` after installing stereo-declare's development files.
Use `PKG_CONFIG_PATH` and `LD_LIBRARY_PATH` for a nonstandard helper prefix.
`make install DESTDIR=...` stages the library, launcher and documentation.
See [PACKAGING.md](PACKAGING.md) for runtime dependencies and edition notes.

Run `./test.sh` from this repository for a fresh container, dependency setup,
private Xvfb/llvmpipe, helper build, tests and benchmark. It mounts only this
workspace read-write and the protocol/helper source read-only, and limits the
container to four CPUs. Artefacts go under `out/`.

Developer overrides:

| Variable | Meaning |
|---|---|
| `GL_STEREO=1` | Enable the layer |
| `GL_STEREO_PASSTHROUGH=1` | Disable stereo for comparison |
| `GL_STEREO_RENDER_RESOLUTION=WIDTHxHEIGHT` | Per-eye render dimensions |
| `GL_STEREO_SEPARATION` | Percentage of frustum width at convergence; default 2 |
| `GL_STEREO_CONVERGENCE` | Positive eye-space screen-plane distance; default five times near |
| `GL_STEREO_CLASS=scientific` or `game` | Explicit application/profile class; absent or unknown means none |
| `GL_STEREO_SWAP=1` | Reverse automatic-stereo eye correction for diagnosis |
| `GL_STEREO_DUMP=N`, `GL_STEREO_DUMP_DIR=...` | Capture selected frame N, once per window |
| `GL_STEREO_STATS=path` | Exclusive-create a dispatch-count JSON file on clean exit |
| `GL_STEREO_LOG=1` | Log observed unsupported/mono-sourced operations once to stderr |
| `GL_STEREO_DEBUG=1` | Geometry and binding diagnostics |

Validated scope and limits are in [REPORT.md](REPORT.md). The prototype is
not a universal GL implementation: automatic shader stereo, projection-changing
lists, automatic stereo during `GL_COMPILE_AND_EXECUTE`, per-eye post effects,
native Wayland and GLES are not supported. GLX quad-buffer mode works with the
program's shader rendering and framebuffer blits, as exercised by ParaView.
The loader interposition currently targets glibc on amd64. No GPU/TV/KWin
presentation was tested. No low-overhead performance claim is made.
