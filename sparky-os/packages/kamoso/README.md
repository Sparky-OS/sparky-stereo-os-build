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

Fresh stereo photos use the edition KImageFormats MPO and JPS writers, which call the layer's descriptor writers. MPO is the study's first/default choice; JPS is selectable. The original JPEG path remains with 3D off. The destination is committed only after the writer succeeds.

Pass the checked declaration-library siblings through DECLARE as well as LAYER. Both successors enter a round only with layer 1.23.2 and stereo-declare 1.12.2; layer source closure remains row 742b's matter.

The source-ordinal sequence pairing remains local pending row 839, which will provide shared pairing and AVStereo3D mapping in the layer. This recipe does not build row 839.


Stereo recording feeds normalized native-size pairs to x264 with multiview caps and muxes Matroska or MP4 with the owning elements. The source is timestamped on the recording pipeline's clock, shared with automatic audio capture; no frame scaling or finished-file fixup occurs. MP4 requires the qtmux writes-st3d capability and the packaged plugin successor. The 3D-off camerabin recording path remains unchanged. VA-API and NVENC H.264/HEVC are named and refused before starting until their GStreamer elements pass the SEI gate.

The recording is finalized on EOS before moving to the destination. An existing destination is refused. A failed destination transfer retains the completed temporary recording and says its location. Incomplete encoding is not published as a finished recording. Native tests exercise both containers, four hardware refusals and destination preservation.

The effects sample keeps camerabin's asynchronous file lifetime: its temporary placeholder is removed before the fresh flat sample is written. Gallery pipelines create their GL sink on the render thread and remove bus watches before replacing or destroying their owner. Config's sample binding depends on Kamoso's value, not on itself. The Qt GStreamer plugin minimum also carries upstream's recreated-material caps fix; frei0r-plugins supplies the four original gallery effects that otherwise disappear. The original 2D gallery and filter route remain available.

For repeated MP4 starts/stops, acknowledge the existing recording action before
expecting a file. Fixed screen coordinates can stop reaching the toolbar after
notifications or layout changes. Keep the request, finalization, temporary path,
destination and filesystem move events together. The diagnostic messages do not
claim to repair the two earlier uninstrumented missing-recording observations.
A reproduction uses two pinned CPUs and work in Kamoso's own main thread; no
additional host load is needed.

The 31 existing effects now run as two independent ordinary GStreamer pipelines,
one per native eye, with separate filter history and identical input timestamps.
The application polls complete pairs without blocking its GUI thread or queuing
unbounded work. Effects feed the declared viewfinder, photos and recordings.
A missing or failed filter is named in the picker and viewfinder; the camera is
explicitly shown without that effect. The picker retains failed stereo previews
as named choices instead of silently removing them. No packing or output-format
list is added. Native tests enumerate the QML list itself, probe each eye's
unmodified input samples and dimensions, check history over three frames, and
compare a spatial effect with independent per-eye controls. Camera sequence
pairing still belongs to the future shared engine route, row 839.
