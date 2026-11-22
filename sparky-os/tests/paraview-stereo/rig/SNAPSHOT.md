# The rig's Debian: snapshot.debian.org at 20261119T023717Z

Every image of this rig takes Debian testing (and testing-updates, testing-security) from snapshot.debian.org at one instant, `SNAP` in `prelude.sh`, so the rows can be rerun on any later day. deb-multimedia, which has no snapshot archive, comes from its frozen signed index in `$S/frozen/dmo` (`freeze-dmo-index.py`, `freeze-dmo-pool.sh`); libstereo-declare 1.12.1 from the copies in `$S/frozen/sd` (pinned at 1002 in the image, so pin 1001 does not bring back r1118a's 1.10.0); the published edition tree is r1118a's own folder. The Lean Code link gate of the vtk9 build reads the same instant (`archive-snap.json`).

## Why this instant

- r1118a's Release is dated 2026-11-19 06:12:32 UTC. Debian testing's index at this instant is dated 2026-11-19 02:12:54 UTC: the last index before the published tree was made, so the day the published edition was made against.
- The next index, 2026-11-20 02:11:10 UTC (instant 20261120T023438Z), replaced OpenImageIO 3.1 by 3.2 (libopenimageio3.1 left testing), and r1118a's Blender 5.0.1+stereo3d3 depends on libopenimageio3.1: from there on the tree no longer installs whole (`blender Depends libopenimageio3.1 (>= 3.1.18.1+dfsg) ... [no choices]`).
- The index of 2026-11-21 14:13:49 UTC brought KDE Frameworks 6.32 (libkf6xmlgui6, libkf6iconthemes6, libkf6iconwidgets6; libkf6parts6 at 2026-11-22 02:09 UTC). r1118a holds its own Frameworks 6.30 at pin 1001, so from that index its KWin no longer installs beside testing (`libkf6xmlgui6 Depends libkf6iconthemes6 (>= 6.32.0~)`): the hold the review met.
- The stage was built on the lane's builder image (made 2026-11-21 23:46 UTC from the 20:10 UTC index). Every staged package, the rig's set and KScreen's page resolve together on this instant (`apt-get -s install`: 1037 new, 0 to remove). The builder differs from this index in 26 packages (the compiler drivers 4:16.2.0-1 against 4:16.1.0-3, TeX Live, BLAS and LAPACK 3.12.1-9 against -8, p11-kit 0.26.6-2, jbig2dec, man-db, python3-packaging, a Perl module); none raises a staged package's Depends above this index, as the resolution shows.

The measurements: `check-tree-whole.sh` (each package of r1118a simulated alone on an instant: `runs/tree-whole-*.txt`), the indexes and the builder's `dpkg-query` list in `$S/read/snapshot/`, and `apt-distupgrade-TAG.txt` of each image (0 upgraded, 0 downgraded, 0 not upgraded).

## To move the instant

Set `SNAP` (environment of `make-rig.sh`, default in `prelude.sh`; `archive-snap.json` for the gate), rerun `check-tree-whole.sh NAME SNAP` and `freeze-dmo-pool.sh`, then `make-review-images.sh all`.
