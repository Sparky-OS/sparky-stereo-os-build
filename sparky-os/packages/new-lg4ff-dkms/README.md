new-lg4ff-dkms for Sparky Stereo OS: the DKMS source of the upstream wheel driver with the edition's udev rule.

`debian/` is the recipe: the plain Debian directory of the published source (`0.5.0+git20261010.2092db1-1+stereo3d3+lc1`, made by the sim-rigs lane on 2026-10-10 and carried through Lean Code since), with the changes its changelog names on top.
The upstream tree is the published orig tarball; `debian/upstream-source.json` names its upstream commit.

Next version: from the published +lc1 source and this directory, with Lean Code's toolkit and the source-consumer plan the published source kept:

    python3 sparky-os/repo/lc-successor.py --recipe sparky-os/packages/new-lg4ff-dkms/debian PUBLISHED.dsc OUT

then build the new `.dsc` (`dpkg-buildpackage` in a fresh debian:testing container; `lean.debhelper` seals the payload with its HR companion).
Check: `python3 sparky-os/repo/check-payload-build-records.py` on the built archives (no `.sparky-lc` in the payload).
