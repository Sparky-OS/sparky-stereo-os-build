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

The programs' Depends carry floors on the cohort's libraries (FFmpeg +16, x264 +stereo3d1, x265 30219): shlibs alone
accept the published FFmpeg +15, and on a machine with the i386 FFmpeg libraries apt then kept the cohort back and Stereo
HandBrake ran on +15. `build-twin-i386.sh RECIPE_DIR IMAGE_I386 DSC WORK REPO [EXTRA_DEB ...]` builds the i386 twin of
x264-dmo, x265-dmo or ffmpeg-dmo from the source package its amd64 build wrote (`dpkg-buildpackage -B` on the same .dsc);
FFmpeg's twin needs the i386 libx265-30219 and libx265-dev as EXTRA_DEB.

An audio encoder this computer's FFmpeg lacks (Fraunhofer's fdk_aac and fdk_haac until `sparky-stereo-ffmpeg-fdk` has
run) is never replaced in silence: HandBrakeCLI stops before scanning and exits non-zero unless `--audio-fallback` names
another encoder, a job that names one does not start, and the window lists the two encoders and says how to get them.
