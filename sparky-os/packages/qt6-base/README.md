# Qt Widgets paper depth

Qt +stereo3d26 uses both element steps and the selected output width from one Wayland event group. Declared negative depths use the behind step. Positive depths use the in-front step. Graphics effects such as the Calligra Words canvas shadow composite the source drawn for each eye.

`libqt6waylandclient6` requires an installed KWin to be +stereo3d70 or newer through its Debian Breaks. Build the Graphics page at its next version with `build-graphics-for-26.sh`, since its Qt dependencies name the exact Qt version.

`next-source-26.sh` prepares the closure from qt6-base +25. The sources used for initial qualification have `SOURCE_DATE_EPOCH=1795729577`. The binary build runs the Qt widget repaint tests for per-eye painting, directional steps and the canvas shadow.

Credits go to The Qt Company for QWidget, the repaint manager, the window, the graphics-effect code and Qt's print preview, with Intel Corporation among QWidget's copyright holders. Daniel Ramos designed the shared stereo element depth.
