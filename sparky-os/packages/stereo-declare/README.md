# stereo-declare 1.9

Protocol version 4 carries native fractional view-source rectangles without resizing the producer buffer or committing the surface.
The existing membership-only X11 API and full side-by-side declaration remain unchanged.
Its release commit is `8fe2c33689939d14dd2357106a3a63a2dc228c03` in [Sparky-OS/libstereo-declare](https://github.com/Sparky-OS/libstereo-declare).

Run `build.sh source WORK CLONE IMAGE` once with `SPARKY_LC_TOOLKIT` pointing to the reviewed current toolkit.
The prepared image needs the Debian source tools and the toolkit's prerequisites.
The output has a plain source closure and the shared `1.9.0-1+lc1` closure under `WORK/source/lc`.
Then run `build.sh binary WORK SOURCE_DIR PREVIOUS_DIR IMAGE ARCH` separately with prepared native amd64 and i386 images.
Use the same LC descriptor for both builds; amd64 also builds the architecture-independent Python packages.
`SPARKY_LC_ARCHIVE_DIR` supplies `sources.json` and its public keyrings, using paths beneath `/archive`.
An empty previous directory is appropriate only for an architecture with no published predecessor.

The in-container scripts can also run in an existing guarded SDK using explicit paths.
They require an empty output directory, retain the original source and invoke the embedded projection, package and archive-backed link gates.
They do not install dependencies, select a host package universe, sign, publish or push.
A native SDK must provide the descriptor's Build-Depends plus bubblewrap, APT and the archive gate's tools; its container must permit the isolated namespace runner.
Keep the source, gate receipts and old packages, compare every shared file of the Multi-Arch pairs, and test installed membership behavior on both architectures before staging.
