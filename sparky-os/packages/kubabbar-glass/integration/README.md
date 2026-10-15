# Background alpha integration

Install the two directories in `usr/share/plasma/desktoptheme/` beside their existing alternatives.
Keep `plasma-theme-oxygen` as a dependency because `sparky-stereo-oxygen` inherits its foreground artwork.
Apply `oxygen-defaults.patch` to the look package source so the default Look and Feel selects the derived Oxygen style.
The original Oxygen style and qplatinum package stay installable.
Kubabbar Glass is the settled name, with `kubabbar-glass` as its package identifier.
Its Look and Feel currently applies the milestone 1 drawings; complete application widgets and GTK follow in milestone 2.

For both looks, retain the edition's `Effect-translucency` values in `config/kwinrc`.
Explicitly set `blurEnabled=false` and `contrastEnabled=false` in its `[Plugins]` group.
The SVG backgrounds have their own 91 percent alpha; do not set opacity on the whole plasmashell window or an applet's content item.
The included test applet is a fixture and is not in the install payload.

Reproducible verification: `bash rig/run.sh alpha-THEME-BACKGROUND-MODE` in the source bundle, where THEME is classic or oxygen, BACKGROUND is black or white, and MODE is 2d or stereo.
Run `tools/check_frame_alpha.py` and `tools/check_compositor_alpha.py` inside the documented fixture image.
After all alpha and window capture cases, `bash rig/verify.sh` runs the asset, background, window and depth checks in that image.
The compositor measurement requires background alpha 232/255, the nearest 8-bit value to 91 percent and the same value measured for inactive windows.
The SVG opacity 233/256 compensates Qt's fixed-point group-opacity quantisation so the resulting pixel is 232/255 in both QtSvg and librsvg.
It rejects an opaque or whole-applet-faded result and requires OpenGL, loaded Translucency and real stereo capture metadata.
