# stereo-matplotlib

Matplotlib's 3D plots in stereo on Sparky Stereo OS, as the package `python3-stereo-matplotlib` (module `stereo_matplotlib`).
It lives outside Matplotlib: Matplotlib's contribution guide does not accept work an AI agent took part in (doc/devel/contribute.rst, "Use of Generative AI"), so nothing of it is offered there.
It replaces the module of 2026-10-05 in `sparky-os/upstream/matplotlib` (mpl_parallel_stereo.py), which stays there as the record.

## What it does

- Every `Axes3D` gets two parallel cameras, never toe-in: a shear of the view, `x' = x + s c (d - z0)`, zero at the axes' centre (perspective: a camera moved by `s` with its frustum shifted back; orthographic: the shear about the camera target).
- The offset is fitted, never set: the largest for which every point the figure projects while it draws (data, panes, grid, ticks, labels) stays inside the person's limits on the 3D area (Daniel, 2026-11-18, "the camera offset is the largest for which every pixel of the 3D area stays inside the person's limits"). The limits come from the one place through libstereo-declare (`stereo_declare.x11_buffer_limits` on the declared window); a figure never shown in 3D is exported with the person's own numbers from the desktop's 3D Depth settings, the picture taken as a view 1920 wide.
- `stereo_matplotlib.show()` shows every open figure with its 3D area as a declared pair: the figure's canvas gets an X11 window of the module's own, two views wide, declared with `stereo_declare_x11_child()` and the size one view is shown at; the toolbar stays 2D and gains "Enable 3D" and "3D display settings...". Measured on TkAgg and on QtAgg with Qt on xcb; Qt on native Wayland and other backends show the figure flat and say why, once.
- `save_stereo_figure(fig, 'plot.pns')` writes PNG with `sTER` (mode 1, the padding of PNG Extensions 1.4.0 section 3.6), `.jps` writes JPEG with the stereo layer's JPS block (`stereo_jps_encode`), both only to new files. `save_stereo_frames` and `save_stereo_video` keep the old module's frames and marked video.

## Build and test

`OUT=DIR build.sh` in a container with the Build-Depends of `debian/control`; the tests (`tests/`) run in the build unless `nocheck`.
