# Stereo saver prototype

Run `./test.sh` in the repository. It uses the `gl-stereo-test:3` image,
a private Xvfb with llvmpipe and uid/gid 1000. The tested image digest and
the current evidence are in the test record, not public yet. No host display,
authentication program or power configuration is used.

`starfield` owns one star array and advances it once per frame. Its two
off-axis cameras use native GLX eye buffers through this layer. Convergence
is 5, infinity disparity is 1% of one eye's width, and stars smoothly fade
between depths 7 and 5 before respawning. The central prompt region is empty.
Oracle and standalone-eye options are diagnostics, not rotation settings.

`rocks-sbs.patch` applies to Debian's XScreenSaver 6.09 source. It adds `-sbs`
using the existing depth-dependent eye positions, with each eye clipped to
its full-size half. `-3d`, its red/blue colours and its existing delta option
remain unchanged and undeclared. The SBS profile uses delta 0.12 and recycles
rocks before their disparity crosses the screen plane. `-sbs-delta` is an
internal profile/debug parameter, not a KWin output selector. Neither saver
adds class metadata. The patched rocks binary calls the accepted format-only
shared helper and exports its finished Xlib frame through `x11-frame.c`.

Source: https://deb.debian.org/debian/pool/main/x/xscreensaver/xscreensaver_6.09+dfsg1.orig.tar.xz

SHA256: `678cbcbe8e15cc5789c9a9cec8e5419a001668dd7cbb884c11ca7ffe9ff4600e`.
`build-rocks.sh` checks that hash, builds only the hack, and removes source and
build scratch. It does not build or install XScreenSaver's locker. Upstream's
copyright and permissive notices remain in the source. ROCKS-COPYRIGHT contains
Debian's attribution/licence index; the new transport and controller are
GPL-2.0-or-later. No proprietary code is used.

## Frame channel

The launcher passes a connected Unix SOCK_SEQPACKET socket as
`GL_STEREO_FRAME_FD`. One packet contains a 32-byte little-endian header and
exactly one SCM_RIGHTS descriptor. The eight header fields are:

| Field | Value |
|---|---|
| magic | ASCII `SD3F` |
| version | 1 |
| width | packed width, even, 2–8192 |
| height | 1–4096 |
| stride | width × 4 |
| sequence | increasing, nonzero |
| bytes | stride × height, at most 64 MiB |
| pixel format | 1: bottom-up RGBA8 |

The FD must be a regular memfd owned by the session user, exactly the stated
size, sealed against writing, shrinking, growing and changing seals. The
receiver closes every received descriptor on malformed/truncated input. It
closes a consumed frame before acknowledging its sequence as one little-endian
32-bit integer. The producer permits one outstanding frame. It continues the
simulation while waiting and skips capture; it never blocks the GL/Xlib draw
on a slow consumer. Optional readback has a cost and is not zero-copy.

`frames.py` is a standalone validating broker. `controller.py` combines the
same validation with process supervision, a private Xvfb, and random rotation.
It accepts a trusted package-generated catalogue, an inherited control socket
and an inherited consumer socket. No saver-provided message selects a program.
The consumer channel carries pixels only. A separate display surface for the
2D prompt remains the proposed greeter integration; no authentication code is
present in this prototype.

## Eligibility and lifecycle

`tests/qualify-savers.py` writes receipts only after camera/depth oracles pass.
Receipts bind the exact command/profile, executable and layer hashes to the
proof. The resulting catalogue includes every passing candidate; failures
stay out. Camera and comfort checks are configuration-specific. The automatic
profiles use 1% separation and convergence 1; molecule disables shells/labels.
The generated catalogue is a trusted packaging artifact, not a file to accept
from a saver process. Regenerate it for installed paths and binaries during
package validation. Development receipts contain workspace paths.

The package build runs these checks (`packaging/qualify-package.sh`). Each
wait on a saver, for its captured frame, a frame from its stream or its exit,
ends when that arrives, up to `GL_STEREO_TEST_SECONDS` (60 by default), so a
loaded build machine waits longer instead of failing.

The controller shuffles bags of all eligible entries and avoids immediate
repeats. A failed/stalled producer is excluded for the session. No eligible
entries means no frames, so the consumer uses its static background. The
consumer must also return to its static background on EOF, malformed packets,
stalled delivery or inactive Plasma state. A hung consumer stops the controller
after a transport timeout. That timeout is not an idle or power timer.

Control packets are at most 256 bytes of JSON. State is exactly three booleans:
`locked`, `display_on`, `on_ac`. Render only when all three are true.
`{"event":"rotate"}` comes from the Plasma rotation setting;
`{"event":"shutdown"}` terminates the controller. No idle-duration default
or power action exists in this code. Preserve the 2 h 45 min screen-off/lock
and 4 h plugged-laptop sleep policies as described in SCREENSAVER-DESIGN.md.

The test consumer renders an identical screen-depth prompt in both halves
of a received frame. It is explicitly a mock, not the Plasma greeter or a
replacement authentication UI. The real greeter adapter and Plasma settings
wiring require review and integration against the edition's sources.
