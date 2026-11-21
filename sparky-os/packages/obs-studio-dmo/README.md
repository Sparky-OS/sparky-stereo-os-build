# obs-studio-dmo, the edition's OBS Studio

deb-multimedia's `obs-studio-dmo` 1:33.0.1-dmo2 (Christian Marillat) rebuilt as `1:33.0.1-dmo2+stereo3d1+lc1` with the patches in `patches/`.
libobs carries the main canvas's stereo layout (`obs_set_video_stereo3d()`, `obs_get_video_stereo3d()`, `obs_encoder_get_stereo3d()`, new symbols only), and the writers mark what they write while they work:

| Writer | Mark |
|---|---|
| x264 | frame packing arrangement SEI (H.264 D.2.26), from x264's own `i_frame_packing`, after the person's own options |
| VA-API through FFmpeg | the same SEI, written by the edition's FFmpeg from `AV_FRAME_DATA_STEREO3D` (stream and frames) |
| NVENC | the same SEI as an `NV_ENC_SEI_PAYLOAD`, H.264 and HEVC (H.265 D.3.16, types 3 to 5) |
| the muxer helper `obs-ffmpeg-mux` | Matroska StereoMode, MP4 `st3d` |
| the hybrid MP4 muxer | `st3d` in every visual sample entry |
| the custom FFmpeg output | the encoder's side data and the container's mark |

Not marked, and told by `sparky-stereo-obs`: Quick Sync (no payload route written yet), OpenH264, AV1 encoders (AV1 has no frame packing message; the container still carries its mark).
On a 2D canvas nothing changes.
The module `sparky-stereo-obs` sets the layout (its "Enable 3D", on by itself when the desktop is in 3D).
Nothing of this goes to OBS: its contribution rules ask for human-written submissions only.

Build: `OUT=... SRC=... IMAGE=... SCRATCH=... SPARKY_LC_ARCHIVE_DIR=... REPO=... bash build.sh` (see the script's header).
