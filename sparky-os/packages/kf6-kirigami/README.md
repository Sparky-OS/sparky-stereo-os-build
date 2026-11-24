# kf6-kirigami, the edition's build

The recipe, its patch and its build are described in [plasma-integration's README](../plasma-integration/README.md): both are first edition builds of a Debian source, made by the same `build.sh` and `build-job-stereo3d1.sh` (queue row 77 milestone 2).

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
