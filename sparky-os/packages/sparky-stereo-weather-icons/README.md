
## Weather cohort build

Run `build-weather.sh WORK INPUT PREVIOUS ARCHIVE PUBLISHED` from a clean recipe commit.
Set `IMAGE` to the amd64 builder with the frozen build dependencies installed.
`WORK` is a new directory.
`INPUT` holds the pinned source descriptor and its files, the stereo-layer clone, or the generated `icons/` tree, according to the source being built.
For stereo-layer, `LAYER_REVISION` names the full source commit that is exported.
`PREVIOUS` holds the published predecessor binaries and `PUBLISHED` is the read-only edition tree.
`ARCHIVE` contains the signed snapshot configuration and package bytes for the link gate.
Set `PUBLISHED_SIBLINGS` to a list of baseline package files as seen below /round.
Set `SIBLINGS_DIR` to the local sibling packages grouped in directories named after their sources.
For the weather applet build, the isolated currency test needs iproute2 in the builder or its Debian archives in `IP_FIXTURE_DIR`.
The build records the committed recipe and leaves the descriptor, source files, binary packages, changes, buildinfo and build record in `WORK`.

## Native loop source

The 0.1.2 motion changes start from the 0.1.1 authored `icons/` export.
`tools/weak-native-loops.tsv` identifies the installed theme, icon and size of each revised loop.
Compile `tools/strengthen-weather-loop.cpp` against Qt 6 Gui, stereo-layer and libjxl.
Run `python3 tools/strengthen-weather-loops.py PREDECESSOR TARGET tools/weak-native-loops.tsv ENCODER PROOF`
with a copy of the predecessor export at TARGET. The driver replaces only the listed loop files.
The JPEG XL encoder keeps 16-bit RGBA, the ICC profile, frame delays and JXLStereo metadata.
The vector path keeps single-timeline SVGStereo and the original projected shapes.
