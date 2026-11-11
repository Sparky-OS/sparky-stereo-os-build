# Viewers: unmarked pictures and the picture area's background (ORDER 504)

stereo-layer 1.17.3-1+lc1 (built with `../depth-source/stereo-layer-source.sh` and `build.sh stereo-layer`), gwenview 4:26.04.0-1+stereo3d9+lc1 and kio-extras 4:26.04.0-1+stereo3d5+lc1.

- stereo-layer: an unmarked picture within 2:1 to 3.6:1 is a side by side pair by its shape (the pixel comparison no longer vetoes it), and `WidgetLayer::shownRect()` says where the picture shows.
- `patches/stereo-opaque-picture-background.patch` (gwenview): the hole is that rectangle, the view's own opaque background around it.
- `patches/kio-extras-thumbnailer-versions.patch`: the image and JPEG thumbnailers' versions go up, so flat thumbnails cached before are made again.

`build.sh PKG OLD NEW PATCH ITEM STAGE_DIR PUBLISHED_TREE OUT` builds one of the two from the published +lc1 source, after the way of `../spatial-video-rebuilds/gwenview-stereo3d8-build.sh`; STAGE_DIR holds the staged stereo-layer debs.
