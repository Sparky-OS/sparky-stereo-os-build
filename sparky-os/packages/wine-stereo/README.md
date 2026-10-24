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
substitute the amd64 CAPI packages for i386. The prepared source pins these versions in `debian/control` and `debian/control.in`.
The Vulkan registry has its own `debian/vulkan-registry/provenance.json`; `.buildinfo` records the complete build environment.

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

For the quad-buffer drawable correction, run `prepare-source.py SOURCE VERSION` on an extracted, unprojected edition source package with its existing quilt series applied.
It appends `patches/wine-quad-buffer-size.patch`, pins the retained dependencies, prepares the standard Lean Code hooks and records the changelog using the edition's packaging identity.
Generate one source package with `dpkg-buildpackage -S -us -uc -d`, then build every architecture from its `.dsc`.
The correction queries `GLX_STEREO` on the actual framebuffer configuration.
Genuine quad-buffer drawables retain one view's dimensions; prepacked OpenGL and Vulkan clients retain the existing packed-size path.

The same source preparation also appends `patches/wine-popup-metadata.patch`.
It describes Wine's override-redirect menus, tooltips and combo lists through EWMH window types.
A submenu's X11 transient owner names its parent menu, while Win32 command ownership stays intact.
The declaration is refreshed before mapping, after the menu's selected child is known.
A dropdown combo list also retains its combo owner when user32 reparents it to the desktop, allowing winex11 to name the application's root window in the transient hint.
The functional types follow [EWMH 1.5 section 5.6](https://specifications.freedesktop.org/wm/1.5/ar01s05.html).
The compositor must read override-redirect transient hints to apply popup depth through that owner chain.
