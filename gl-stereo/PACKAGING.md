# Packaging for Sparky Stereo OS

This prototype is GPL-2.0-or-later. The retained historical MIT text covers
files that still carry that alternative; it does not relicense the new core.
The shared stereo-declare library is MIT and remains a separate dependency.

Build in a Debian testing container with at most four CPUs. Build dependencies:
`build-essential`, `pkg-config`, `libgl-dev`, `libegl-dev`, `libx11-dev`, and
the installed `stereo-declare` development package. For the test image also
install Xvfb, mesa-utils, the XScreenSaver GL packages, Python Pillow/NumPy,
CMake, Ninja, Wayland development files/protocols, and ParaView/Python bindings.
The helper source mount is read-only. Its build/install prefix is container-only.

Install `libgl-stereo.so` in `/usr/lib/gl-stereo/`, `gl-stereo-run` in
`/usr/bin/`, and this report, README, licence and tests in the source package.
Runtime dependencies: libc, libGL, libEGL, libX11, libstereo-declare1 and Python 3.
Recommend `python3-tk` for the settings dialog and `kscreen` for Display settings.
Do not put the library in `/etc/ld.so.preload`: enable it per application.
32-bit programs need a separate i386 library build; this work tests amd64 only.

Package control provenance follows the edition's packaging skill:

```
Package: gl-stereo
Version: 0.1~sparky9~0
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
Credit: Sparky Stereo OS, an edition of SparkyLinux, created by Paweł
“pavroo” Pijanowski and Daniel Ramos (Capitain Jack).

Examples:

```
gl-stereo-run -- glxgears
gl-stereo-run --settings -- glxgears
gl-stereo-run --render-resolution 1920x1080 -- glxgears
gl-stereo-run --enable-3d off -- glxgears
gl-stereo-run --display-settings
GL_STEREO_CLASS=scientific gl-stereo-run -- pvpython scientific-scene.py
```

The dialog has Enable 3D, Render resolution per eye, and Display settings.
The shortcut executes `kcmshell6 kcm_kscreen`. No output packing choices
exist in the launcher. The default follows the application's window dimensions,
including screen-sized dimensions supplied by fullscreen applications. An
explicit resolution changes the per-eye drawable dimensions. KWin owns final
scaling and output format selection. Native fullscreen/KWin presentation and
TV comfort are not verified by Xvfb tests.
