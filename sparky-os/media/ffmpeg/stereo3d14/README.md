# ffmpeg-dmo 10:9.0.2-dmo1+stereo3d14: the shape of an eye from a Matroska pair (ORDER 577)

The package carries the whole series of the published +stereo3d12 and two patches more:

| Patch | What |
|---|---|
| 0074 | avformat/matroskadec: keep a stereo display size that is the whole frame |
| 0075 | tests/fate/matroska: test the display size of stereo tracks (fate-matroska-stereo-display-size) |

FFmpeg's Matroska demuxer multiplied the display width of every side by side and column interleaved track by two, and the display height of every top and bottom and row interleaved one, since ec83efd4d3 (Aaron Colwell, 2015, committed by wm4), to undo what FFmpeg's own muxer writes: the size of one plane, as [RFC 9559](https://www.rfc-editor.org/rfc/rfc9559) section 18.10 describes it.
DisplayWidth and DisplayHeight default to the whole frame (sections 5.1.4.1.28.12 and 5.1.4.1.28.13), and mkvmerge writes the whole frame, so a film whose two views are whole pictures was shown with views of 32:9.

The rule Daniel agreed on 2026-11-15: the multiplier applies only when a view of the frame as declared cannot be a whole picture, that is narrower than 4:3 side by side (the frame's declared shape below 8:3) or 8:3 or wider when stacked (the frame's declared shape 4:3 or wider).
For a view whose real shape lies between 4:3 and 8:3 the result is right whichever size the muxer wrote (one plane, or the whole frame); a view of 8:3 or wider that a muxer wrote as one plane is read at half its width.
Checkerboard, anaglyph and block-laced tracks have no multiplier, before and after; DisplayUnit 4 (unknown) gives no sample aspect ratio, before and after.

Route: `sparky-os/packages/ffmpeg-dmo/make-source-stereo3d14.py PLAIN12 ORIG OUT PLAN`, where PLAIN12 is the plain source of the published +stereo3d12+lc1 (`dpkg-source --skip-patches -x` of the published .dsc, then `plain-from-lc.py --save-plan PLAN PLAIN12`; that source has no preserve plan, so PLAN stays unwritten).
The date of the source comes from the last commit of this folder or the script (repo/reproducible.py, ORDER 421).
Binaries: `release/build-from-lc-dsc.sh` for amd64 and i386 from the one .dsc.
The patches were written on the 9.0.2 tree with the published series applied; they are not on a fork branch or a pull request yet.
