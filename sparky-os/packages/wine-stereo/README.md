# Retained inputs for Wine's native Lean Code build

These helpers supplement the shared `lean.debian_prepare` adapter for the edition's Wine 10 source.
Keep Wine's `debian/scripts/check-control` enabled.

## Audit WoW64 before changing the build

The published `10.0~repack-12+stereo3d5+lc1` source already configures amd64 with `--enable-archs=x86_64,i386` in `debian/rules`.
Its `libwine:amd64` contains both `x86_64-windows` and `i386-windows` PE payloads, alongside `x86_64-unix` modules.
Enabling that configure option again is not a Wine transition.
Start from the actual signed source and package members, then prove PE32 and PE32+ execution using the installed amd64 packages in a root without i386 Unix libraries.
Record the executable and loaded ELF classes as well as program output and exit status.

The edition's `debian/scripts/wine.in` selects `/usr/bin/wine32` for an explicit `WINEARCH=win32` or a prefix marked `#arch=win32`, when that loader is installed; otherwise it prefers `/usr/bin/wine64`.
The latter wrapper executes `/usr/lib/x86_64-linux-gnu/wine/wine`.
The `wine32` route and `libwine:i386` preserve pure 32-bit prefixes; PE32 execution in a 64-bit prefix does not prove those prefixes can be migrated.
Keep the existing package set and rollback inputs until the prefix and dependency transition is separately qualified.

Separate PE payload architecture from Unix runtime architecture.
In particular, the edition's `dxvk-wine32:i386` package contains Windows DLLs, while the `libdxvk-*` packages contain native Unix libraries.
A PE32 DLL remains necessary for a 32-bit Windows application even when Wine loads only ELF64 Unix libraries.
Native Linux i386 applications remain separate consumers of i386 libraries.
Check installed dependency relationships and simulate removals with the actual machine inventory; do not infer an image-library removal set from Wine alone.
The current `wine64` control stanza suggests the matching `wine32` package.
Account for that relationship when the installation policy enables Suggests; removing an installed package alone does not change future package selection.

