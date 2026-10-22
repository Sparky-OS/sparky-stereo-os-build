# Stereo lock-screen backgrounds: design for review

2026-10-12. The producer, validating broker, supervisor, eligibility generator,
starfield and rocks SBS path are implemented and tested in private containers.
The greeter and Plasma settings integration remains a proposal. No changes to
Plasma, PAM, session settings or power policy have been made. See savers/README.md
for the implemented wire protocol and test commands.

## Rendering and trust boundary

A session-side controller starts one saver process at a time on a private
headless display, without the session's display socket or authentication input.
GL savers render full side by side through gl-stereo; rocks uses its native
Xlib eye positions. Each producer exports the finished pair to a separate
validating broker. The greeter receives pixels, never a saver plugin,
executable, script, shader, filename to open, or input handler. The existing
authentication path owns every unlock input event.

The proposed transport is a local socket handed to the greeter by its trusted
launcher, with bounded fixed-size messages and sealed shared-memory frame
buffers. The broker validates dimensions, byte count, stride, pixel format,
frame sequence and ownership before handing a frame to the greeter. The prototype
uses one uncompressed pixel format and one outstanding frame per producer.
Slow consumers cause producers to skip new captures; a stalled or dead saver
must not block unlock or keep the display on.
The greeter has its normal static background when frames are absent or invalid.
Exact socket ownership and greeter lifecycle integration need review against
the Plasma version being packaged; no security approval is inferred here.

The 3D area is a separate declared surface below the undeclared 2D unlock
surface. KWin repeats the latter at screen depth. Reserve a region for the
prompt and keep all saver geometry behind the screen plane; no positive-depth
geometry may occlude the prompt. If the greeter cannot provide this separation,
use a static background until its integration is implemented and tested.

Readback to shared memory is an explicit cost of crossing processes; it is not
a claim that the layer's direct-to-window rendering already exports frames.
A headless producer harness must prove the transport separately. A future
DMA-BUF path can replace the transport after buffer lifetime and synchronization
tests; it does not change the one-world/two-camera contract.

## Automatic rotation from evidence

Generate the candidate catalogue during package validation from successful
stereo oracle results, not from a hand-maintained list of presumed GL savers.
Each entry includes executable and library hashes, exact arguments, camera
settings, oracle version, analytic error and comfort bounds. An absent, failed,
stale or mismatched result excludes that entry. No shell command comes from a
saver process. Packaging resolves fixed executable paths and argument arrays.

The implemented controller shuffles the eligible entries into a random bag and avoids an
immediate repeat across bags. A crash or transport timeout removes that saver
for the session. An empty catalogue uses the static background. Existing
gears, opaque molecule and rubik results originally established stereo without
the stricter comfort bounds. In particular, molecule's negative disparities
in the accepted test were unsuitable for the proposed behind-screen comfort
rule. The new profile (convergence 1, separation 1%) passes the stricter
behind-screen bounds alongside gears and rubik. The generated catalogue now
contains those three, starfield and rocks, only when their tests pass.

## One world, two cameras

The inherited fixed-function layer uses the program's projection and gives
that view an off-axis eye projection. It keeps FBO work once today. That is
only sufficient for the current simple scenes, not a general classification
of all FBO work: shadow maps should be shared, while camera-dependent bloom,
AO and depth-of-field passes must have per-eye targets and camera values.
Camera constants, products, inverses and temporal history need explicit
tracking for shader applications; shaders themselves must remain unchanged.
An older shader-rewriting proposal is superseded by Daniel's guard.
Per-draw fallback must be identified as such, never reported as camera-pass
support. No claim of that future support is made by the output-only change.

## Starfield and rocks

Implement a small deterministic GL starfield with one world-space star array
and one simulation update per frame. It supplies a perspective camera to this
layer; stars have real depth. For near distance c (the convergence plane),
fade a star to zero before its depth reaches c, then respawn it farther away.
Use a small infinity disparity budget and bound motion between frames.
Test seeded frames against analytic disparity at several star depths, check
fade continuity, and reject empty eyes, swapped eyes and a shifted-copy
mutation. Only then add it to the generated rotation catalogue.

Obtain the packaged XScreenSaver rocks source and retain its licence. Preserve
the existing red/blue mode. Add a full-SBS path using its own left/right camera
rendering and libstereo-declare1, with simulation advanced once. A selectable
legacy/debug red/blue path must remain usable without declaring it as SBS.
Tests must compare each SBS eye to a reference render from the same rocks
camera, verify layout-only declaration and keep the existing red/blue output
covered. The prototype now implements both and checks analytic disparity,
single-eye reference renders, mutations and the retained red/blue output.

## Timing proposal for Daniel

Use only Plasma's session and power settings. Keep the approved desktop policy:
no automatic system sleep; screen-off and lock at 2 h 45 min. Keep plugged-in
laptop sleep at 4 h. Do not create a five-minute lock or ten-minute screen-off
timer, change text consoles, postpone screen-off, or wake a display for a saver.

Because the automatic lock and screen-off share the same deadline, that event
provides no visible saver interval. Proposed behavior: show the saver after a
manual/otherwise existing earlier lock only while the screen remains on, stop
at the existing screen-off event, and resume only when Plasma wakes the locked
screen. Disable saver rendering on battery. A visible interval at automatic
lock would require Daniel to choose a different policy in Plasma; none is
assumed or set here. Rotation duration is also a Plasma preference to be
decided, not a second idle or power timer.

## Next implementation checks

The broker/producer harness, malformed-frame checks, producer death, slow
consumption, starfield/rocks proofs, catalogue filtering, random selection and
state-driven shutdown tests now pass. Next review a concrete greeter adapter
against its source and run it only in a nested container session. Verify that
failed savers cannot alter real prompt/input handling or unlock. The current
mock consumer proves pixel delivery and screen-depth overlay placement only.
