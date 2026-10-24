# Native MV-HEVC spatial video

Use the recorded published source baselines with prepare-source.py, then build one source descriptor per project through its native Lean Code adapter.
Build and install the companion stereo-layer 1.12.0-1+lc1 first, including libstereo-av-dev and libstereo-av1.
Its Qt-free C boundary assembles the two native decoded views and preserves the presentation side data for the three FFmpeg consumers.
The original libstereo-layer and policy ABIs remain at soname 1.

| Project argument | Source baseline | Candidate |
| --- | --- | --- |
| mpv | mpv-dmo 1:0.41.0-dmo9+stereo3d6+lc1 | 1:0.41.0-dmo9+stereo3d7+lc1 |
| qt | qt6-multimedia 6.11.2-3+stereo3d9+lc1 | 6.11.2-3+stereo3d10+lc1 |
| vlc | vlc 3.0.24-1+stereo3d13+lc1 | 3.0.24-1+stereo3d14+lc1 |
| gwenview | gwenview 4:26.04.0-1+stereo3d6+lc1 | 4:26.04.0-1+stereo3d7+lc1 |

mpv and MpvQt consumers request the decoder's views and assemble them before the filter queue.
Qt Multimedia assembles them before its playback queue and carries their native geometry and base eye to its video outputs.
Gwenview connects those video frames to its existing stereo layer, with its existing per-file eye correction.
VLC retains the enhancement-layer configuration and presentation fields in its native MP4 reader and assembles views at the FFmpeg decoder boundary.
Its correction is kept beside its recent-file playback positions.
The VLC translation delta is kept separately under sparky-os/translations and applied as a separate package patch.
English uses the original source message; the other eight required languages have translated catalog entries.

The media stays unchanged.
The codec's signalled eye identities determine the pair, and the VPS base view is the ordinary fallback.
Each stereo video surface is left-first full SBS at the decoded view dimensions, declared once to Stereo KWin.
The compositor performs the output resize.
The added Qt StereoFlag values describe assembled multiview frames and their base eye, without changing the layout of QVideoFrameFormat.
Do not infer a half-resolution packing from the aspect ratio of an assembled pair.
