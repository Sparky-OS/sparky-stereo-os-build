# ffmpeg-dmo 10:9.0.2-dmo1+stereo3d10: pull request 25398

`next-source.sh PUBLISHED.dsc OUT` makes the source ffmpeg-dmo 10:9.0.2-dmo1+stereo3d10+lc1 from the published +stereo3d9+lc1 source (repo/lc-successor.py --in-place --overlay, so the published changelog stays a byte identical suffix of the new one).
`RED=1` makes the proof source +stereo3d10~red410 (patch 0052 removed, the test kept), never published.

What changes in debian/patches:
- 0052 is now the fix commit 60f372459e of Daniel's open pull request https://code.ffmpeg.org/FFmpeg/FFmpeg/pulls/25398 (fork branch hwaccel-fallback, code.ffmpeg.org danielcamposramos/FFmpeg) with its DEP-3 header: `Origin: other` names the fork commit, `Forwarded` names the pull request.
  The edition carried the same one-line change since +stereo3d6 as its own patch with another comment; the code is identical, only the comment is the pull request's.
- 0067 is the pull request's test commit efc1a824b6 (libavcodec/tests/get_format.c, fate-get-format), applied to 9.0.2 without change; it builds with libdrm, which debian/rules enables.

Qt Multimedia 6.11.2-3+stereo3d14 (packages/depth-source) depends on libavcodec63 (>= 10:9.0.2-dmo1+stereo3d10~) from this version on.
