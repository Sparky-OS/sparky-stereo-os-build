# Native-eye Bino package

`build-native.sh` starts from the published `bino_2.8-1+stereo3d2+lc1.dsc` and its original tarball.
It adds `native-playback.patch`, builds the edition with `BINO_STEREO_DESKTOP=ON`, refreshes the retained Lean Code toolkit, and produces `2.8-1+stereo3d9+lc1`.
The original upstream output modes remain available to an OFF build.
The desktop entry uses the session's platform; it no longer forces Xwayland.
The coordinated build uses libstereo-declare 1.7.0 and Qt Multimedia
6.11.2-3+stereo3d11+lc1 for the default-off native-raster sink capability.
Configure checks the X11 child-placement API and the native-raster sink API.
Shared layer and AV 1.12.0-4+lc1 supply the existing approximate anaglyph
reconstruction API and coherent codec/container input precedence.
The edition build requires this additive API. Other source builds gate the new
input choices when building against an older shared layer. Native MV-HEVC
chroma sampling stays within each decoded eye; custom/unassembled declarations
cannot fall through to a shape guess.

Run in an isolated Debian testing package image with the edition's pin and matching development dependencies:

```
./build-native.sh PUBLISHED_SOURCE_DIRECTORY NEW_BUILD_DIRECTORY SPARKY_OS_TOOLKIT_DIRECTORY
```

The script creates one source package, then extracts that exact `.dsc` for the amd64 binary build.
Use the same source archive for any later architecture.
`BINO_SOURCE_ONLY=1` stops after creating that descriptor. This supports a split
build where compilation/staging runs in the pinned container and the existing
Lean Code archive gate runs in a native private namespace. It does not emit a
binary or waive either release gate.
For coordinated unpublished shared libraries, assemble with the public
`lean.source_tree.restore_payload`, provenance and `lean.release build-tree`
interfaces, then pass the exact sibling archive list with `check-link
--siblings-file`. Both the AV and layer runtime dependencies require -4; a
new transform symbol must never resolve against an older installed layer.
It sets the required packaging identity and limits the build to four threads.
Qt's moc input headers are preserved in the native source-consumer plan.
GLSL is outside the native C/C++ projection set and remains unchanged.
The binary dependency records the Qt Multimedia private ABI from `pkg-config`, as well as the published importing backend's minimum version.
The pipeline stamps provenance before payload projection and generates the LC marker and checksums itself.
Do not restamp the assembled package.

Release checks require a native runner with unprivileged Bubblewrap namespaces.
Dependencies are resolved from explicitly configured signed public archives,
not from the runner's installed libraries. Supply Debian Forky, deb-multimedia
testing and the edition's public archive, each with its public keyring.
Use private scratch and the exact published predecessor cohort:


```
export SPARKY_LC_ARCHIVE_CONFIG=PUBLIC_ARCHIVES_JSON
export SPARKY_LC_SCRATCH=PRIVATE_SCRATCH
PYTHONPATH=SPARKY_OS_TOOLKIT_DIRECTORY python3 -m lean.release check-debs NEW_BUILD_DIRECTORY/*.deb
QT_QPA_PLATFORM=offscreen PYTHONPATH=SPARKY_OS_TOOLKIT_DIRECTORY python3 -m lean.release check-link NEW_BUILD_DIRECTORY/*.deb --previous-dir PUBLISHED_BINARY_DIRECTORY --smoke bino-smoke.tsv
```

The smoke row is tab-separated: `bino`, `/usr/bin/bino`, `--help`.
Retain negative controls for a removed LC marker and a deliberately missing ELF NEEDED library.
Install the published Bino and upgrade to the candidate in a throwaway test container before capturing both eyes from the real executable.
The operator-run A10 comparison kit is a separate review artifact, not a
directory in this recipe. Use the approved kit supplied by the coordinator.

Translation correction: +stereo3d9 adds the seven anaglyph input labels in the required locales. The shared -4 cohort and all reviewed media code remain unchanged from +8. The complete existing Chinese catalog is retained in both explicit territories; only the seven new labels receive new Traditional wording.
