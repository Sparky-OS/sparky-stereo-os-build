# Container GPU routing tests

Use an owned SDK with the edition's Vulkan, Mesa device selection layer, EGL, VA-API, CUDA, NVDEC, private KWin and Weston.
Create no connection to a host compositor or D-Bus session.
GPU containers run as uid 1000 with four CPUs and core dumps disabled.
The KWin fixture needs `SYS_NICE` for its packaged file capability.
The compositor control module only reorders KWin's DRM enumeration and is removed from client environments before any player starts.
It preserves both GPUs and their real driver capabilities.
Verify the renderer in the saved KWin support information.

Mount the new routing workspace at `/w`, the previously qualified fixture and software reference workspace read only at `/prev`, and this directory read only at `/kit`.
Build `media-gpu-route` into `/w/route-build` and install it to `/w/route-prefix`.
Build the patched libplacebo in `/w/placebo-build`.
Set `PKG_CONFIG_PATH=/w/route-prefix/lib/pkgconfig` when building the decoder engines.
`build-mlt.sh` and `build-vlc.sh` use fresh build directories under `/w`.
Build the Qt FFmpeg plugin under `/w/qt-build`.
Compile the two choice probes with `-Wall -Wextra -Werror` and their pkg-config libraries.
Compile `compositor-device.c` as a shared module with libdrm and libdl.
The decoder choice probe also links libavformat, libavcodec and libavutil.

For the host fixture with Renoir at renderD128 and RTX 3060 at renderD129, `run-engine-matrix.sh` supplies each GPU alone and both hybrid display preferences.
It checks nine driver capability cases and seven native recorded media cases per decoder engine, including H.264 High 10 software fallback, HEVC 12 bit, 2D, eye reversal and cancellation.
The shell runners take the granted Docker endpoint and owned workspace, test directory, SDK image and name prefix from the `SPARKY_*` variables checked at startup.
They do not contain a machine endpoint or private workspace path.
Set `COMPOSITOR_RENDER_NODE` when the virtual compositor's render node differs.
Adapt the explicit fixture expectations before using a different GPU pair.
These assertions describe the supplied fixture hardware, not a player policy based on GPU model names.

Run `check-engines.py ROUTING_WORK DECODER_WORK` after the native matrix.
Qt and MLT luma output must equal their qualified software reference byte for byte.
Every VLC presented luma picture must be an exact source picture, allowing presentation repeats and skips.
Each decoder trace must retain depth, stereo layout, eye order, cancellation and the expected supported backend.
The accepted decoder harness separately covers all-component downloaded frame equality.
The new route checker does not claim to capture every chroma plane through every GUI.

Generate continuous 20 second performance files with `make-performance.sh` before the rendered matrix.
Run `run-render-matrix.sh` serially after other lane jobs stop, with `RUN_PREFIX=continuous`.
It launches a fresh private KWin with one or two virtual outputs for each GPU case, then renders 2D and stereo media through Vulkan and GL.
`PAIRS`, `SCREENS` and `RUN_PREFIX` can select a smaller rerun without overwriting a failed case.
The player records IPC counters, process CPU time, its real driver log, Wayland traffic and native `video-flip` timing.
Count flips over the five second interval starting one second after the first flip to report VO flips per second; this is virtual presentation, not physical scanout.
The table must identify source frame rate, dropped frame counters, GPU names and any hardware download or cross-GPU transfer.
Do not call a virtual stereo-content case a physical HDMI frame packing test.

`prepare-packages.sh` verifies the exact Debian patch stacks and runtime floors against pinned plain sources.
The diagnostic version suffix in that test is not a release version reservation.
Run the existing edition packaging and Lean Code qualification pipeline before release.

`capture-clients.py` and `capture.lua` take GPU-rendered screenshots after playback restart, rather than issuing a screenshot before the first frame is ready.
Run them through the same private KWin fixture for both hybrid display preferences.
The RGB PNGs preserve 16 bit output and are compared with software decoding by `check-captures.py`.
Their dimensions follow mpv's screenshot display aspect; they are not a raw handoff raster witness.
The native decoder checks retain that raster witness.
`render-table.py WORK` checks GPU identities, decoder APIs, stereo declarations and counters while generating the host matrix table.
`ROUTE_BEFORE=1` is a test control that loads the installed libplacebo for a before comparison.
It is never installed as a user configuration setting.

`before-engines.sh` uses the accepted decoder binaries and installed Qt plugin on an AMD compositor with both GPUs visible.
Mount the accepted VLC plugin for this control.
All three old automatic defaults select CUDA, so each display-route assertion records exit 1.
The corresponding rebuilt native route assertions must pass before accepting the new defaults.

Continuous fixtures avoid player loop-boundary seeks and stereo reconfiguration inside the timing interval.
The 2D load is H.264 1920x1080 at 48 fps from testsrc2.
The 3D load is a stream-copy extension of the owned H.264 1920x540 at 48 fps source.
The timing checker requires no settled VO drops and at least 98% of source cadence.
It still reports startup drops and sampled decoder counters separately.
