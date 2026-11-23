# netgen-stereo-2 (ORDER 50, steps 2 and 5)

Netgen 6.2.2606+dfsg1-3+stereo3d1+lc1: Debian testing's -3 with the four patches of the published -1+stereo3d3+lc1 (load-nggui-by-soname, 0001 to 0003).
Debian's -3 makes netgen depend on libnglib-dev for the GUI library; the edition keeps load-nggui-by-soname.patch and `libnglib-6.2t64`, so the development package is not needed.
The drawing area (Togl child of a Tk window) is flat on the published Mesa because Tk draws it before it maps its window; the fix is Mesa patch 0045 (`../mesa`, in Mesa 26.1.6-1+stereo3d28 and later).
`build.sh DEBIAN.dsc WORK` as for pymol-stereo-1.

## 6.2.2606+dfsg1-3+stereo3d2+lc1 (step 5)

The successor of the staged +stereo3d1+lc1 source (the accepted pool of row 794, `.dsc` SHA-256 bc077655...), made the way every in-place successor is made:

- `prepare-source-stereo3d2.sh STAGED_DIR OUT TOOLKIT` (with `SOURCE_DATE_EPOCH` from the recipe's last commit) runs `repo/lc-successor.py --in-place` with `overlay-stereo3d2/` (patch 0004, the whole series, the list of our files for the copyright file) and two `--depends` edits that add `libstereo-declare-dev (>= 1.12.2)` and `pkgconf` to Build-Depends; nothing else of `debian/` changes.
- `build-stereo3d2.sh SOURCE_DIR WORK TOOLKIT` builds the binaries in a container with the build dependencies, through Lean Code, then `lean.release check-debs`, which writes the build record.

Patch 0004 draws the drawing area for each eye whenever the desktop offers a stereo visual: "Enable 3D" (View, Viewing Options; on by default, `stereo3d.enable` in `ng.opt`) asks Togl for the quad-buffer widget at the start, and a 2D desktop keeps one picture with nothing said.
The separation is no longer the constant 3 % of the distance looked at: before the two eyes the scene is drawn once from the camera between them, its depth is read, and the separation is the largest under which every pixel of the drawing area stays inside the person's depth limits, read through libstereo-declare on Togl's window; a change of the limits redraws the view.
Netgen has no separation setting; Viewing Options has a button to the desktop's 3D display settings.
When the limits are not offered, do not arrive or cannot be read, the status bar says so once, in ten languages (Tcl's msgcat, in `ng/stereo3d.tcl`).
The program needs libstereo-declare 1.12.2 (row 835) and the Mesa with patch 0045 in the same round.