Wine 10's implementation still describes new WoW64 as experimental.
[Wine 11.0's release notes](https://gitlab.winehq.org/wine/wine/-/raw/wine-11.0/ANNOUNCE.md) call it fully supported, but continue to exclude pure 32-bit prefixes.
That release also changes the X11 OpenGL default to EGL, retaining GLX as an option and fallback.
A rebase therefore needs review of the stereo GLX drawable and declaration patches, the EGL path, Vulkan integration and popup ownership, in addition to loader and prefix checks.
Preserve `/usr/bin/wine64` as a packaging interface where callers require it; upstream's removal of a loader named `wine64` is not permission to remove the edition's wrapper.

## Prepare retained build inputs

### Repair TMPDIR ownership on an existing prepared source

Debian's `fixes/temporary-directory.patch` adds the shared `include/wine/server_tmpdir.h` helper to the Unix client and wineserver.
When `/run/user/UID` is absent, the helper selects `TMPDIR` and frees its borrowed environment pointer, so a fresh Wine prefix can abort before startup.
The normal unset-TMPDIR case does not exercise that invalid free.
`patches/wine-tmpdir-ownership.patch` keeps both the environment value and constant fallback borrowed; it preserves private-directory and marker modes.

For an already prepared source, use `prepare-tmpdir-fix.py SOURCE NEW_VERSION`.
It appends only this correction and a new changelog entry, retains the existing LC integration and stereo patches, and runs Wine's control consistency guard.
It refuses to replace an existing correction.
Create one new descriptor and build its architecture peers from that descriptor.
Do not rerun the original stereo source preparer or rebuild the old version.

Inside an isolated native container, run `python3 tests/test-tmpdir.py PUBLISHED_SOURCE NEW_SCRATCH_DIRECTORY`.
The test uses the actual helper, tests creation and reopening, checks directory mode 0700 and marker mode 0400, and compares an unset environment with three explicit temporary paths, including spaces.
The old code must fail the explicit-path cases under AddressSanitizer; the corrected code must pass all cases.
This source regression complements installed-package fresh-prefix tests; it does not qualify a rebuilt loader or replace graphics and prefix rollback checks.

Prepare a disposable source export in this order:

1.
Retain and pin the build dependencies described below in `debian/control`.
2.
Run `lean.debian_prepare` with the new package version and `--preserve-source '*.h' 'WIDL and WRC also preprocess shared headers and reject filename-less line directives; preserve their exact inputs'`.
3.
Run `sync-control.py SOURCE` to carry those declarations into `debian/control.in` and run Wine's own consistency check.
4.
Run `pin-vulkan-registry.py SOURCE`.
It verifies the fixed upstream registry hashes, retains the registry and license in `debian/vulkan-registry`, and points Wine's existing Vulkan generator at those inputs.
5.
Create the source package, then build it in an isolated Debian environment.
Build the i386 counterpart from that **same** source descriptor and compare all shared files of `Multi-Arch: same` packages before publishing.

WIDL and WRC consume the same headers as GCC but do not accept its complete preprocessing grammar.
A successful C check does not qualify those consumers; the source headers and installed `/usr/include/wine/` headers stay authored.
The package still goes through lc1 coverage and payload verification.

Wine's existing `generate/vulkan-1.4.318.patch` expects Vulkan-Headers v1.4.318.
Substituting the latest system registry fails the generator.
The helper pins commit `b39ab380a44b6c8df462c34e976ea9ce2d2c336b` and rejects different bytes.
`--cached DIR` accepts the same verified `vk.xml`, `video.xml` and `LICENSE.md` without downloading them again.
Generated files absent from Debian's repacked source are not falsely counted as projected compiler inputs.

The migration used these exact build inputs from Debian's authenticated trixie archive, because they had left testing.
Retain the signed index, package hashes and architecture-specific packages; do not add an unauthenticated mirror or substitute the amd64 CAPI packages for i386.
The prepared source pins these versions in `debian/control` and `debian/control.in`.
The Vulkan registry has its own `debian/vulkan-registry/provenance.json`; `.buildinfo` records the complete build environment.

| Package | Version |
| --- | --- |
| `unicode-data` | `15.1.0-1` |
| `unicode-idna` | `16.0.0-1` |
| `unicode-cldr-core` | `46-0.1` |
| `libldap2-dev` | `2.6.10+dfsg-1` |
| `libcapi20-dev`, `libcapi20-3t64` | `1:3.27-3.2+b1` |

The amd64 candidate `10.0~repack-12+stereo3d3+lc1` built successfully on 20 October 2026 and all 14 archives passed lc1 payload/HR verification.
Its configure warnings about unavailable OSMesa bitmap and CAPI/ISDN support also occur in both architectures' previous accepted builds.
Those features are not newly enabled by this migration.
At this checkpoint the i386 build, shared-file comparison and installed runtime checks remain separate gates.

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

`tests/popup-ui.c` exercises those hints with actual Win32 controls.
Build it with either MinGW target, linking `comctl32` and `gdi32`, and run it with the installed Wine in a disposable headless prefix.
It accepts newline-separated commands on standard input: `combo`, `menubar`, `right`, `select`, `close`, `context`, `tooltip`, `dialog`, `resize` and `exit`.
Open `menubar`, then send `right` to open its submenu and `select` to deliver command 101 to the owner.

Check the X11 properties while each control is visible.
The menu bar's popup is `DROPDOWN_MENU`; its child and a context menu are `POPUP_MENU`; the combo, tooltip and owned dialog use their corresponding EWMH types.
The submenu's `WM_TRANSIENT_FOR` names the parent menu, while its window group and command recipient remain the main window.
The other popups name the application's root window.
None of this ordinary UI declares stereo.

For compositor coverage, use a separate stereo surface to activate the output, disable desktop plane depth, and compare the ordinary UI in both captured eyes, against the stereo-off capture and against the published Wine.
Check both PE32 and PE32+, the 40-pixel width/height reduction, and window destruction.
Reject deliberately flattened submenu ownership, wrong popup types, a spurious UI stereo mark and a changed pixel in one eye.
Property snapshots establish the observed state; they do not count every property change or qualify a game's stereo renderer.
The fixture periodically repaints for capture and clips child controls out of its background paint so the test itself cannot erase the combo.

`tests/wgl-child.c` places an address-coded WGL viewport inside an ordinary Win32 owner, with a real menu above it.
Build both MinGW targets with `-O2 -Wall -Wextra -Werror -lopengl32 -lgdi32`.
Pass `stereo` or `mono`, then send `open`, `menu`, `close-menu`, `resize`, `hide`, `show`, `destroy`, `open`, `destroy`, and `exit` on standard input.
The viewport starts at 240x140 and resizes to 200x120.
A missing requested stereo format exits 77.

Each eye encodes `(x, y, eye * 128)` in RGB, with y increasing from the bottom.
Check every viewport pixel, the unchanged surrounding UI, visibility and exit restoration.
The parent must remain undeclared; a stereo viewport needs its own child surface under the real owner, listed in that owner's stereo children property.
Record X11 requests before launching the fixture to count exactly one declaration per created surface, including the destroyed first surface.
Final property snapshots alone cannot establish that count.

The offscreen Wine child path can instead create the drawable below a dummy window, manually redirect it and copy its pixels into the owner with GDI.
A correct stereo format or one declaration does not prove that this copy preserves both eyes.
Keep this failure and ordinary mono resize/show failures visible when comparing a driver correction; unchanged failure pixels establish non-regression only.
Direct-child success does not qualify nested clipping, sibling overlap, scaled DPI, native Wayland, or another graphics driver.

For redraw diagnosis, pass an existing Windows-accessible output directory as argument two.
The fixture logs client size, viewport, frame and paint counters, swap start/completion times, and exact address errors in the GL back buffer before swapping and front buffer afterwards.
`probe` saves bottom-up RGB GL readbacks and a top-down BGRA owner-DC readback.
The latter is the GDI backing surface, which can differ from the X window containing Wine's delivered GL copy; compare the actual X window and compositor pixels separately.

An optional third argument containing `step` disables the timer.
`redraw` presents one frame; `paint` explicitly invalidates and paints the child.
`step-paint-redraw` also draws after the child's `EndPaint`, and `step-rebind` rebinds its WGL context before drawing as a diagnostic control.
A `probe` acknowledgement on the UI thread supplies a completion barrier for preceding commands.
Capturing after a fixed delay can precede `SwapBuffers` completion.
Keep the first returned frame after resize separate from a later good frame.
These diagnostic modes report pixel errors without turning process exit zero into a rendering pass; an external oracle must inspect the readbacks and logs.

### Native first-resize control

`tests/native-glx-resize.c` runs the address-coded mono resize sequence directly through GLX, without Wine.
Compile with `gcc -O2 -Wall -Wextra -Werror native-glx-resize.c -lGL -lX11 -lXcomposite -o native-glx-resize` and run in an empty writable directory in an isolated X11 session.
It uses a manually redirected child below a 1x1 parent to match the offscreen route.
It records initial, first-resize, second-resize and show frames separately.
Each phase retains raw GL_BACK/GL_FRONT RGB bytes in bottom-up row order and XGetImage bytes with the logged stride, masks and byte order, plus requested and completed OML swap counters and monotonic timestamps.
Existing output files cause failure instead of being overwritten.

Exit zero means the diagnostic sequence completed.
Pixel error counts must be checked independently against `(x, y, 0)` in GL coordinates; an exact second frame never qualifies a failing first frame.
Native and Wine pixels are separate observations.
External protocol traces can correlate submitted pixmaps and Present events, but do not expose uninstrumented Mesa internals.
This fixture is not a rendering correction or a package acceptance gate.

### Packed Direct3D 9 pixel control

`tests/d3d9-pair.c` writes address-coded pixels into a D3D9 back buffer, presents, then resets from 320x200 to 256x160.
Its `stereo` argument puts the two eyes in halves of that same buffer; `mono` uses the whole buffer for one image.
It does not declare a native stereo window.
That is the runtime producer's job.

Run `tests/check-d3d9-pair.py IMAGE --phase 0 --mode stereo` on the raw 320x200 X11 image, or `--phase 1` on the resized 256x160 image.
The checker requires Python 3, NumPy and Pillow, checks every channel without a tolerance, and exits nonzero on any wrong pixel.
Use `--mode mono` for the ordinary control.
Do not apply the WGL quad-buffer oracle: this fixture's eye is half the buffer width, whereas the WGL fixture draws each eye at the full logical width.

This raw-image check does not prove compositor declaration, eye separation or surface lifetime.
Record actual declaration requests and separate ScreenShot2 captures for those gates, including the published runtime as a negative control.

The matching `tests/d3d11-pair.c` fixture uses a D3D11 BGRA8 backbuffer and `ResizeBuffers`; its raw image uses the same `check-d3d9-pair.py` oracle.
Both D3D fixtures signal capture after their eleventh Present, not their first.
They never write native stereo declaration properties.

### Vulkan child lifecycle candidate

`patches/wine-vulkan-child-lifecycle.patch` is an unapplied source candidate against Wine `10.0~repack-12+stereo3d6+lc1` with its existing patches.
It is not yet added to `prepare-source.py` or a source package.
The paired producer is DXVK's `wine-wsi-v1-request.patch`.

The version-1 request is a temporary, thread-named Win32 property scoped to native surface creation.
Wine acknowledges it only with the version-9 X11 consumer, Shape support and the membership API from libstereo-declare 1.8.
A live native X window owns its content declaration.
Reparenting and ancestor recreation maintain owner membership without declaring that content again.
Ordinary owners remain undeclared, and packed pixels bypass the mono GDI copy.
A referenced surface snapshot separates geometry calculation from the registry lock.
An actual native reparent completes before another X connection destroys the old owner.

The first Present after an owner map waits for actual X viewability, with a one-second bound and without the Wine window or registry lock held.
A timeout still submits the host Present so its wait semaphores are consumed, then reports an out-of-date surface.
This adds an optional callback to the internal Vulkan driver interface and increments its version to 37; all consumers of that internal header must be rebuilt together before packaging.

The source has targeted-module evidence for first repaint, ancestor recreation, two overlapping children, clipping, move, detach and destruction.
DPI-aware 192-DPI input and both captured eyes are measured separately from DPI-unaware behavior.
The surface-only concurrent lifetime and acknowledgement error controls are described below.
Swapchain and Present concurrency, native i386 and the new package cohort remain qualification gates.
The private module tests do not qualify Wine on NVIDIA, Wayland, arbitrary games or a production transition.

The two-child mono capture control must service its UI event loop while the observer reads the first frame.
Blocking that thread can delay the ordinary GDI CopyArea even after the native Present has completed.
With a responsive capture handshake, the original and candidate modules match across all nine phases, and the restacked native images and ordinary owner pixels match the fixture's pattern without another Present.
The retained blocking-capture negatives remain useful controls; this parity result does not assert that every original-Wine frame is correct.
The DPI-unaware 192-DPI input failure also occurs on the unchanged runtime and remains a separate Wine follow-up.
Candidate input mapping must still match original mono Wine in each DPI mode before packaging.

### Two-child capture timing control

`tests/d3d9-multiple-capture.c` exercises restacking, ancestor visibility, move, child destruction and input with two overlapping D3D9 children and an ordinary panel.
Compile it with `x86_64-w64-mingw32-gcc -O2 -Wall tests/d3d9-multiple-capture.c -o multiple64.exe -ld3d9 -lgdi32` and run it only inside the isolated capture rig with a private Wine prefix.
Set `WINE254_CAPTURE_PUMP=1` for the responsive handshake: a reader thread waits for the observer's stdin reply while the window thread services messages.
Only the window thread calls D3D9, and its Present counters must remain unchanged throughout each capture.
Leaving the variable unset retains the blocking handshake as a timing negative.

`tests/check-d3d9-multiple-parity.py REFERENCE CANDIDATE` compares the nine mono captures, checks the restacked raster and panel against the pattern, and correlates actual Present requests with delivered completion events by window and serial.
Its input directories contain `result.json`, `atoms.json`, `client.stdout`, `wire.jsonl`, `phaseN-screen.png` and the native window PNGs from the observer.
The checker requires zero stereo declarations, five correct input assertions and unchanged Present counts, and rejects the retained blocking-capture negatives.
Delivered XRecord GenericEvents may contain only their first 32 bytes; the checker uses window and serial and does not infer a missing MSC field.

### Acknowledgement transaction and surface lifetime controls

The Wine candidate checks the acknowledgement-property write before reparenting or declaring the native surface.
If the declaration API rejects the surface, Wine removes the temporary acknowledgement and restores the original native parent.
The producer observes the acknowledgement after synchronous surface creation and restores the caller's original property when its request scope ends.
Content declaration and membership maintenance remain separate operations.

`tests/fail-stereo-ack.c` interposes the actual Unix `NtUserSetProp` import in an isolated amd64 Wine client.
Compile it with `cc -shared -fPIC -O2 -Wall tests/fail-stereo-ack.c -o fail-stereo-ack.so -ldl`.
Wine's Unix library imports use the native Unix calling convention, including on amd64.
Set `WINE254_FAIL_ACK=fail` and preload that library for the client only to reject the version-1 acknowledgement write.
`observe` forwards the write and records its actual return value.
`fail-declare` forwards the acknowledgement write but intercepts the driver's resolved `stereo_declare_x11_child` function and returns `-ENOTSUP` before any native property writes.
Every injection must have its call receipt in stderr; a preload variable alone is not evidence that the call ran.

`tests/check-stereo-ack.py CAPTURE LABEL` correlates that receipt with the real DXVK acknowledgement or fallback log and the XRecord content and membership writes.
The retained old-module control rejects the write but still declares content, so the checker rejects it.
Both corrected failure routes produce no native declarations or membership writes, and their six captures match the unchanged Wine runtime exactly.
The forwarding control retains the exact first-paint and subsequent visibility and reparent checks.
These are private targeted-module results, not installed-package acceptance.

`tests/vulkan-surface-lifetime.cpp` includes the actual DXVK `wsi/wsi_wine_stereo.h` helper and links the matching DXVK utility archive.
Compile with the retained DXVK build's Vulkan and Win32 definitions and include directories; do not substitute a local implementation of the request helper.
It requires a private Wine prefix, the matching version-1 DXVK helper, Vulkan loader and capture rig.
Its observer protocol prints `phase=N logical=320x200 frame=ready` and waits for a newline while the window thread pumps messages.
The worker thread alone creates and destroys Vulkan surfaces; the window thread reparents and moves a valid Win32 child concurrently.
It creates no swapchain and makes no Present calls.

The control checks nested property restoration, a destroyed HWND rejected by the request helper without an invalid Vulkan call, reparenting, a detached native surface surviving HWND destruction until its real Vulkan destruction, and recreation.
Seventeen surfaces each declare content once, owner lists contain no duplicate entries and end empty, and actual XDestroyWindow requests remove all seventeen native windows.
Membership write and delete counts vary with the overlapping window operations and are not a fixed contract.
`tests/check-vulkan-surface-lifetime.py CAPTURE` checks those requests, snapshots and helper receipts, and requires measured overlap between surface-destruction intervals and window-operation intervals.
This is a legal bounded concurrency control, not sanitizer coverage or proof of arbitrary races, swapchain concurrency or rendered pixels.
