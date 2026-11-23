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

The processed pair is also published as a PipeWire Video/Source camera through
pipewiresink, with media.role Camera, side-by-side mode, two views and no
half-aspect or right-first flag. It keeps the native RGBA sample grid and
clock timestamps. Enable 3D off, a flat source, source replacement and program
exit remove the node. Kamoso excludes its output nodes from its camera inputs
so publication cannot feed back into capture, including across instances.
A publication failure is shown without stopping the viewfinder or recording.
No separate depth or output-format option is introduced.

The published GStreamer PipeWire adapter loses the layout in both directions.
The pipewire-stereo-61 recipe owns that repair; its new gstreamer1.0-pipewire
package is a dependency, alongside the already pinned layer/declaration and
GStreamer good successors. Independent native PipeWire parsing and ten exact
frames establish the output camera, separately from compositor rendering.

The clean replay exposed frei0r's shared C++ parameter metadata being rewritten
by simultaneous eye-instance construction (Cartoon aborted with a double free).
The frei0r-stereo-61 recipe owns the immutable-metadata fix; the camera requires
that successor too. The same 31 effects remain available and the per-eye
pipelines and algorithms are unchanged. A deterministic overlapping-construction
control fails before the header fix and passes after it.

Recording retains quality-based encoding: the original camerabin profile is
Ogg/Theora (quality 48) and Vorbis (quality 0.3), despite its .mkv filename.
Stereo uses H.264 for frame-packing SEI and Matroska/MP4 for their stereo marks;
Ogg/Theora cannot supply that mandated combination. H.264 uses constant-quality
mode with x264enc's own default quantizer and medium preset, without the
quality-changing zerolatency tune. These codec quality scales are different;
Theora 48 is not claimed numerically equivalent to x264's quantizer 21.
The RGB source retains 4:4:4 chroma through encoding. Matroska keeps the ordinary
Vorbis quality default. MP4's muxer cannot carry Vorbis, so that choice uses
AAC at the encoder's default; there is no invented cross-codec quality mapping.
No audio resampler or rate/channel restriction is added. A multiqueue joins the
branches without disabling x264 lookahead to avoid an audio/video queue stall.

If encoding falls behind, the source queue drops a complete stereo pair and
reports it once per recording, retaining the original timestamps of later pairs.
It does not discard the recording. A blocked-source-pad test forces repeated
drops without artificial CPU load and proves finalization and the notice reset
for the next recording. This does not explain the earlier missing MP4 reports.

Constant-quality x264 still applies a 2,048 kbit/s VBV ceiling by default.
Set vbv-buf-capacity=0 to disable that ceiling, matching the ordinary Theora
quality route's absence of a bitrate ceiling. Verify rc=crf, lookahead and the
absence of vbv_maxrate in the encoder options written inside the actual film.

Enable 3D does not make a mono camera stereo. After a frame identifies the
source as mono, photos and films keep camerabin's ordinary writers, filename
choice, effects and mirroring. The preview retains its mono frame for readiness
and never publishes it as a pair. Source-filter transitions discard the frame
that still carries the preceding filter; recording stop follows the recorder
actually started, independently of the Enable 3D setting.

The compositor fixture under tests/compositor-fixture enumerates the installed
policy list, checks native samples and child-only declarations, and compares
both rendered eyes with one output resize. A nested 2D compositor supplies an
actual output witness; an ordinary ScreenShot2 pair alone cannot do that.
The ordinary-control fixture fixes Qt's hash seed equally on both builds and
uses zero differing pixels. Fifty hide/show rounds invoke the shared action and
wait for the real child lifecycle; they load the repaired Qt GStreamer dependency.

## Building the five-package set

Prepare authenticated source downloads and build dependencies before the isolated
build. The four upstream-source recipes accept SOURCE_INPUT, a folder containing
their original descriptor and every archive it names, so the build can consume
those retained inputs without downloading again. The Camera page is a native
source recipe. The outer driver supplies build-provenance.sh's facts from a clean
commit and the signed runtime archive configuration; all ordinary Lean Code,
link and start checks remain in the recipes.

SPARKY_LC_SIBLINGS_FILE may supply the accepted round and earlier successors in
this set. Kamoso and Camera retain that universe while adding their checksum-pinned
layer and declaration inputs. A duplicate filename must have identical bytes.
Build every frei0r plugin, PipeWire's full source and the good-plugin source before
Kamoso, whose build dependencies require those repaired binaries. Retain each
source closure, binary build metadata, clean recipe record and install/path
comparisons before considering the set packaged.
