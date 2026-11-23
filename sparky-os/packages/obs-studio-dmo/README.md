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

From `+stereo3d2` (milestone 3) a side by side canvas is drawn once per eye, and OBS's own views of it can be 3D areas:

| Patch | What it does |
|---|---|
| 0008 | libobs: a side by side canvas drawn once per eye, in one eye's space; a display with two views (`obs_display_set_views()`); the layout taken in the same video reset as the size (`OBS_STEREO3D_FLAG_AT_RESET`) |
| 0009 | the frontend: scenes, the preview, the projectors and the multiview in the canvas's scene space (one eye); each display handed to a module through the widget's `obsDisplay` property |
| 0010 | obs-filters: Render Delay keeps each eye's frames apart |
| 0011 | media playback: a stream's own stereo mark handed on (`get_stereo3d`), frames in turn and the two views of an MV-HEVC stream paired at the Stereo input filter's request (`set_stereo3d_pairing`). Pairing frames in turn here is a copy of the stereo layer's own rule; queue row 839 moves it (one sequence pairing and one AVStereo3D mapping exported by the layer, used by OBS and Stereo HandBrake) |
| 0012 | obs-websocket: a hotkey triggered by name (`TriggerHotkeyByName`) runs on the UI thread, as a key press does; it ran on obs-websocket's own request thread, where the preview's hotkeys showed and hid widgets off Qt's main thread and the program died at a show |
| 0013 | obs-ffmpeg: the custom FFmpeg output's raw callbacks and its stop share a lock on the encoder's data; a frame still being encoded after the stop met a freed encoder (SIGSEGV at the stop; upstream's report of the same race: obs-studio issue 14153) |

OBS's own screenshots of a 3D canvas stay one picture until the stereo layer writes a marked PNG from pixels (queue row 798).
The module `sparky-stereo-obs` sets the layout (its "Enable 3D", on by itself when the desktop is in 3D).
Nothing of this goes to OBS: its contribution rules ask for human-written submissions only.

Build: `OUT=... SRC=... IMAGE=... SCRATCH=... SPARKY_LC_ARCHIVE_DIR=... REPO=... bash build.sh` (see the script's header).
