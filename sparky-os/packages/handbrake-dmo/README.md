# HandBrake stereo successor

Build the committed order742 branch of Sparky-OS/HandBrake, based on 1.11.2.
`export-source.py FORK DMO_DEBIAN_TAR OUTPUT` records the fork commit in the
upstream source version and exports DMO packaging before adaptation.
`prepare-source.py SOURCE` adds edition library dependencies and Lean Code.
Contrib archives are neither fetched nor linked.

The fork adapts Debian 1.11.2+ds1's shared-library patches and keeps the build
switches for FDK-AAC, Dolby Vision, NUMA, NVENC, NVDEC, VCE and QSV.
The edition's FFmpeg is published without libfdk_aac (FFmpeg's LICENSE.md calls such a GPL build unredistributable);
`sparky-stereo-ffmpeg-fdk` rebuilds it with the profile `pkg.ffmpeg-dmo.fdk` on the person's computer.
So `check-required-encoders.py` runs in the rig against the FFmpeg built with that profile, not in the package build:
with it, HandBrake offers fdk_aac and fdk_haac as deb-multimedia's does.
Enabling HandBrake's FDK configure switch alone never provides the encoders; they come through libavcodec.
Debian's ambient-viewing and Dolby
Vision removal patches are omitted: the owning shared libraries carry those APIs.
The three deb-multimedia binary names and epoch are retained.

Upstream stereo metadata and x264 commits retain their authors; spherical
metadata preservation is their prerequisite. x265 frame packing and SEI scanning
are separate commits. Installed sample and package comparisons qualify binaries.
