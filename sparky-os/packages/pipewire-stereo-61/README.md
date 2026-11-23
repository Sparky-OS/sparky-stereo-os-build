# PipeWire GStreamer camera formats

The edition rig installs Debian pipewire 1.6.9-2. Its GStreamer adapter drops
multiview mode, flags and view count in both directions. The owning adapter now
carries the public mode values (including temporal and separated modes), fixed
negotiated flags and view count, without changing any pixels or dimensions.
The public values of both APIs are checked at compile time. Unconstrained flag
sets do not become a fixed format; partial flag-mask negotiation and temporal
buffer metadata are not established by the camera's side-by-side tests.

This successor is 1.6.9-2+stereo3d1+lc1. It retains Debian's source packaging and
applies the ordinary Lean Code preparation and release check. The outer package
build and source closure are still required; native plugin builds are not a
packaged successor. Kamoso depends on the new gstreamer1.0-pipewire binary.

Upstream default-branch history, multiview merge requests and issues were read
on 2026-11-23. The adapter in current main also lacks these fields. The three
issue matches concern documentation and older generic plugin/buffer failures;
no matching fix was found. Wim Taymans is the original adapter's author.

A native control tests every defined public multiview mode against independent
SPA parsing and the reverse GStreamer fields. A live source and consumer then
check the actual plugin boundary. Neither substitutes for buffer-level proof
of temporal or separated video: Kamoso publishes one complete side-by-side pair.

## Installed JACK examples

The two examples link PipeWire's JACK extensions, but the install step formerly
removed their build-tree run path. Debian pipewire-tests 1.6.9-2 then loaded
jackd2 and video-dsp-play failed at jack_get_video_image_size. Both examples now
keep an install RUNPATH to the configured libjack_path. This changes neither
the system JACK provider nor any other installed test's search path.

Debian intentionally excludes the private JACK libraries from dh_makeshlibs.
A SONAME-bearing library in another binary package without dependency metadata
makes dpkg-shlibdeps fail; --ignore-missing-info would hide that error. Instead,
the existing pipewire-jack.shlibs.local map is also used for pipewire-tests,
generating pipewire-jack (= ${binary:Version}). The same invocation explicitly
selects -Sdebian/pipewire-jack, so dependency analysis reads the staged library,
which has no generated shlibs file and is otherwise absent from its search roots. The noinsttest build profile
still excludes that package. No dependency check is suppressed. A pw-jack
wrapper would leave the installed ELF itself broken and change its invocation;
a global ld.so.conf entry would change unrelated JACK clients. RUNPATH keeps
the intended choice local and retains the ordinary LD_LIBRARY_PATH override.

Read-only search on 2026-11-23: PipeWire master 9638bb38ced9, Salsa
debian/master febdaec30c03 (1.6.11-2), both meson paths, merge requests and
issues for video-dsp-play, JACK examples, jack_get_video_image_size and
install_rpath; Debian SOAP package searches and all 120 current/archived pipewire subjects.
No matching fix was found. The examples/meson.build path does not exist;
the targets live in src/meson.build, unchanged since before 1.6.9. MR !2270
(2025-02-02) fixes includes, !3079 (2026-10-24) SPA types; issue #4832
(2025-08-04) concerns video rendering, #3811 (2024-01-25) builds without udev.
None repairs this installed library selection. The original JACK examples
and library are by Wim Taymans. The local install-path repair is by
Daniel Campos Ramos.

Starting the installed video example without a connected source exposed its
second defect: JACK supplies an audio-sized silence buffer, but the example
reads a complete 640 by 480 float RGBA image from it. GDB placed the out-of-bounds
read in process(), line 90. The same example patch keeps event handling alive
but waits for a connected input before reading an image, and checks the buffer
pointer. Current master has the same callback; its only newer commit on the
file, a60c4c7f9a91 (2026-11-19), changes include paths. The exact callback history,
MR and issue searches found no buffer-read fix. This is an example fix, not a
claim that the JACK video extension's general buffer negotiation is qualified.
