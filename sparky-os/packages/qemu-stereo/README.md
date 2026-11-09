# QEMU native Lean Code integration

`prepare-lean.py` adapts the edition's already patched QEMU Debian source to the
shared Lean Code pipeline. It preserves QEMU's explicit make graph, firmware
builds, tests and control-file generator. It does not replace the stereo patches.

For a disposable export of that source:

```sh
python3 prepare-lean.py /path/to/source '1:11.1.2+ds-3+stereo3d5+lc1'
dpkg-source -b /path/to/source
# In the isolated Debian build environment, install this source's Build-Depends:
cd /path/to/source
dpkg-buildpackage -us -uc -b -j4
```

Keep the resulting source descriptor and its archives beside the binaries.
The source bundles the projection engine and preservation plan. Firmware under
`roms/` and target compiler/assembly fixtures under `tests/tcg/` remain authored
inputs until their respective consumers have independent qualification.

QEMU regenerates `debian/control` from `debian/control-in`. Both must retain the
checker dependencies, `libstereo-declare-dev`, `libstereo-dibr-dev` (the GTK display
draws a guest's picture with its depth through libstereo-dibr; its runtime
`Depends: libstereo-dibr1 (>= 1.17.1)` comes from the library's shlibs file) and the
edition's minimum SPICE version; changing only the generated file can produce a source package that
fails its next clean rebuild. The shared preparation function accepts simple
extra package names; versioned, architecture-qualified relations are added
through the control-stanza helper to both files.

`rebase-debian.py SOURCE PRIOR_EDITION_DEBIAN_ARCHIVE` carries the seven unchanged
stereo3d4 patches onto authenticated Debian `1:11.1.2+ds-3` source. The second
argument is the retained `qemu_11.1.2+ds-1+stereo3d4.debian.tar.xz`, before Lean
Code integration. The recipe retains Debian's virtio-gpu mapping cleanup,
migration and RISC-V fixes and records each stereo patch's hash. Apply this
rebase before `prepare-lean.py`. A successful rebase is not build qualification.

The `1:11.1.2+ds-3+stereo3d5+lc1` candidate completed 129 tests with zero failures
and four skips on 20 October 2026. Its 39 binary, debug and required HR archives
passed the lc1 release checker. An isolated installation matched all 359 regular
files, permissions and symlink targets in the four VM-test packages; KVM/QMP
checks confirmed the stereo device property and paused VM state. These checks
do not establish paired-display or physical-output behaviour.

When resuming failed package assembly, regenerate ordinary **and** debug-symbol
staging from the qualified compiled outputs. Debhelper can leave previously
projected trees in `debian/.debhelper/*/dbgsym-root`; removing just their marker
would incorrectly project an already projected payload. Retain the failed
attempt's logs and metadata before discarding that temporary staging.

## CPU refresh series after the published stereo3d6 source

The signed repository already publishes `1:11.1.2+ds-3+stereo3d6+lc1` with
37 patches, including the native-sample `stereo3d/0008` patch. Do not rebuild
that version in place or rebase it from the older seven-patch stereo3d4 input.
For a disposable extraction of this exact source, run:

```sh
python3 add-refresh-patches.py /path/to/source
cd /path/to/source
dpkg-source --before-build .
```

This appends the three reviewed CPU refresh patches and a history-preserving
`1:11.1.2+ds-3+stereo3d7+lc1` changelog entry. The allocation-size correction
is required with the full-frame refresh. No protocol IDs or input admission
are changed. The old 37 patch bytes and order remain intact.

This step is source integration, not a package qualification or an lc1
attestation. The source still contains its previously bundled Lean Code
engine. Before a build, refresh that disposable integration from the current
shared toolkit through `prepare-lean.py`, retaining its QEMU make graph,
source-preservation plan and provenance-before-payload order. The preparer
rejects an already integrated tree; do not run it blindly over the published
rules or strip their hooks. Retain the original rules and changelog as the
comparison when preparing that refresh.

Run the full Debian package build, the Lean Code release/link gate and the
installed-package runtime controls before treating the resulting stage as
ready. The source integration alone must not be presented as those passes.
