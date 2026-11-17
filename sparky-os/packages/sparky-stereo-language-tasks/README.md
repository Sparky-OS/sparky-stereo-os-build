# Language task catalogues

The Git tree contains only the edition's translations.
Debian's tasksel catalogues are read from its unmodified 3.92 source archive at package build time.
`tasksel-source.json` pins the descriptor and archive by SHA256 and size; `catalogues.py` also checks the archive against the descriptor's component list.
Original translator credits remain in Debian's files.

Obtain `tasksel_3.92.dsc` and `tasksel_3.92.tar.xz` from the pinned Debian URL into a build-input directory, preferably with `apt-get source --download-only tasksel=3.92` against Debian's signed source index.
Set `TASKSEL_SOURCE_DIR` to that directory when running `build.sh`.
Missing or altered inputs stop the build; the builder never substitutes a later version or a local catalogue.

The generated source package retains both verified inputs in `upstream/`.
Its binary build verifies them again and compiles all ten catalogues using gettext from the retained sources, even when the resolved staging tree already contains compiled files.
A source rebuild needs no network.
The source-only inputs are not installed in the binary package.
