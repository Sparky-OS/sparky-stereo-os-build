# QEMU native Lean Code integration

`prepare-lean.py` adapts the edition's already patched QEMU Debian source to the
shared Lean Code pipeline. It preserves QEMU's explicit make graph, firmware
builds, tests and control-file generator. It does not replace the stereo patches.

For a disposable export of that source:

```sh
python3 prepare-lean.py /path/to/source '1:11.1.2+ds-1+stereo3d4+lc1'
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
checker dependencies and `libstereo-declare-dev`; changing only the generated
file can produce a source package that fails its next clean rebuild.

The 20 October 2026 candidate completed 129 tests with zero failures and four
skips. Its 39 binary, debug and required HR archives passed the lc1 release
checker. Compilation and package checks do not establish paired-display or
physical-output behaviour.

When resuming failed package assembly, regenerate ordinary **and** debug-symbol
staging from the qualified compiled outputs. Debhelper can leave previously
projected trees in `debian/.debhelper/*/dbgsym-root`; removing just their marker
would incorrectly project an already projected payload. Retain the failed
attempt's logs and metadata before discarding that temporary staging.
