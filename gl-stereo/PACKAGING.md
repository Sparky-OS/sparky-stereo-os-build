# Packaging for Sparky Stereo OS

The layer is GPL-2.0-or-later. The retained historical MIT text covers
files that still carry that alternative; it does not relicense the new core.
The shared stereo-declare library is MIT and remains a separate dependency.

Build in a Debian testing container with at most four CPUs. Build dependencies:
`build-essential`, `pkg-config`, `libgl-dev`, `libegl-dev`, `libx11-dev`, and
the installed `stereo-declare` development package. For the test image also
install Xvfb, mesa-utils, the XScreenSaver GL packages, Python Pillow/NumPy,
CMake, Ninja, Wayland development files/protocols, and ParaView/Python bindings.
The Debian package builds link against libstereo-declare-dev (>= 1.1.0)
from the edition repository; no helper source is built.

The format-only X11 and Wayland calls are provided by libstereo-declare 1.1.0.
The retained helper patches document the earlier integration; package builds
do not apply them. dpkg-shlibdeps generates the runtime dependency from the
imported symbols. No class or sub-class is declared by the layer, including
when old GL_STEREO_CLASS settings are present.

Install `libgl-stereo.so` in `/usr/lib/gl-stereo/`, `gl-stereo-run` in
`/usr/bin/`, and this report, README, licence and tests in the source package.
Runtime dependencies: libc, libGL, libEGL, libX11, libstereo-declare1 and Python 3.
Depend on `python3-tk` for the settings dialog and `kscreen` for Display settings.
Do not put the library in `/etc/ld.so.preload`: enable it per application.
32-bit programs need a separate i386 library build; this work tests amd64 only.

Package control provenance follows the edition's packaging skill:

```
Package: gl-stereo
Version: 0.2.0-1
Architecture: amd64
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Section: graphics
Priority: optional
Homepage: https://sparkylinux.org
Description: OpenGL stereo layer for KWin full side-by-side windows
```

Generate dependencies with dpkg-shlibdeps when integrating the real Debian
package. Do not invent a dependency version from the local helper build.
This workspace supplies packaging notes and an install target, not a released
or signed .deb. No repository, host installation or publication is performed.
Credit: Sparky Stereo OS, Daniel Ramos's edition of SparkyLinux (by Paweł "pavroo" Pijanowski).

Examples:

```
gl-stereo-run -- glxgears
gl-stereo-run --settings -- glxgears
gl-stereo-run --render-resolution 1920x1080 -- glxgears
gl-stereo-run --enable-3d off -- glxgears
gl-stereo-run --display-settings
gl-stereo-run -- pvpython scientific-scene.py
```

The dialog has Enable 3D, Render resolution per eye, and Display settings.
The shortcut executes `kcmshell6 kcm_kscreen`. No output packing choices
exist in the launcher. The default follows the application's window dimensions,
including screen-sized dimensions supplied by fullscreen applications. An
explicit resolution changes the per-eye drawable dimensions. KWin owns final
scaling and output format selection. Native fullscreen/KWin presentation and
TV comfort are not verified by Xvfb tests.

## Saver prototype

The lane-owned test image is `gl-stereo-test:3`. Its Dockerfile omits ParaView
to keep the image small and adds the dependencies needed to build only the
XScreenSaver rocks hack. Tests and source builds run as the workspace user.
The source archive is hash-pinned by `savers/build-rocks.sh`; it and its build
tree are removed when that step ends. The helper dependency patch is unchanged.

After the saver suite, `make install-savers DESTDIR=...` stages the native
starfield, patched rocks, private-display announcer, broker/controller modules
and licence/design documents. It does not install a service, greeter plugin,
autostart or session/power setting. Run the controller with Python 3; Pillow and
NumPy are test dependencies, not controller runtime dependencies. Xvfb and the
selected saver libraries are runtime dependencies for this prototype.

Generate the catalogue against installed paths and exact binaries during
package validation. Never ship the development catalogue's workspace paths.
The greeter receives only validated pixels through inherited descriptors; its
real adapter and Plasma settings UI are the next integration review. Keep the
approved 2 h 45 min screen-off/lock and 4 h plugged-laptop sleep policies.

### X11 sizing with current KWin

The layer reads the announced support version when activating a window.
For version 3 and later, KWin owns the double-width X11 buffer: client resize
requests stay one eye wide, and KWin's synthetic configure events already
carry one-eye geometry. Older compositors retain the layer's resizing.
Legacy stereo visual twins are resolved to a mono FBConfig inside the driver;
the layer keeps ownership of its packed framebuffer, including virtual
quad-buffer programs.

`./test-window-sizing.sh` runs the saver/output suite and a fresh virtual KWin
regression. It uses the lane-owned `gl-stereo-sizing:1` tag of the existing
`kwin-package-17-rig:m2` image and its read-only rig harness. Only the explicitly
permitted renderD128 node enters that container, with no host display sockets.
The tests check initial sizing and three resize APIs, versions 0/1/2 under
Xvfb, real version 3 and a private version-4 announcement, both eye pixels and
composed captures, quad-buffer selection, and glxgears. A mutation restoring
the old unconditional doubling must fail at a 1600-pixel window instead of 800.
Results and LEFT/RIGHT captures are in `out/window-sizing/`. This script is a
lane integration test; a downstream runner must provide an equivalent stereo
KWin image and harness before using it outside this workspace.

The real source package uses debhelper and 3.0 (quilt). Binary packages are
`gl-stereo`, `gl-stereo-savers`, `gl-stereo-show`, `libstereoshow1` and
`libstereoshow-dev`. The saver package includes our starfield and controller;
rocks, gears, molecule and rubik come from the rebuilt XScreenSaver packages.
Qualification runs after stripping and binds the final binaries by SHA-256.
The native library's development package is a build dependency of the
patched KScreenLocker. See packaging/README.md and workspace REPORT.md for
build commands, measured versions and the current verification state.

### Complete OpenGL saver catalogue

Version 0.3.0 packages 132 selectable savers: all 130 standalone programs from the two Debian OpenGL packages, plus Starfield and Rocks.
The Mapscroller helper remains installed and is not a separate chooser item.
The qualification manifest records exact executable, stripped layer, original settings and capture hashes.
The package build rejects an incomplete manifest or different binaries; new builds need fresh qualification when their rendering binaries change.
Regular screen-level entries use 0.5% separation with camera-derived convergence, allowing gentle depth around the screen plane.
Ten picture or orthographic scenes remain flat.
Flurry's owning patch exposes its existing CPU-projected particle camera through OpenGL when Enable 3D is active; its original 2D path stays pixel-identical.
The chooser preserves every entry and author credit, and saves the user's rotation selection in Plasma's existing configuration without changing its timers.

`packaging/test-installed.sh` exercises the installed layer, 132-entry catalogue, chooser and controller.
`packaging/test-installed-sizing.sh` uses a self-contained virtual KWin harness and the installed files.
`packaging/test-installed-plasma.sh` supplies only deterministic catalogue data to installed producers and receivers, restoring the production catalogue on exit.
Run it in an isolated disposable container with that data file writable to the test user.
The all-saver audit scripts retain independent camera controls, exact stock/disabled 2D comparisons and fresh KWin LEFT/RIGHT captures.
`packaging/stage-all-savers.py` stages the two complete source upload sets only after the build, installed-file, catalogue and lintian gates pass.
