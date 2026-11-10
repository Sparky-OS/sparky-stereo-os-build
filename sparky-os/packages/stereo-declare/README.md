# stereo-declare 1.10

Version 1.10 hands a program the person's depth limits: `kde_stereo_depth_v1.depth_limits` (protocol 5) on Wayland and `_KDE_NET_WM_STEREO_DEPTH_LIMITS` (support version 10) on a declared X11 window, in C and Python.
A compositor that does not offer them is told apart (`-ENOTSUP`), never answered with zeros; the library binds at most the protocol version it knows.
Only symbols are added to 1.9, which was never published; the protocol 4 native view sources and the membership-only X11 API stay as they were.
Its release commit is `675798f627e9010626acc9a32ed88d2f7e0349ba` in [Sparky-OS/libstereo-declare](https://github.com/Sparky-OS/libstereo-declare).

Run `build.sh source WORK CLONE IMAGE` once with `SPARKY_LC_TOOLKIT` pointing to the reviewed current toolkit.
The prepared image needs the Debian source tools and the toolkit's prerequisites.
The output has a plain source closure and the shared `1.10.0-1+lc1` closure under `WORK/source/lc`.
Then run `build.sh binary WORK SOURCE_DIR PREVIOUS_DIR IMAGE ARCH` separately with prepared native amd64 and i386 images.
Use the same LC descriptor for both builds; amd64 also builds the architecture-independent Python packages.
`SPARKY_LC_ARCHIVE_DIR` supplies `sources.json` and its public keyrings, using paths beneath `/archive`.
An empty previous directory is appropriate only for an architecture with no published predecessor.

The in-container scripts can also run in an existing guarded SDK using explicit paths.
They require an empty output directory, retain the original source and invoke the embedded projection, package and archive-backed link gates.
They do not install dependencies, select a host package universe, sign, publish or push.
A native SDK must provide the descriptor's Build-Depends plus bubblewrap, APT and the archive gate's tools; its container must permit the isolated namespace runner.
Keep the source, gate receipts and old packages, compare every shared file of the Multi-Arch pairs, and test installed membership behavior on both architectures before staging.
