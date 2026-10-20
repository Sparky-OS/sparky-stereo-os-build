# Retained inputs for Wine's native Lean Code build

These helpers supplement the shared `lean.debian_prepare` adapter for the
edition's Wine 10 source. Keep Wine's `debian/scripts/check-control` enabled.

Prepare a disposable source export in this order:

1. Retain and pin the build dependencies described below in `debian/control`.
2. Run `lean.debian_prepare` with the new package version and
   `--preserve-source '*.h' 'WIDL and WRC also preprocess shared headers and reject filename-less line directives; preserve their exact inputs'`.
3. Run `sync-control.py SOURCE` to carry those declarations into
   `debian/control.in` and run Wine's own consistency check.
4. Run `pin-vulkan-registry.py SOURCE`. It verifies the fixed upstream registry
   hashes, retains the registry and license in `debian/vulkan-registry`, and
   points Wine's existing Vulkan generator at those inputs.
5. Create the source package, then build it in an isolated Debian environment.
   Build the i386 counterpart from that **same** source descriptor and compare
   all shared files of `Multi-Arch: same` packages before publishing.

WIDL and WRC consume the same headers as GCC but do not accept its complete
preprocessing grammar. A successful C check does not qualify those consumers;
the source headers and installed `/usr/include/wine/` headers stay authored.
The package still goes through lc1 coverage and payload verification.

Wine's existing `generate/vulkan-1.4.318.patch` expects Vulkan-Headers v1.4.318.
Substituting the latest system registry fails the generator. The helper pins
commit `b39ab380a44b6c8df462c34e976ea9ce2d2c336b` and rejects different bytes.
`--cached DIR` accepts the same verified `vk.xml`, `video.xml` and `LICENSE.md`
without downloading them again. Generated files absent from Debian's repacked
source are not falsely counted as projected compiler inputs.

The migration used these exact build inputs from Debian's authenticated trixie
archive, because they had left testing. Retain the signed index, package hashes
and architecture-specific packages; do not add an unauthenticated mirror or
substitute the amd64 CAPI packages for i386. The prepared source records its
inputs in `debian/verified-build-inputs.json`; `.buildinfo` records the build
environment.

| Package | Version |
| --- | --- |
| `unicode-data` | `15.1.0-1` |
| `unicode-idna` | `16.0.0-1` |
| `unicode-cldr-core` | `46-0.1` |
| `libldap2-dev` | `2.6.10+dfsg-1` |
| `libcapi20-dev`, `libcapi20-3t64` | `1:3.27-3.2+b1` |

The amd64 candidate `10.0~repack-12+stereo3d3+lc1` built successfully on
20 October 2026 and all 14 archives passed lc1 payload/HR verification.
Its configure warnings about unavailable OSMesa bitmap and CAPI/ISDN support
also occur in both architectures' previous accepted builds. Those features
are not newly enabled by this migration. At this checkpoint the i386 build,
shared-file comparison and installed runtime checks remain separate gates.
