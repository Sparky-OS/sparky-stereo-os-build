# Decoder defaults

These patches prepare the shared engines used inside Sparky Stereo.
mpv, Haruna and mpvqt use the libmpv default unless the person selects a decoder.
Dragon, Gwenview video and other Qt Multimedia clients already select hardware automatically and retain their shared precision guard.
MLT selects CUDA or VA-API automatically for Kdenlive, whose new default selects that shared engine behavior.
VLC Stereo uses a precision preserving hardware copy path independently of the display importer.
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
