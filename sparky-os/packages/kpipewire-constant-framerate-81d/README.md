# A constant frame rate for a live stream (queue row 81, part D)

kpipewire 6.7.4-1+stereo3d9+lc1, from the published +stereo3d8+lc1.

What it is for: KWin sends a screen's frame only when the screen changes, and KPipeWire repeats the last frame once, to flush it.
A Throw of a still desktop to a Chromecast therefore carried two pictures and then none, while its sound went on; the receiver's player waited for the next picture for ever (BUFFERING at its time 0, measured on a real Chromecast on 2026-11-25).
At a constant 30 frames a second the same receiver played.
GNOME Network Displays gets the same with GStreamer's `intervideosrc`, which repeats its last frame at the negotiated rate, and mkchromecast with `videorate`.

## Files

- `patches/kpipewire-constant-framerate.patch`: `PipeWireBaseEncodedStream::setConstantFramerate(bool)` and `constantFramerate()`; the producer repeats the last frame that carries a picture once per frame interval of `maxFramerate()` while no new frame comes, and keeps doing so; a repeat is skipped while the encoder's queue is full. Off by default, so recordings and remote desktop sessions (KRdp) keep their behaviour. The repeat timer is made in `initialize()`, after `start()` set the rate, so its first interval follows the constant rate when it is on. Its autotest `testConstantFramerateInterval` is in `autotests/TestEncoder.cpp`.
- `changelog/kpipewire.items`: the changelog item.
- `next-source.sh PUBLISHED.dsc OUT`: the next +lc1 source (`repo/lc-successor.py --in-place --reapply-patches --overlay`), with the two new symbols in `libkpipewirerecord6.symbols` at `6.7.4-1+stereo3d9`.

The round script follows `../not-3d-thumbnail-581/round.sh` (the Lean Code migration image and `../depth-source/build.sh`); the row's lane did not run it: the link gate needs 12 GiB free on `/`, which the station did not have on 2026-11-25, and the migration image was not named for the lane.

## Proved so far

A development build (CMake, no packaging) in the loopback rig: the autotest passes, and a Throw of a still screen carries 31 pictures a second (340 pictures; before: 2), KPipeWire's frame statistics 29 to 32 frames each second.

## Search upstream first

KPipeWire's master (read 2026-11-25) has no repeat at all: its comment says the first frame "for a static screen, may be the only frame ever delivered". So this is our own patch; it is an upstream offer once the Throw has run on real devices.
