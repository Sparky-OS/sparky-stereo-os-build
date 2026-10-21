# Browser source packaging

`prepare-lean.py` integrates the accepted M5 browser export with Debian packaging
and the edition's qualified native-input pass. It retains the accepted release
profile, stereo source changes and eight locales. Binding templates and test
fixtures stay in their authored form for their additional consumers. The Cargo
adapter binds only verified C/C++ projections to vendor checksums; Rust remains
authored source.

The payload source layout records the generated application directory copied by
the install step. Its empty `removed-files` list is generated data; matching the
hash of an empty projected C header does not make it a copy of that header.
The layout keeps generated files intact while retaining the separate payload
qualification. The browser package does not install development headers.

The exported source package has no Git metadata. Its build environment therefore
pins `MOZ_SOURCE_REPO` and `MOZ_SOURCE_CHANGESET` to the edition fork and accepted
commit; Mozilla's own generator uses these for the source header and package
sourcestamp. An empty source header must not be bypassed in the packager.

The accepted browser commit also contains 192 pre-existing vendor checksum
discrepancies and three entries for absent files, across 13 manifests.
`cargo-baseline.json` records the exact accepted Git blobs and SHA256 values.
`cargo-baseline.py` reconciles only those entries in the disposable build, before
the separate projection adapter runs. It changes no source content or crate
package identity, rejects unrelated edits and restores the original manifests
on clean. These baseline repairs are not Lean Code savings.

The prepared source carries a complete compiler file/mode/symlink manifest.
With Python 3, tar, zstd and rustup installed, reconstruct its bundle in a fresh
directory and build from the source root:

```sh
python3 debian/fetch-toolchains.py /path/to/new-bundle \
    debian/toolchain-manifest.json --cache /path/to/download-cache
SPARKY_BROWSER_TOOLCHAIN_ROOT=/path/to/new-bundle \
    dpkg-buildpackage -us -uc -b -j4
```

Mozilla archive URLs identify fixed Taskcluster tasks, with SHA256 checks before
extraction. The WASI aliases reproduce the accepted upstream fetch script. Rust
1.98.1 uses the minimal profile in an isolated Rust installation. Configuration
checks all compiler entries again; a newer compiler is not an interchangeable
input. On 20 October 2026, reconstruction matched all 17,947 retained entries.

Source preparation and compiler reconstruction do not establish application
correctness. The complete build, package payload/HR checks and the installed
browser's headless stereo bench remain separate release requirements.

The `6.7.5-0+stereo3d5+lc1` candidate completed those checks on 21 October 2026:
both archives passed payload/HR verification, 57 installed regular files matched
the application archive, and all 77 M5 browser cases passed in private headless
Stereo KWin. Ten representative left/right capture pairs were visually reviewed,
covering video, opacity, mono controls, inline/immersive WebXR and Three.js/Babylon
camera rendering. The no-stereo-output fixture correctly declined an immersive
session. This is not physical-display, HDR or latency qualification.

Retained compiler dependency records identify 22,547 unique matching source
inputs: 336,325,166 authored bytes became 307,626,450 bytes, a reduction of
28,698,716 bytes. These are compiler inputs, not executable-size savings,
physical disk-read totals or a measured reduction in compilation time.
