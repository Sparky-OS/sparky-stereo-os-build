# Xwayland stereo child presentation

`prepare-source.sh INPUTS OUTPUT` extends the published
`2:24.1.13-1+stereo3d3+lc1` source package into
`2:24.1.13-1+stereo3d4+lc1`. INPUTS contains its descriptor and both tarballs;
OUTPUT must be empty. The descriptor hash is pinned and `dpkg-source` checks
its archive closure. The eight existing patches and embedded Lean Code
pipeline are retained. Patch 0009 preserves packed child-eye pixels through
first-copy presentation, compositor redirection and backing-pixmap recycling.
Mesa remains the stereo declaration writer.

Build in an isolated amd64 dependency environment with
`build-in-container.sh OUTPUT PREVIOUS TOOLKIT`. PREVIOUS contains the exact
published predecessor package, and TOOLKIT is the current edition release
toolkit with `check-debs` and `check-link`. The source package is prepared
once; the binary build keeps the original Debian feature options and test
sequence. Provenance runs before payload sealing. The inherited source
toolkit predates the link gate, so the recipe explicitly runs the current
gate after assembly. A failed build or gate is not an installable candidate.

Use the Mesa `tests/glx-window-lifetime.c` capture fixture with installed Mesa
and Xwayland packages. Keep Mesa identical when comparing Xwayland versions.
Check raw eyes, compositor captures, owner backgrounds, declaration timing
and lifecycle state separately. These bounded controls do not establish
partial-update, clipping, overlapping-child, input, DPI or other-GPU coverage.

## +stereo3d5: a stereo window's pair without glamor (ORDER 560)

`next-source.sh PUBLISHED.dsc OUT` makes `2:24.1.13-1+stereo3d5+lc1` from the published `+stereo3d4+lc1` source
(`repo/lc-successor.py --in-place --overlay`): patches 0010 to 0012 join the series, the test's build dependencies join
`debian/control`, and the entry of `changelog-stereo3d5.txt` goes on top of the published changelog.
Build the binary package from the new `.dsc` with `release/build-from-lc-dsc.sh`.

Without glamor (no 3D acceleration, or `XWAYLAND_NO_GLAMOR=1`) Xwayland has no DRI3, so a GL program draws on the software
renderer and Mesa presents a pixmap twice the window's width for a stereo window (declaration version 4).
0010 gives that pixmap shared memory and a `wl_buffer`, so Present flips it to the window's surface instead of copying it
into the one eye wide window; 0011 damages both eyes of the flipped buffer.
0012 is the test, in the source's own `xwayland` suite (`test/scripts/xwayland-stereo-pair.sh`, `test/stereo-present-pair.c`):
Xwayland without glamor under a headless weston, a declared toplevel and a declared child window, an undeclared window as
the control.
The build runs it; read `stereo pair without glamor OK` in the build log, since a `SKIP` there is not a pass.
To run it against an installed Xwayland: build `stereo-present-pair.c` with `-lxcb -lxcb-present -lxcb-composite` and call
`xwayland-stereo-pair.sh /usr/bin/Xwayland ./stereo-present-pair`.
