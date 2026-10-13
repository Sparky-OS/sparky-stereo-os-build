# Plasma stereo GL show

This integrates the validated saver controller into our Plasma forks. The
idle program uses KIdleTime; the real KScreenLocker greeter owns the locked
case. Each process has one separate controller, one private Xvfb and one
active saver. All its outputs receive the same world and camera pair.
Authentication and input stay in the existing greeter.

`stereoshowrc` is a Plasma setting, exposed in Screen Locking: enable the show,
start after 135 idle minutes, and change saver every 10 minutes. KConfig
notifications apply changes to running receivers. A manual lock starts the
show immediately while AC and at least one display are on. Battery and
DPMS-off stop the producer; normal idle input dismisses the unlocked show.
The compositor's Wayland idle inhibitors suppress its idle timeout.

The edition's `sparky-stereo-power-profiles` package owns dimming at 15 minutes,
screen-off/locking at 165 minutes, laptop AC sleep at four hours, and battery
screen-off at 20 minutes. Desktops do not auto-sleep. This integration requests
no power inhibitor and writes no console or power-controller settings. The
visible AC interval is 30 minutes. HDMI-CEC remains the existing power path;
the headless tests neither connect a TV nor exercise physical standby.

The main greeter surface stays undeclared and draws the normal 2D prompt.
`StereoBackground` attaches an input-empty full-SBS subsurface below it, using
the shared helper's format-only Wayland call. The parent requests an alpha
buffer before creation. If frames stop or are rejected, the subsurface is
removed and the normal wallpaper returns. The patches hide the normal
wallpaper only while a stereo background is active. No saver code is loaded
into the greeter.

`FrameClient` accepts bounded sealed memfds over a private inherited socket.
It checks the envelope, sequence, format, dimensions, exact storage size,
owner and seals, closes rejected descriptors, and acknowledges one frame at a
time. The renderer does not wait on the unlock UI. A failed producer is
excluded for that controller session; no eligible entries means static
fallback. The native transport tests include truncation, excess descriptors,
wrong dimensions/format/storage, mutable buffers and replay.

The private Xvfb announces layout capability version 1. That deliberately
leaves packing to this layer: Mesa's stereo fork enables its own allocator at
version 2, and enabling both on the producer display gives an empty right eye.
This private capability does not alter the real KWin declaration. General
wrapper coexistence with Mesa's native stereo allocator on a version-2
application display is separate work, not covered by this integration.

## Build and verification

From `gl-stereo/` on the host, these scripts run all builds/tests in fresh
non-root containers, with four CPUs and no host session sockets:

```
./test.sh
./test-plasma.sh
```

The first validates the layer and saver catalogue using `gl-stereo-test:3`.
The second uses `gl-stereo-plasma:4`, the permitted `/dev/dri/renderD128` render
node only, and KWin's virtual OpenGL backend. The render GID defaults to 125;
`GL_STEREO_RENDER_GID` can match another test machine. No card/KMS node is
passed. A workspace copy of the image's KWin executable omits its file
capability so the local fork/SDK library path reaches its child greeter.
All buses, sockets, input injection, UPower/logind fixtures and DPMS actions
are private to the container. `.artifacts` lists the rebuildable resources.

`verify.sh` builds the receiver, real greeter and KCM together, runs native
transport/policy tests and KDE's PAM/logind regression tests, then checks
compositor captures. The deterministic fixture uses the real starfield's
known camera depths at an unobstructed screen position. LEFT/RIGHT PNGs must
match analytic disparities, and the actual password field must have the same
mask in both eyes. The runtime tests shorten the configurable idle interval
to 60 seconds; the shipped 8100/600 values and edition power config are checked
separately. They do not pretend to have waited 135 minutes.

Further checks cover battery, DPMS, dismissal, visible idle inhibition,
producer death/static fallback, manual lock/unlock and two virtual outputs.
The old-output mutation suppresses the subsurface declaration; both idle and
real-lock eye checks must fail. The KCM is rendered with decided defaults;
its generated settings are tested for save, defaults and live notification.
Evidence and exact results are in `out/plasma/verify.log` and the root REPORT.

## Installation and forks

`patches/kscreenlocker-stereo-background.patch` contains the greeter and
Screen Locking KCM changes. `patches/plasma-desktop-stereo-background.patch`
contains the lock theme change. Apply these only to our forks. The local
KScreenLocker fork uses the pinned v6.7.4 archive; `build-greeter.sh` verifies
its checksum. Its SDK extraction preserves the rig's forked runtime libraries.

Build/install the native library with CMake (`/usr`, sysconfdir `/etc`). Its
installed `StereoShowConfig.cmake` allows KScreenLocker to find it. Build
KScreenLocker against the matching headers/library, then install both forks.
The receiver depends on the separate proposed
`stereo-declare-wayland-format.patch`; integrate it into libstereo-declare
before packaging the receiver. The accepted X11 helper patch is unchanged.

Install the layer and savers with `make install install-savers`, then
`make install-catalogue` only after the packaging qualification suite passes.
The last step relocates receipts without changing their binary hashes. Ship
the receipt as trusted package data, never writable by a saver; stripping or
rebuilding a renderer requires renewed qualification and matching receipts.
The production receiver reads `/usr/share/gl-stereo/catalogue.json` and runs
`/usr/lib/gl-stereo/savers/controller.py`. Test oracle paths are not used in
the separately staged production build. Empty/stale catalogues fall back.

The autostart entry is KDE-only, and default settings live in
`/etc/xdg/stereoshowrc`. User settings take precedence. The fresh suite stages
the native install and verifies all relocated receipt hashes. Nothing is
installed on the host, merged upstream or published by these scripts.
