# GStreamer MP4 stereo marks

This recipe follows the edition's installed deb-multimedia source, gst-plugins-good1.0-dmo 1.28.9-dmo1. Its successor is 1.28.9-dmo1+stereo3d1+lc1. The full plugin set and Debian control are preserved; the change belongs to qtmux, not to a later file rewrite.

The muxer reads multiview-mode and multiview-flags from encoded video caps. It writes the Spherical Video V2 st3d box after codec configuration and before optional aperture/aspect boxes: mono 0, top-bottom left first 1, side-by-side left first 2, side-by-side right first 4. It warns for arrangements or transforms st3d cannot express; it does not claim the custom mode without its additional description. Existing svmi is preserved. The readable writes-st3d capability lets a recorder refuse an older muxer before opening a recording.

Source: https://github.com/google/spatial-media/blob/master/docs/spherical-video-v2-rfc.md#stereoscopic-3d-video-box-st3d

Read-only upstream main, path history, merge-request and issue searches on 2026-11-23 found no matching st3d writer. The latest qtmux path change concerned reordered presentation timestamps. Names credited in the original element: Thiago Sousa Santos and Mark Nauwelaerts. This patch is Daniel Campos Ramos's edition change; nothing was filed upstream.

Native plugin proof passes x264 frame-packing SEI and MP4 st3d together. Full binary/source package gates and file-by-file comparison remain required before stage admission. VA and NVENC encoder changes belong in gst-plugins-bad1.0-dmo and are separate unfinished work; Kamoso refuses those unmarked routes before recording.
