# gimp: the stereo GIMP

Debian's GIMP 3.2.8-1 with the canvas of a stereo image shown per eye (queue row 137 with row 148, the stereo GIMP's milestone 1).

- **What it does:** an image with the layers "Left eye" and "Right eye" (as the stereo pictures plug-in, package `gimp-stereo-pictures`, opens MPO, JPS and PNS files), or a side-by-side or top-and-bottom picture in one of the plug-in's editing modes, is drawn once for each eye while View > Enable 3D is on (the default). Each eye is the canvas at its own size, drawn from that eye's own content; the edition's GTK 3 hands both to Stereo KWin side by side, left first, declared once, and KWin does the one resize. Guides, the selection, paths and the tools' outlines stay over the picture at the screen, the same in both eyes. Where the canvas cannot be shown per eye (a window drawn by the processor on Wayland; an X11 window on Mesa's zink, where GTK 3 draws a window holding an OpenGL area black, a fault of GTK 3's own), the canvas draws the left eye with its guides and outlines and the status bar says why; turning Enable 3D off and on tries again. View > Display Settings opens the display settings. A 2D image is drawn as before.
- **The patches** (after Debian's series): `stereo3d-canvas-per-eye.patch` (the canvas: `app/display/gimpdisplayshell-stereo.c`, the render cache per eye, GimpCanvas's underlay, the View actions, the image window's alpha channel on X11) and `stereo3d-canvas-per-eye-po.patch` (the strings in pl, pt_BR, fr, de, es, ja, ko, zh_CN and zh_TW; "Enable 3D" and "Display Settings…" are the stereo layer's words).
- **debian/control:** `libgtk-3-dev (>= 3.24.52-3+stereo3d1~)` and `libepoxy-dev` (the stereo GtkGLArea), and `libkf6kcmutils-bin` (kcmshell6) and `kscreen` (the display page) in gimp's Depends (View > Display Settings).
- **Built in the edition's environment** (Debian testing, deb-multimedia, the edition's tree): deb-multimedia's libmypaint 1:1.6.1 (`libmypaint0`) wins over Debian's 1.6.0 (`libmypaint-1.5-1`) by its epoch, so this GIMP links `libmypaint.so.0` where Debian's links `libmypaint-1.5.so.1`; it is the only library that differs (measured by `ldd` over the program and its plug-ins).
- **Build:** `build.sh WORK DEBIAN_SOURCE SIBLINGS REPO`: `make-source.sh` makes the `+lc1` source (Lean Code keeps libgimp's sources and headers, which g-ir-scanner and gi-docgen read, and the Goat Exercises, which show their own source), then `release/build-from-lc-dsc.sh` builds it with the staged gtk+3.0 as siblings until a round publishes it. GIMP's own test suite is run by the proof, not in the build (`nocheck`).

## Credits

- GIMP, by its developers: the files changed here are, in GIMP's own git history, chiefly the work of Michael Natterer, Sven Neumann, Martin Nordholts, Jehan, Ell, Øyvind Kolås, Simon Budig, Bruno Lopes, Alx Sa, William Skaggs, Alexia Death, Alexandre Prokoudine, Henrik Brix Andersen and Niels De Graef, among the many people GIMP's `AUTHORS` names; Spencer Kimball and Peter Mattis started it.
- Debian's GIMP maintainers (the Debian GNOME team; `debian/control` names the uploaders), whose 3.2.8-1 package is the base.
- The stereo GtkGLArea of the edition's GTK 3 (queue row 137, milestone 4) and the stereo pictures plug-in (queue row 101, round 1), both Sparky Stereo OS.
- Diolinux, for PhotoGIMP, where the plug-in was first written.

## gimp 3.2.8-1+stereo3d2+lc1: depth layers (queue row 137's milestone 2, with row 148)

Daniel's design (2026-10-15): a layer type that groups other layers at one depth value the artist sets, with three decimals; one key held with the tool's normal 2D movement pops it, another sinks it.

- `patches/stereo3d-depth-layers.patch`: `GimpDepthLayer` (a layer group whose depth is its persistent parasite `gimp-depth-layer`), each eye's picture (`GimpEyeProjectable`: copies of the layers' mode nodes over the eye's own picture below, each depth layer's content and mask moved by `gimp:depth-shift`, which calls the stereo policy library), the stereo canvas's third kind of image, Layer > New Depth Layer, the Depth row of the Layers dock, the pop (8) and sink (7) keys, the PDB group `depth_layer` (core only), and XCF loading.
- `patches/stereo3d-depth-layers-po.patch`: the eighteen strings in nine languages.
- `make-source-2.sh`: the successor of the staged +stereo3d1+lc1 (`source-stereo3d1.sha256`) through `repo/lc-successor.py --in-place --overlay --reapply-patches`, which runs quilt: the image named to `build.sh` needs it (sparky-lc-migration:20261020 has none; the lane built with that image plus quilt 0.69-1); `build.sh` builds it with the staged gtk+3.0 and stereo-layer 1.24.0 as siblings.
- Dependencies added: Build-Depends `libstereo-policy-dev (>= 1.24.0)` (stereo-layer 1.24.0, staged with this milestone); gimp Recommends `gimp-stereo-pictures` (the exports of a stereo image and of depth layers; a Depends would be a cycle, since the plug-in depends on gimp).
- The PDB files are written by pdbgen from `pdb/groups/depth_layer.pdb` during the build; the patch carries what it generates (`app/pdb/depth-layer-cmds.c`, `internal-procs.c` and `.h`), so a build without perl's run gives the same files.

Credits: GIMP's authors of the files changed (from GIMP's own history: Michael Natterer, Ell, Jehan, Øyvind Kolås, Sven Neumann, Alexia Death and the GIMP developers), Debian's GNOME team for the 3.2.8-1 package.
