# 3D thumbnails at every scale (ORDER 576)

stereo-layer 1.18.1-1+lc1 and dolphin 4:26.08.0-1+stereo3d8+lc1.

On a 13.3 inch full HD notebook at 125 % Dolphin's 3D thumbnails showed a strip of each picture and the desktop through the rest of the cell; at 100 % they were right (Daniel, 2026-11-14: "in 3D they are alpha to the desktop background"; "in 100% it works").

The cause was in the stereo layer: an eye image that carries its window's device pixel ratio was copied into the surface's buffer at its size divided by that ratio.
stereo-layer 1.18.1 copies every sample to its own place, and puts the surface of a 3D area on whole device pixels, so every program on the layer has the picture under its hole to the pixel at every scale.
Dolphin +stereo3d8 draws its eyes on the layer's canvas (the window's own device pixels), so nothing is resized at any scale.

## Files

- `patches/dolphin-stereo-thumbnails-on-device-pixels.patch`: the icon view, the information panel and the tooltip draw each eye on `Stereo::WidgetLayer::eyeCanvas()` and hand it over with `setEyes()`; a picture's hole is the pixels its pixmap is drawn on.
- `changelog/dolphin.items`: the changelog items, one paragraph per item.
- `next-source.sh PUBLISHED.dsc OUT`: the next +lc1 source of dolphin from the published +stereo3d7+lc1 (`repo/lc-successor.py --in-place --overlay`).
- `round.sh WORK STEREO_LAYER_CLONE REV PUBLISHED_TREE ARCHIVE_DIR [STEP...]`: both builds in order, each through `../depth-source/build.sh` (Lean Code, the link and start gate, `lean.release check-debs`).

## Installing over the published round

stereo-layer 1.18.1 alone repairs the published Dolphin +stereo3d7 (no backdrop through any cell); with Dolphin +stereo3d8 the thumbnails are exact to the device pixel.
Dolphin +stereo3d8 needs `libstereo-layer1 (>= 1.18.1)`, which its package states.

## Dependencies added or changed

- dolphin: `libstereo-layer-dev (>= 1.18.1)` in Build-Depends (from 1.18.0); the edition's own package, built in step 1.
- No new package name anywhere.
