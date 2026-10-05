Xwayland stereo child patches

Base: xwayland-24.1.13, commit c5a47fd4e3810a15632789b3291b1fc00db50f0f.

The patches are exported from the local `stereo3d` branch in order:

- 0001 creates a surface for a redirected child window.
- 0002 makes the manually redirected child condition use the window's
  toplevel and keeps the child surface associated with its X window.
- 0003 registers and posts damage for a redirected child surface.
- 0004 preserves alpha on 32-bit root surfaces used by the controls layer.

They are the Xwayland part of Sparky Stereo OS's full-side-by-side child
surface path. The Debian package version is 2:24.1.13-1+stereo3d1.
