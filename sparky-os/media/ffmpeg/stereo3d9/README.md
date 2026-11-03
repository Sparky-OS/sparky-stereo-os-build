# ffmpeg-dmo 10:9.0.2-dmo1+stereo3d9: the six multilayer and AC-3 fixes

These twelve patches go on top of the published source ffmpeg-dmo 10:9.0.2-dmo1+stereo3d8+lc1 (deb-multimedia's FFmpeg with the edition's patches), as debian/patches 0055 to 0066; `series.add` holds the lines appended to debian/patches/series, and `changelog.entry` the changelog entry.
Each fix and its FATE test are separate patches, carried from the fork branches on code.ffmpeg.org (danielcamposramos/FFmpeg): hevc-ps-layer-id-mask, hevc-parser-au-split, vvc-parser-layer1, vvc-eos-recovery, vvc-layer-au and ac3-parser-short-header; each DEP-3 header names its fork commit, and `Forwarded: no` because the upstream pull requests are held.
Every fix applies to 9.0.2 unchanged; five test patches place their Makefile lines by 9.0.2's context, as each header says.
The full source package (.dsc and .debian.tar.xz) is published with the binaries.
