# stereo-widget-move: a stereo QOpenGLWidget whose ancestors move while the window repaints

Queue row 863's test of qt6-base (from 6.11.2+dfsg-5+stereo3d24).
The edition's Qt gives a stereo `QOpenGLWidget` a native window of its own (a subsurface on Wayland) under alien ancestors.
Up to +stereo3d23 that window was moved inside the backing store's flush, and on Wayland the move repainted the window from within that flush and freed the list of textures the flush then read (patches `o863-0001` and `o863-0002` fix it).

Run, with an image that holds the Qt build under test (its libqt6* packages and qt6-base-dev), Stereo KWin, Mesa, valgrind, g++, pkg-config, python3 and bc:

```
GPU=nvidia ROW863_CONTAINER_PREFIX=NAME bash run.sh IMAGE RESULTS [LIBDIR]
```

- One fresh container and Stereo KWin session per case (`--cpus 4`, `--network none`, `--ulimit core=1`, uid 1000); KWin on the NVIDIA card through CDI with `GPU=nvidia` (every case is a loop), else on the AMD render node; the program always on llvmpipe.
- `LIBDIR` lays a development build's `libQt6Widgets`, `libQt6WaylandClient` and `libQt6OpenGLWidgets` (the same Qt version) over the image's.
- Four shapes: `scroll` (a scroll area's content), `viewport` (two graphics views of one scene with stereo viewports beside a dock that hides and shows), `itemview` (cell widgets of a table scrolled with `QWidget::scroll()`), `float` (a dock floated and docked again).
- Rows, one per case, exit 1 when one is not as expected: `memcheck-MODE` (no error block naming `QPlatformTextureList`, the run ended by itself, every visible stereo window placed after every step) and `lag-MODE` (the run ended, every step placed; `lag.py` counts the commits of the top level that carried a stereo window away from its widget, and those that reached the screen; `ROW863_LAG_MAX=N` makes that a limit).
- `ROW863_MODES`, `ROW863_MEMCHECK_STEPS`/`_WAIT`, `ROW863_LAG_STEPS`/`_WAIT` change the run; `ROW863_CONTAINER_IDS=FILE` appends each container's ID to FILE.

Measured on 2026-11-24 (Stereo KWin 6.7.4 +stereo3d64, Mesa 26.1.6 +stereo3d29): +stereo3d23 fails `memcheck-scroll`, `-viewport` and `-itemview` with 31 error contexts each, all reads of a freed `QPlatformTextureList`; the fixed build passes every row.
