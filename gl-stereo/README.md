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
Native stereo visuals are offered only with compositor stereo support.
The test helper announces that capability on its private Xvfb, never on the
host's desktop.

Build with `make -j4` after installing stereo-declare's development files.
Use `PKG_CONFIG_PATH` and `LD_LIBRARY_PATH` for a nonstandard helper prefix.
`make install DESTDIR=...` stages the library, launcher and documentation.
See [PACKAGING.md](PACKAGING.md) for runtime dependencies and edition notes.

Run `./test.sh` from this repository for a fresh non-root container,
private Xvfb/llvmpipe, helper build, output tests and screensaver suite. The
lane-owned image is `gl-stereo-test:3`, built from Dockerfile and listed in the
workspace `.artifacts`. No packages are installed by the test runner. Use
`GL_STEREO_TEST_SCOPE=output` for just the output/synthetic/state/EGL checks.
The historical `full` scope additionally requires ParaView and its Python
bindings in `GL_STEREO_TEST_IMAGE`; those are omitted from the smaller saver
image. The runner mounts only this
workspace read-write and the protocol/helper source read-only, and limits the
container to four CPUs. Artefacts go under `out/`.

The helper must include `dependency-patches/stereo-declare-format-only.patch`
or its upstream equivalent providing `stereo_declare_x11_format()`. The explicit
format-only entry point changes only the layout and prevents linking against
an old helper that would silently write class metadata. The runner applies
this patch to a small private copy of its sources.
It never changes the read-only shared checkout. The library declares full SBS
left first once per bound window, without adding or changing class metadata.
Program-owned class properties and KWin rules remain the program/user's choice.

Developer overrides:

| Variable | Meaning |
|---|---|
| `GL_STEREO=1` | Enable the layer |
| `GL_STEREO_PASSTHROUGH=1` | Disable stereo for comparison |
| `GL_STEREO_RENDER_RESOLUTION=WIDTHxHEIGHT` | Per-eye render dimensions |
| `GL_STEREO_SEPARATION` | Percentage of frustum width at convergence; default 2 |
| `GL_STEREO_CONVERGENCE` | Positive eye-space screen-plane distance; default five times near |
| `GL_STEREO_SWAP=1` | Reverse automatic-stereo eye correction for diagnosis |
| `GL_STEREO_DUMP=N`, `GL_STEREO_DUMP_DIR=...` | Capture selected frame N, once per window |
| `GL_STEREO_STATS=path` | Exclusive-create a dispatch-count JSON file on clean exit |
| `GL_STEREO_FRAME_FD=N` | Optional sealed full-SBS pixel stream to an inherited broker socket |
| `GL_STEREO_LOG=1` | Log observed unsupported/mono-sourced operations once to stderr |
| `GL_STEREO_DEBUG=1` | Geometry and binding diagnostics |

Validated scope and limits are in [REPORT.md](REPORT.md). The prototype is
not a universal GL implementation: automatic shader stereo, projection-changing
lists, automatic stereo during `GL_COMPILE_AND_EXECUTE`, per-eye post effects,
native Wayland and GLES are not supported. GLX quad-buffer mode works with the
program's shader rendering and framebuffer blits, as exercised by ParaView.
The loader interposition currently targets glibc on amd64. No GPU/TV/KWin
presentation was tested. No low-overhead performance claim is made.

The tested saver prototype includes starfield, rocks, automatic eligibility,
random rotation and a separate frame broker/controller. See
[savers/README.md](savers/README.md) for its protocol and
[SCREENSAVER-DESIGN.md](SCREENSAVER-DESIGN.md) for the proposed Plasma integration.
The test consumer is a mock; no authentication or power configuration is changed.
