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
