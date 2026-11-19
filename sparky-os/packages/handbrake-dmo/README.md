# HandBrake stereo successor

Build the committed order742 branch of Sparky-OS/HandBrake, based on 1.11.2.
`export-source.py FORK DMO_DEBIAN_TAR OUTPUT` records the fork commit in the
upstream source version and exports DMO packaging before adaptation.
`prepare-source.py SOURCE` adds edition library dependencies and Lean Code.
Contrib archives are neither fetched nor linked.

The fork adapts Debian 1.11.2+ds1's shared-library patches while retaining FDK-AAC,
Dolby Vision, NUMA, NVENC, NVDEC, VCE and QSV. Debian's ambient-viewing and Dolby
Vision removal patches are omitted: the owning shared libraries carry those APIs.
The three deb-multimedia binary names and epoch are retained.

Upstream stereo metadata and x264 commits retain their authors; spherical
metadata preservation is their prerequisite. x265 frame packing and SEI scanning
are separate commits. Installed sample and package comparisons qualify binaries.
