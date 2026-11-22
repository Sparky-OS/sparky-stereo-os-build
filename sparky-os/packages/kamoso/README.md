# Kamoso stereo viewfinder

The recipe preserves the session default camera patch and adds a viewfinder that reads the Camera page's packing choice.
The edition's stereo layer separates the views, and Qt Multimedia places their native sample grids in a declared child surface.
Enable 3D uses the shared action; the settings drawer links to Camera Settings and Display Settings.
The original GStreamer viewfinder remains the 3D-off path.

The recipe requires the exact stereo-layer siblings in `layer-1.23.2.sha256` through `LAYER`.
Install those siblings before installing build dependencies, and keep the same packages available to the link gate.
`build.sh` verifies their checksums and installed version and passes their paths to the gate.
The existing Lean Code preparation and release checks remain in place.
The binary dependencies explicitly require stereo-layer and stereo-policy 1.23.2 or later.

With `BUILD_TESTING=ON`, CTest checks native eye sizes and pixels through GStreamer's appsink and Qt's video sink, caps declarations, both eye orders, and temporal gaps and discontinuities.
