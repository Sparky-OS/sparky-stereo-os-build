# ffmpeg-dmo 10:9.0.2-dmo1+stereo3d12: the h264_sei header bound and the stereo3d eye order, on top of +stereo3d11 (ORDER 425)

The package carries the whole series of +stereo3d11 (patches 0010 to 0013 and 0068, the frame_packing option of FFmpeg pull request 25395 after review) and five patches more:

| Patch | Pull request | What |
|---|---|---|
| 0069 | 25409 | avcodec/h264_sei: bound payload header accumulation |
| 0070 | 25409 | fate/h264: test SEI payload header bounds (fate-h264-sei-header) |
| 0071 | 25377 | avfilter/stereo3d: preserve eye order for interleaved columns |
| 0072 | 25377 | avfilter/stereo3d: select the correct mono view from interleaved rows |
| 0073 | 25377 | fate/filter: test more eye order selections of stereo3d |

Each patch has a DEP-3 header: `Origin` names the fork commit on code.ffmpeg.org (danielcamposramos/FFmpeg) at the head of its pull request on 2026-11-06, `Forwarded` is the pull request.
They were ported from the pull requests to the 9.0.2 tree (with the series of +stereo3d11 applied), not from master.
The code hunks apply with a line offset only (libavcodec/h264_sei.c one line, libavfilter/vf_stereo3d.c minus 116 lines).
Only the FATE wiring differs: in 0070 the `TESTPROGS` line of libavcodec/Makefile and the `fate-h264-sei-header` block of tests/fate/libavcodec.mak sit at the same place in their lists but beside the neighbours 9.0.2 has (the pull request's context names `hw_base_encode` and `enc-recon`, which 9.0.2 does not have).
Pull request 25377 had a third commit pushed on 2026-11-06 (3cd1362c43); the patch carries that one, with its Signed-off-by.

Route: `sparky-os/packages/ffmpeg-dmo/make-source.py PLAIN0 ORIG OUT PLAN` where PLAIN0 is the plain source of the published +stereo3d9+lc1 (`dpkg-source --skip-patches -x` of the published .dsc, then `plain-from-lc.py --save-plan PLAN PLAIN0`, ORDER 435), as +stereo3d11 did.
The script adds the patches and series of this folder and two changelog entries: this folder's and the one of ../stereo3d11, which was never published; the dates of both come from the recipe commits (repo/reproducible.py, ORDER 421), so the same commit gives the same source.
+stereo3d10 (ORDER 410, branch order410-ffmpeg-hwaccel) is still not published or staged; if it ships, merge it into one source with this recipe.
