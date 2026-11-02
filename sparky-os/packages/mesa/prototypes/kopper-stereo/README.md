# Kopper stereo pixmap test series

This series adds packed X11 presentation for stereo GLX windows rendered by Zink through Kopper.
It applies after the edition's Mesa 26.1.6 +stereo3d17 patches.
It is kept outside the source-preparation recipe pending integration review.
It does not create a source package or change a package version.

Vulkan WSI uses the native window extent.
The stereo path instead allocates GPU eye resources, packs their pixels side by side, maps the result and uploads it through Mesa's existing X11 pixmap Present loader.
This incurs GPU readback and X11 upload; it is a correctness foundation, with no performance claim.
The ordinary mono path keeps its existing WSI implementation.
Offscreen stereo resources invalidate on viewport changes, and a geometry change advances the attachment stamp before allocation.
The GLX loader declares the packed image before Present and retains the live X-window declaration across drawable-only recreation.
The existing X-window tracker continues to own reparent and destruction membership maintenance.
Content declaration and owner-list maintenance remain separate operations.

## Upstream credit

The first patch is Mike Blumenkrantz's [b258e2a051761868734f09774295ee9cee5f7e8d](https://gitlab.freedesktop.org/mesa/mesa/-/commit/b258e2a051761868734f09774295ee9cee5f7e8d), dated 6 October 2026.
It moves Present event selection to the sync-value query.
It does not implement `glXWaitForSbcOML`.
His [f3f63efe9ca77e197210d9ece06f8e5cedc0f853](https://gitlab.freedesktop.org/mesa/mesa/-/commit/f3f63efe9ca77e197210d9ece06f8e5cedc0f853) addresses front readback in a newer WSI implementation; its missing prerequisites prevent an unchanged application to this base.
That change is not included here.

## Measured scope and remaining work

Headless RTX 3060 tests through NVIDIA Vulkan verified native stereo startup, first resize and repeated resize with exact GL back/front arrays, packed pixmap pixels and compositor eyes.
Native two-child tests verified reparenting, drawable recreation, destruction before another swap and four-sample MSAA, with unchanged ordinary window pixels.
The fixture intentionally retains the X error from deleting a GLX drawable after its X window and records the unsupported SBC wait separately from actual Present completion events.
Mono presentation without front readback matched the installed predecessor pixel for pixel.
The predecessor and this series both retain mono front-readback failures.

Wine testing produced exact packed pixmaps but exposed the existing whole-window declaration copy in `winex11.drv` and stereo processes that ended with SIGKILL after printing their success line.
This series therefore does not qualify the complete Wine route.
No proprietary NVIDIA GLX stereo, AMD, Wayland, Vulkan API, package or release acceptance is implied.
Clipping, overlap, input and DPI remain separate gates.
