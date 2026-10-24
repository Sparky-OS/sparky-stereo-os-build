# Decoder defaults

These patches prepare the shared engines used inside Sparky Stereo.
mpv, Haruna and mpvqt use the libmpv default unless the person selects a decoder.
Dragon, Gwenview video and other Qt Multimedia clients already select hardware automatically and retain their shared precision guard.
MLT selects CUDA or VA-API automatically for Kdenlive, whose new default selects that shared engine behavior.
VLC Stereo uses a precision preserving hardware copy path independently of the display importer, when copying back is allowed or the person names a decoder.
Since ORDER 234 hardware decoding that copies every picture back is the person's choice, or the machine's measured record (`CopyBack` in group `[Decoding]` of `sparky-stereo-graphicsrc`), never the default: on the AMD A10-9600P it dropped many more frames than software decoding. The order is hardware whose pictures the output imports, then software, then copy-back by choice; `tests/copy-back` holds the checks.
The software choice remains available in every engine.
The FFmpeg patch is required before installing the new MLT and VLC builds because a declined hardware query must clear decoder private state.

`prepare.py PACKAGE SOURCE --version VERSION` adds the patches to freshly extracted plain Debian sources, including the accepted full side by side patches for mpv, MLT and Kdenlive.
It requires `quilt` and `dpkg` and deliberately rejects Lean Code source versions.
For MLT and VLC, also supply `--ffmpeg-min-version VERSION` naming the FFmpeg build that contains this cleanup.
For Kdenlive, supply `--mlt-min-version VERSION` naming this MLT build.
It writes those runtime dependency floors into Debian control rather than relying on installation order.
Choose unused release versions against the current repository before preparing release sources.
Use the existing edition packaging and Lean Code pipeline for builds and qualification after this plain source preparation.
Do not publish these source preparations as a qualified Lean Code release.

The NVIDIA installer and ISO add `libnvcuvid1` at the graphics module version, which depends on matching `libcuda1`, plus `nvidia-vaapi-driver`.
Mesa VA-API and Intel media drivers remain in the existing edition package lists, including the legacy i965 driver in the base image.
The patch tests run only in disposable containers and do not install anything on the host.
`tests/check-results.py WORK` checks the recorded fixture qualification tree made by the test harnesses.

Elsewhere, automatic decoding defaults are each project's choice.
The small FFmpeg cleanup is independent of the edition and can go upstream separately.
MLT automatic selection and VLC hardware copy improvements can be proposed independently with the precision and software fallback gates.
The edition default policy and its package dependencies stay inside Sparky Stereo until the respective projects accept an equivalent policy.

The test components expect `/w` to be an owned container workspace and `/kit` to mount this directory read only.
Build the probes with `tests/build-probes.sh` against the edition SDK image.
Generate recorded inputs with `make-fixtures.py`, `extra-fixtures.sh`, `cancel-recorded.sh` and `more-codecs.sh` using the installed edition FFmpeg, whose metadata options create the test declarations.
Run `before-defaults.sh` separately with the installed modules and libraries, then `qualify-gpu.sh` with the rebuilt codec library and the rebuilt VLC plugin mounted over the installed plugin.
Set `GPU=amd API=vaapi` with the AMD render node, or `GPU=nvidia API=cuda` with NVIDIA CDI.
Run `fallback.sh` in the NVIDIA container to record the format-query failure before the FFmpeg fix and the successful software fallback afterward.
Run `benchmark.sh` serially after other qualification jobs stop.
The checker distinguishes strict decoded-frame and downloaded-frame equality from video output presentation cadence, which can repeat or skip pictures.
It also checks the real VLC Qt interface in an isolated Weston headless session and the native libmpv client default.
The qualified binaries are diagnostic builds; use the normal package flags, dependencies and release gates for deliverable packages.

GPU routing also belongs to the shared engines.
ORDER 223's libplacebo patch, which kept the compositor's GPU first, is dropped again in +stereo3d2 (`patches/libplacebo-dmo/DROPPED`): on the A10 rendering on the Carrizo that composites the desktop dropped 589.6 frames a minute of 3D film in frame packing, against 65.3 on its discrete Hainan. libplacebo prefers the discrete GPU again; the display GPU stays a choice through Mesa's device selection and mpv's `--vulkan-device`.
MLT, Qt Multimedia and VLC use the adjacent `media-gpu-route` library to select a supported decoder on that display GPU before startup where possible.
The library can select another GPU for a source the display GPU cannot decode at its depth.
Its runtime must be built first.
For these three sources, pass `--gpu-route-min-version VERSION` in addition to the FFmpeg floor.
The preparation helper inserts both the build dependency and the runtime floor.
For Qt Multimedia it also retains the accepted full side by side Quick surface patch.
`prepare.py libplacebo-dmo` prepares libplacebo for all its consumers, including mpv, and drops the patches `DROPPED` lists.
No per-film rule or user configuration file is installed.
The renderer still owns hardware surface import, copy fallback and transfer to the compositor.
GL follows the window system's display device; this change does not force a global DRI_PRIME value.
The routing probes use one fresh private compositor session per case and clear compositor-only device controls before launching clients.
They measure virtual output presentation and must not be reported as physical connector, HDMI or TV timing proof.
