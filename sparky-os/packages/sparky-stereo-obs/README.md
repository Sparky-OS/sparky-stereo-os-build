# sparky-stereo-obs

The edition's stereo module for OBS Studio, a native integration pack (skill `stereo-integrations`).
It is built against the OBS the edition installs, deb-multimedia's `obs-studio` and its `libobs-dev`, and loads with nothing to click from OBS's system plugin folder (`/usr/lib/<triplet>/obs-modules/plugins/sparky-stereo-obs.so`, data in `/usr/share/obs/obs-modules/plugins/sparky-stereo-obs/`).

- **Tools, Stereo 3D…** holds a program's three 3D options: "Enable 3D", the render resolution per eye (1920 × 1080 by default) and "Display Settings…".
  Enable 3D sets the canvas (Settings, Video: base and output resolution) to two eyes side by side, left eye first; off, the canvas the person had returns.
  The dialog says, for the recording and the stream, which 3D marks the next start will carry and why any will not.
- **The marks are written while encoding.** x264 writes the frame packing arrangement SEI (H.264 V16 D.1.26; type 3, side by side, Table D-9; content interpretation 1, frame 0 the left view, Table D-10) through its own `frame-packing=3` option, which the module adds to every x264 encoder of the main canvas before a start and takes out again on a 2D canvas.
  OBS's other encoders cannot be told the layout from a module (VA-API through OBS's FFmpeg path, its own NVENC and Quick Sync, AMF, OpenH264, the custom FFmpeg output, AV1, which has no such message), and neither can OBS's muxers write Matroska's StereoMode or MP4's st3d: before each start OBS says so, once a session in its window and always in its log.
  The first keyframe of every running output is read, and a missing message is told.
- **The Stereo input filter** takes a source in any packing of the stereo layer's input list (`stereo_policy_input_format_at()`) to full side by side, each eye at the resolution it has, every sample copied, never resized: side by side, top and bottom, rows, columns, checkerboard, side by side quincunx, both eye orders, the three anaglyphs, Not 3D, and Automatic by the layer's video rule. It offers "Swap left and right eyes" per source. Frames in turn, both views in one block and picture-and-depth inputs are listed and not converted yet: the filter says so where they are chosen.
- On a 2D canvas the module changes nothing in what OBS writes.

The words shared with every program of the edition ("Enable 3D", "3D Input Format", each packing, "Swap left and right eyes", "Display Settings…") come from the stereo layer's catalogue; the module's own sentences are in `data/locale`, in the ten required languages.

Build: `OUT=... IMAGE=... SCRATCH=... bash build-in-container.sh` (the builder image carries `debian/control`'s Build-Depends). The module's unit test (`tests/test-sei.c`) runs in the build.
