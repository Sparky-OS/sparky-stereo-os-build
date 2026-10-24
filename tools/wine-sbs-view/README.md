# Wine SBS image view

Select standard full side by side output in the application, with the left eye first.
Size its image control to the native packed picture size.
Run `wine-sbs-view X11_IMAGE_WINDOW_ID` with the X11 ID of that image drawable.
The ID is the rendering child of Wine's offscreen GLX window, not the application window with its controls.
Use `xwininfo -root -tree` and inspect the selected drawable before declaring it.

The helper uses Composite and Damage to copy the complete native pixmap into a separate stereo image window without resampling.
It declares this window once through libstereo-declare, with its native one-view size.
Stereo KWin chooses the output format and scales each view once.
The original application and its controls remain ordinary 2D.
Closing the image window stops the helper.
A disappearing or unmapped source closes the view instead of leaving a stale picture.
If Wine replaces its rendering window, select the new drawable explicitly.

The helper cannot identify the eye order or remove controls from an arbitrary source.
Do not select half-width, stretched or mixed-eye display modes for a native pixel check.
Without the stereo declaration protocol, the helper exits and the original application's 2D view remains available.

Build with `make` against libstereo-declare 1.4.0, Xlib, Composite and Damage.
For the distribution package, copy this directory to a disposable source tree and use the edition's standard `lean.debian_prepare` adapter before creating the source package.

The source backing pixmap is reacquired on repaint so graphics buffers replaced without a resize are followed.
