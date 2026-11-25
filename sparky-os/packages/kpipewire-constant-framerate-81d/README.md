# A constant frame rate for a live stream (queue row 81, part D)

kpipewire 6.7.4-1+stereo3d10, from ORDER 740's 6.7.4-1+stereo3d9 (HEVC stereo packing; staged and accepted, not yet published), which follows the published +stereo3d8.

What it is for: KWin sends a screen's frame only when the screen changes, and KPipeWire repeats the last frame once, to flush it.
A Throw of a still desktop to a Chromecast therefore carried two pictures and then none, while its sound went on; the receiver's player waited for the next picture for ever (BUFFERING at its time 0, measured on a real Chromecast on 2026-11-25).
At a constant 30 frames a second the same receiver played.
GNOME Network Displays gets the same with GStreamer's `intervideosrc`, which repeats its last frame at the negotiated rate, and mkchromecast with `videorate`.

## Why +stereo3d10, from ORDER 740's +stereo3d9

ORDER 740 staged its own +stereo3d9 (`order740-hevc-packing.patch`; KRdp +stereo3d9 depends on it).
A +stereo3d9 of this recipe from the published +8 would be a second, different +stereo3d9, and a later version without ORDER 740's patch would take the HEVC packing away from the phones.
So this source follows 740's: both patches in one series, 740's first.
`next-source.sh` takes only the .dsc 740 staged (its SHA-256 is in the script).

## Its version has no +lc1

The published +stereo3d8 has the 19 October adapter's shape: a bundled toolkit in `debian/sparky-lean` and versions without `+lc1`; the Lean Code mark is in each package's fields (`Sparky-Lean-Code: lc1 …`).
`repo/lc-successor.py --in-place` keeps that shape, so the next version is `6.7.4-1+stereo3d10` itself.

## The 12 GiB floor (a trap)

A build of the published +stereo3d8's tree with `dpkg-buildpackage` stops at `override_dh_builddeb` with `/: free space … is below root floor 12884901888`.
That is the toolkit the +8 source carries in `debian/sparky-lean` (19 October): its `Archive()` refuses a root floor under 12 GiB and its `release.py` defaults to 12.
Build main's toolkit has the house floor of 1 GiB (ORDER 638), and `lc-successor.py --in-place` replaces the bundled copy with it, so this source's gate uses 1 GiB.
A set `SPARKY_LC_ROOT_MIN_FREE_GIB` was not the cause; no builder image carries the toolkit.

## Files

- `patches/kpipewire-constant-framerate.patch`: `PipeWireBaseEncodedStream::setConstantFramerate(bool)` and `constantFramerate()`; the producer repeats the last frame that carries a picture once per frame interval of `maxFramerate()` while no new frame comes, and keeps doing so; a repeat is skipped while the encoder's queue is full. Off by default, so recordings and remote desktop sessions (Spectacle, KRdp) keep their behaviour. The repeat timer is made in `initialize()`, after `start()` set the rate, so its first interval follows the constant rate when it is on. Its autotest `testConstantFramerateInterval` is in `autotests/TestEncoder.cpp`.
- `changelog/kpipewire.items`: the changelog item.
- `next-source.sh BASE_DIR OUT`: the next source (`repo/lc-successor.py --in-place --reapply-patches --overlay`): this patch after ORDER 740's series, the two new symbols in `libkpipewirerecord6.symbols` at `6.7.4-1+stereo3d10`, the patch named in `debian/sparky-provenance-files`.
- `build.sh BASE_DIR WORK PUBLISHED_TREE ARCHIVE_DIR PREVIOUS_DIR` and `build-in-container.sh`: the source and the packages in one container of the Lean Code migration image (`SPARKY_BUILD_IMAGE`, a lane's own tag of `sparky-lc-migration:20261020`), the link and start gate against ORDER 740's packages, then `lean.release check-debs`, which writes the build record; after `../kpipewire-740/build.sh`.

## Search upstream first

KPipeWire's master (read 2026-11-25) has no repeat at all: its comment says the first frame "for a static screen, may be the only frame ever delivered". So this is our own patch; it is an upstream offer once the Throw has run on real devices.
