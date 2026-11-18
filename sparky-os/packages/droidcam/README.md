droidcam 2.1.7: Dev47Apps' Linux client for the DroidCam phone app (GPL-2.0), built from the release tag v2.1.7 of github.com/dev47apps/droidcam-linux-client (commit c8a0cc97663d90fe427d2c623b202628f8e95a17).

Not in Debian (no source package in any suite, no open wnpp bug) and not in SparkyLinux's repositories (core and tiamat, read 2026-11-18): the edition carries it (Daniel, 2026-11-17: "if not, we keep it if sparkylinux itself won't host it").
The phone app is Dev47Apps' own and comes from the phone's store; nothing of it is in this package.

`make-orig.sh OUTDIR` makes droidcam_2.1.7.orig.tar.xz byte for byte the same each time, pinned by the tag archive's SHA-256, its commit and the git tree id.
`debian/` builds the client and the command line client with upstream's Makefile (USBMUXD and APPINDICATOR come from the environment: a value on make's command line would replace upstream's pkg-config call).
The bundled kernel module v4l2loopback-dc and the install scripts are not used; the package depends on Debian's v4l2loopback-dkms, which the client opens like any v4l2loopback device.
`tests/plain-build.sh` builds the package with dpkg-buildpackage in a container (the proof of the lane); `build.sh` is the recipe for the Lean Code route, copied from headsetcontrol's and not run in the lane that wrote it (it needs the migration image and the link gate's archive folder).
