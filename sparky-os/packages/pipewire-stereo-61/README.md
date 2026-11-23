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
