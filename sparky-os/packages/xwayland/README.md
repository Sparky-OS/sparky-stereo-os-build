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
The test's build dependencies (weston, three xcb development packages, `x11-xkb-utils` and `xkb-data`, without which no X server starts in a build container) also switch on upstream's own `sync` test.
To run it against an installed Xwayland: build `stereo-present-pair.c` with `-lxcb -lxcb-present -lxcb-composite` and call
`xwayland-stereo-pair.sh /usr/bin/Xwayland ./stereo-present-pair`.

## 24.1.15 +stereo3d1: the upstream release rebase (ORDER 562)

`rebase-source.py STAGED.dsc UPSTREAM.tar.xz DEBIAN.tar.xz OUT` consumes the accepted
`24.1.13-1+stereo3d5+lc1` source, X.Org's `xwayland-24.1.15.tar.xz`, and Debian's
`24.1.14-1.debian.tar.xz`. Their SHA-256 values are pinned in the recipe.
It retains all twelve patches, the source-consumer plan when present, the complete
accepted changelog and Debian's new changelog stanza. Debian's other packaging files
are unchanged between 24.1.13-1 and 24.1.14-1. The stereo counter restarts at one for
the new upstream release; the epoch remains two and the Debian revision remains one.

Patch 0005 now covers Michel Dänzer's `abb1e9914df8`: a declared version-four window's
backing pixmap can be one view wide before its first flip or already hold both views.
Other backing widths and both height mismatches remain rejected. The ordinary flip
checks remain upstream's. Patches 0009 and 0011 apply at shifted lines after upstream
changes, with no semantic change. No stereo patch is supplied by upstream or dropped.

Run the producer in a container with this checkout's `sparky-os` on `PYTHONPATH`.
Its date is the last clean recipe commit unless `SOURCE_DATE_EPOCH` is provided.
Build the resulting `.dsc` with `release/build-from-lc-dsc.sh`; read the suite's
`stereo pair without glamor OK` line. The mechanical rebase without the 0005 extension
fails that test. Keep the predecessor source closure alongside the inputs for reruns.
