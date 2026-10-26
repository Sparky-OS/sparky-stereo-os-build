# Native-eye Bino package

`build-native.sh` starts from the published `bino_2.8-1+stereo3d2+lc1.dsc` and its original tarball.
It adds `native-playback.patch`, builds the edition with `BINO_STEREO_DESKTOP=ON`, refreshes the retained Lean Code toolkit, and produces `2.8-1+stereo3d7+lc1`.
The original upstream output modes remain available to an OFF build.
The desktop entry uses the session's platform; it no longer forces Xwayland.
The coordinated build uses libstereo-declare 1.7.0 and Qt Multimedia
6.11.2-3+stereo3d11+lc1 for the default-off native-raster sink capability.
Configure checks the X11 child-placement API and the native-raster sink API.
Shared libstereo-av 1.12.0-3+lc1 supplies the corrected in-process inspector;
its API satisfies the retained Bino dependency minimum of 1.12.0-2+lc1.

Run in an isolated Debian testing package image with the edition's pin and matching development dependencies:

```
./build-native.sh PUBLISHED_SOURCE_DIRECTORY NEW_BUILD_DIRECTORY SPARKY_OS_TOOLKIT_DIRECTORY
```

The script creates one source package, then extracts that exact `.dsc` for the amd64 binary build.
Use the same source archive for any later architecture.
It sets the required packaging identity and limits the build to four threads.
Qt's moc input headers are preserved in the native source-consumer plan.
GLSL is outside the native C/C++ projection set and remains unchanged.
The binary dependency records the Qt Multimedia private ABI from `pkg-config`, as well as the published importing backend's minimum version.
The pipeline stamps provenance before payload projection and generates the LC marker and checksums itself.
Do not restamp the assembled package.

Release checks run in a container with the published runtime libraries installed:

```
PYTHONPATH=SPARKY_OS_TOOLKIT_DIRECTORY python3 -m lean.release check-debs NEW_BUILD_DIRECTORY/*.deb
QT_QPA_PLATFORM=offscreen PYTHONPATH=SPARKY_OS_TOOLKIT_DIRECTORY python3 -m lean.release check-link NEW_BUILD_DIRECTORY/*.deb --previous-dir PUBLISHED_BINARY_DIRECTORY --smoke bino-smoke.tsv
```

The smoke row is tab-separated: `bino`, `/usr/bin/bino`, `--help`.
Retain negative controls for a removed LC marker and a deliberately missing ELF NEEDED library.
Install the published Bino and upgrade to the candidate in a throwaway test container before capturing both eyes from the real executable.
The operator-run A10 comparison kit is a separate review artifact, not a
directory in this recipe. Use the approved kit supplied by the coordinator.
