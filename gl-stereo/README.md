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
| `GL_STEREO_DRIVER_VIEWS=1` | Leave a program's own two views to a driver with stereo configs (X11); gl-stereo-run sets it |
| `GL_STEREO_NO_DOUBLING_WAIT=1` | Do not wait for the compositor to double a declared X11 window (diagnostic) |
| `GL_STEREO_NVIDIA_OPENGL=zink\|nvidia` | gl-stereo-run's default OpenGL on a desktop that runs on NVIDIA's driver |
| `GL_STEREO_LOG=1` | Log observed unsupported/mono-sourced operations once to stderr |
| `GL_STEREO_DEBUG=1` | Geometry and binding diagnostics |

Validated scope and limits are in the test record, not public yet. The prototype is
not a universal GL implementation: automatic shader stereo, projection-changing
lists, automatic stereo during `GL_COMPILE_AND_EXECUTE`, per-eye post effects,
and automatic stereo on native Wayland and in OpenGL ES are not supported (a
program's own two views are, in both APIs). GLX quad-buffer
mode works with the program's shader rendering and framebuffer blits, as
exercised by ParaView. The loader interposition currently targets glibc on amd64.
The NVIDIA paths were measured under a headless KWin on an RTX 3060; no
television presentation was tested. No low-overhead performance claim is made.

On native Wayland, programs that draw their own two views get them from the EGL
where it has them (Mesa's EGL_EXT_multiview_window). On X11, with
`GL_STEREO_DRIVER_VIEWS=1`, which gl-stereo-run sets, the layer leaves such
programs to a driver with stereo configs of its own (Mesa's, also through zink);
preloaded without it, the layer keeps the packing, which its frame stream needs. Where the driver has none, as NVIDIA's OpenGL, the
layer provides the views: GLX quad-buffer configs on X11, and on native Wayland
EGL_EXT_multiview_window when the compositor offers version 2 of
`kde_stereo_content_v1` (the window's buffer is twice its width, each view
drawn into its half, the surface declared full side by side; the program keeps
its own viewport and fractional scale). Desktop OpenGL names the views
GL_BACK_LEFT and GL_BACK_RIGHT; OpenGL ES names them through
GL_EXT_multiview_draw_buffers, which the layer offers on such contexts (Qt picks
OpenGL ES on NVIDIA's EGL).

On X11 the layer declares a window when its context is first made current and
then waits, up to a second, for the compositor to double the window before the
driver sizes its buffers: NVIDIA's OpenGL missed a doubling that came later and
left the second view black. `GL_STEREO_NO_DOUBLING_WAIT=1` skips the wait (a
diagnostic control).

On NVIDIA, `gl-stereo-run --nvidia-opengl` chooses how such programs get their
views: `zink` (the default) runs them on Mesa's OpenGL over NVIDIA's Vulkan
driver, where the views are Mesa's own; `nvidia` keeps NVIDIA's OpenGL with the
layer's views. NVIDIA's EGL gives a window no second view itself (its window
surfaces take only one colour buffer). The launcher asks the OpenGL library
which vendor serves the display (EGL on Wayland, GLX on X11, with the program's
environment, so PRIME offload counts), so a machine whose desktop runs on Mesa
keeps Mesa. For zink it lists Mesa's EGL vendor before NVIDIA's, which NVIDIA's
Vulkan driver needs to start, and keeps Mesa's own presentation path, which
carries the two views (zink's Vulkan swapchain path, kopper, has none yet). The
settings dialog offers the same choice on NVIDIA machines;
`GL_STEREO_NVIDIA_OPENGL` sets the default.

No launcher is needed for that on Sparky Stereo OS: when NVIDIA's driver runs
the desktop, sparky-stereo-hardware makes zink the session's OpenGL for every
program (menu, panel, terminal), while KWin keeps NVIDIA's driver, and exports
the system choice as `GL_STEREO_NVIDIA_OPENGL`. With that default in place
(`SPARKY_STEREO_OPENGL=zink`), `--nvidia-opengl nvidia` and `--enable-3d off`
run the program on NVIDIA's own OpenGL.

The tested saver prototype includes starfield, rocks, automatic eligibility,
random rotation and a separate frame broker/controller. See
[savers/README.md](savers/README.md) for its protocol and
[SCREENSAVER-DESIGN.md](SCREENSAVER-DESIGN.md) for the proposed Plasma integration.
The test consumer is a mock; no authentication or power configuration is changed.
