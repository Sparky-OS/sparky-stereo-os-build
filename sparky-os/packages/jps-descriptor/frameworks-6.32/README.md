# Frameworks 6.32 successor

This manifest starts from Debian testing 6.32.0-1 and the published edition source.
Run `sparky-os/release/prepare-frameworks-successor.py MANIFEST DEBIAN_INPUTS PUBLISHED_INPUTS WORK` inside a build container, then apply `lean.debian_prepare` and build the source and binaries with `dpkg-buildpackage -us -uc -j4`.
The descriptor hashes bind every component; the published patch series must match the manifest exactly.

The patches preserve edition behavior and Debian's new upstream fixes.
Rebased HEIF hunks retain the library-version metadata while selecting the stereo/depth image; rebased FFmpeg tests retain upstream location and Apple metadata cases alongside all stereo tests.
KImageFormats keeps the multi-binary debhelper form because Lean Code emits an HR companion; its published recipe already used that form.
KIconThemes keeps qt6-svg-plugins for its existing stereo SVG test.
The changelog, binary fixtures, added symbols, copyrights and installed-test harness of the published source are retained.

Build amd64 only.
Use the same signed archive snapshot for build dependencies and final link/upgrade qualification.
Record a clean recipe commit before the build; qualify every resulting binary and its source closure before publication.

The full upstream HEIF test set needs the JPEG decoder/encoder, JPEG 2000 encoder and FFmpeg decoder plug-ins as build dependencies. Debian’s ignored-test return is removed so an amd64 test failure stops the source build. The tests remain enabled and unchanged.
