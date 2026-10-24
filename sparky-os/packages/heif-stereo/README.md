# HEIF stereo entity groups

Apply these patches to the recorded edition source packages with prepare-source.py, then build from one resulting source descriptor per project through its native Lean Code adapter.

| Source baseline | Candidate |
| --- | --- |
| libheif 1.23.6-2 | 1.23.6-2+stereo3d1+lc1 |
| kf6-kimageformats 6.30.0-1+stereo3d4+lc1 | 6.30.0-1+stereo3d5+lc1 |
| kf6-kfilemetadata 6.30.0-1+stereo3d2+lc1 | 6.30.0-1+stereo3d3+lc1 |
| stereo-layer 1.10.0-1+lc1 | 1.11.0-1+lc1 |
| gwenview 4:26.04.0-1+stereo3d5+lc1 | 4:26.04.0-1+stereo3d6+lc1 |
| kolourpaint 4:26.08.1-1+stereo3d1+lc1 | 4:26.08.1-1+stereo3d2+lc1 |

Build libheif first and install its development and runtime packages in the disposable build SDK before the reader builds.
The readers require that libheif revision because the preceding library defines stem but does not parse it.
KImageFormats breaks older stereo-layer versions so an installed consumer cannot mistake a monoscopic fallback for the left view during a partial upgrade.
The companion stereo-layer 1.11.0 change reads explicit view indices while keeping the primary as its ordinary image.

The native file marks are ISO/IEC 23008-12:2025 6.8.5 ster and Amendment 1 6.8.11 stem, registered at https://mp4ra.org/registered-types/entity-groups.
The libheif entity-group API lists left, right and the optional monoscopic fallback in that order.
The new Qt reader text Stereo3DViewIndices maps those views to reader image numbers when neither view is primary.
It introduces no new file mark and writes no source picture.
A standard Qt read still returns the primary image.

Build and install stereo-layer 1.11.0 development and runtime packages before building the two application adapters.
Its source lives in the companion stereo-layer repository and uses the edition's existing native package adapter.
Gwenview passes its current document bytes to Picture::fromReader, preserving unsaved editing state.
KolourPaint selects the actual view pair through the same entry point before preparing its editable packed image.
Both adapters require libstereo-layer-dev at least 1.11.0-1+lc1.
The existing digiKam and Showfoto Picture::load routes use the new shared-layer selection without a separate application patch.
Keep the generated CC0 HEIF fixtures and their binary declarations in the source package.
Run each native adapter's check-debs and check-link gates against the installed build dependencies, and repeat the checks with a removed payload and a deliberately unresolved ELF dependency.
The ordinary primary image, explicit eye correction and malformed-group fallbacks are part of the reader contract.
