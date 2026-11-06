# ffmpeg-dmo 10:9.0.2-dmo1+stereo3d11: the frame_packing option as FFmpeg pull request 25395 has it after review (ORDER 416)

The published source ffmpeg-dmo 10:9.0.2-dmo1+stereo3d9+lc1 carried the first revision of the series (12 October) as debian/patches 0012 and 0013.
This recipe replaces patches 0010 to 0013 with the corrected series of the pull request (series-v6, five commits after master 5d85b7bfb2, ported to 9.0.2) and adds 0068 after 0011 (`patches/series` is the whole new series).
Each patch has a DEP-3 header: `Origin` names the fork commit on code.ffmpeg.org (danielcamposramos/FFmpeg), `Forwarded` is https://code.ffmpeg.org/FFmpeg/FFmpeg/pulls/25395.
The six findings of the review of 31 October, their clauses and tests are in the lane report; the changelog entry lists them.
Patch 0010 leaves out the reference line of cbs-h264-metadata-sei, which 9.0.2 does not have.

Route: `sparky-os/packages/ffmpeg-dmo/make-source.py PLAIN0 ORIG OUT`.
lc-successor.py cannot be used: its --in-place --overlay keeps the old patched upstream tree, so replacing a patch makes `dpkg-source -b` stop with "unexpected upstream changes", and its --recipe mode allows only debian/ changes.
The script builds from the pristine upstream (`dpkg-source --skip-patches -x`, then plain-from-lc.py) instead, as lane 377 did.
Versions: +stereo3d10 was prepared by ORDER 410 (branch order410-ffmpeg-hwaccel) and never published or staged; if both ship, merge them into one source.
