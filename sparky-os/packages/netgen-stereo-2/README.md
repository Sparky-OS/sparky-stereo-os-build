# netgen-stereo-2 (ORDER 50, step 2)

Netgen 6.2.2606+dfsg1-3+stereo3d1+lc1: Debian testing's -3 with the four patches of the published -1+stereo3d3+lc1 (load-nggui-by-soname, 0001 to 0003).
Debian's -3 makes netgen depend on libnglib-dev for the GUI library; the edition keeps load-nggui-by-soname.patch and `libnglib-6.2t64`, so the development package is not needed.
The drawing area (Togl child of a Tk window) is flat on the published Mesa because Tk draws it before it maps its window; the fix is Mesa patch 0045 (`../mesa`, waits for the next Mesa build).
`build.sh DEBIAN.dsc WORK` as for pymol-stereo-1.
