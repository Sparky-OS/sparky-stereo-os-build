# The published programs on qt6-base +stereo3d24 (row 863, part A)

`rerun-part-a.sh [OUT]` runs every row in one command and exits 0 only when each is as expected: the published set
(`sc50i-rig:a863-pubg`) against the same image with the staged qt6-base 6.11.2+dfsg-5+stereo3d24 and
sparky-stereo-graphics 0.2.18 by apt (`sc50i-rig:a863-q24`), one fresh Stereo KWin session per case.

| Row | Script | What runs |
|---|---|---|
| A1 | `a1.sh` | Kubrick, KAlgebra's 3D graph, Kalzium's molecule view, Fraqtive's 3D view: resizes, tab and dock changes, full screen; each program's own proof measure (the Qt rig's `an-kub.py`, `an-ka.py`, `an-kz.py`, Fraqtive's `measure.py` rule); `lag-selftest.py` |
| A2 | `a2.sh` | VLC Stereo (Qt 5) playing a marked 3D film: resize, the playlist shown and hidden, full screen and back; VLC's own `check-embedded.py` rule |
| A3 | `a3.sh` | Krita's stereo canvas layer (a child `QWindow`) with a side-by-side document: dockers hidden and shown, resizes; its known bad case (the layer moved 40 px) |
| A4 | `a4.sh` | Qt's own client-side frame around a plain window, resized by its corner and its left edge with the button held; its known bad case (`FC_STALE=1`) |
| A5 | `a5.sh` | The installer's slideshow (`show.qml` with Calamares' `calamares.slideshow` module, unpacked, nothing installed) in a window of its own, the output in its 3D twin mode |
| A6 | `a6-images.sh` + the Octave rig | Octave's 2D-screen row on Xvfb |

How a placement is read:
- `r863-probe.cpp`, preloaded through QtCore's `qt_startup_hook` (Qt 6, and built against Qt 5 for VLC), logs each watched widget's place and the window's frame margins at every update request and expose, drives the steps and waits for each capture (`step-K.ready`, `step-K.captured`).
- `lag.py` reads `WAYLAND_DEBUG=client` and says which commits of the parent carried a declared surface away from its widget.
- `analyze-prog.py` measures each capture: the eyes differ only inside the widget's rectangle, plus the program's own measure.
- `verdicts-a.py` judges each program as a published/+24 pair.

The traps met building it are in the skill page `native-linux/references/qt-stereo-opengl-widget.md`.
