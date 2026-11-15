# kamoso +stereo3d1 (ORDER 570)

Debian's kamoso 26.04.0-1 with one patch, `patches/0001-follow-the-session-default-camera.patch` (DEP-3 header inside): with no camera chosen
in Kamoso, it takes the camera the session names as its default video source (PipeWire's "default" metadata, key default.video.source,
which the Camera page of System Settings sets); a camera the person picks in Kamoso's own list stays theirs (kamosorc, `deviceChosen`).
Build: `apt-get source kamoso`, copy the patch into debian/patches with a `series` file, `dch --newversion 26.04.0-1+stereo3d1`,
`dpkg-buildpackage -us -uc -b`. Proof (rig of the lane): follow-kamoso.sh, three defaults, red on the published build, green on this one.
Not yet through the Lean Code route: Debian's source is not an lc1 source, so the +lc1 successor is the publication round's step.
Upstream (invent.kde.org/multimedia/kamoso): nothing merged or open for this on 2026-11-15; open MR 62 (remember the chosen camera, camera switcher) is related.
