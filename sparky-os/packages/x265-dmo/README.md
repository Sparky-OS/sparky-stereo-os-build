# x265 shared library for stereo media

Start from deb-multimedia's x265-dmo 1:4.3-dmo1.
The three commits merged through upstream PR 986 add frame packing and its frame-duplication and intra-refresh fixes.
Additional credited HandBrake patches preserve ambient viewing metadata, Dolby Vision RPU lifetime, motion-vector bounds and platform behavior.
The H.273 backport keeps the existing `ipt-pq-c2` name and adds matrix coefficients 16 and 17.
The upstream aq-motion fix is already present in this release.

Frame packing changes upstream's ABI from 217 to 218.
The additional ambient fields are appended after that API and assigned ABI and SONAME 219; existing fields retain their offsets.
`libx265-219` coexists with `libx265-217`, so installing it does not remove consumers of 217.
FFmpeg and HandBrake must be rebuilt against the new development package to use the added API.
The package comparison and loader qualification must verify the exact installed result.
