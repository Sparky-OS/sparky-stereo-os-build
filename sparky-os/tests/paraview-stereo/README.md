# ParaView and VTK in stereo (ORDER 50, step 5)

The proofs of the vtk9 and paraview recipes (`sparky-os/packages/vtk9`, `sparky-os/packages/paraview`), run in throwaway containers on a virtual Stereo KWin; nothing reaches a desktop.

## vtk-quad-buffer-blit

A program with no ParaView: a `QVTKOpenGLStereoWidget` in Crystal Eyes stereo draws a turning cone for 60 frames, and VTK's `Error in cache state for GL_DRAW_BUFFER` warnings are counted through the output window's `WarningEvent`.
Exit 0: a stereo context and no such warning; 1: warnings (the count is printed); 77: the window got no stereo context, so nothing was tested.
Build it against Debian's `libvtk9-dev` and `libvtk9-qt-dev` (`cmake -S . -B build && cmake --build build`); run it inside a Stereo KWin session (`rig/qb-case.sh`).
On Debian's vtk9 9.6.2+ds-3 it fails on both routes and both cards; on the edition's 9.6.2+ds-3+stereo3d1 it passes.

## rig

The lane's rig, with its paths (`S`, the lane scratch; `L`, the lane folder with its Docker socket) set at the top of each script; copy them and change those two lines to run them elsewhere.

- `make-rig.sh`: the rig image from `debian:testing` (by digest) with the published tree at pin 1001 and Debian's paraview; `make-green.sh` adds staged packages through apt from a flat repository (`flat-index.py`, Origin "Sparky Stereo OS"), keeping apt's plan; `make-review-images.sh` makes every image of the review from the stage.
- `run-case.sh NAME IMAGE CASE.sh VAR=value...`: one fresh container and Stereo KWin session per run (`session.sh`); `GPU=nvidia` for the RTX 3060 through CDI with the session's zink route.
- `pv-case.sh`: ParaView with the two-square fixture `two.vtk` (options `PV_STEREO`, `PV_SETTINGS`, `PV_EXTRA`, `MENU=1`); writes the log, the draw-buffer warning count, the declarations, KWin's window list, the loaded VTK libraries and two captures; `pv_analyze.py` measures the pair against VTK's closed form.
- `pv-refuse-case.sh`: each former output type on the command line, in the language of `LANG`.
- `pv-settings-case.sh`: Edit > Settings..., its Render View tab searched for "stereo", then the Properties panel searched for it (`PV_ARGS` passes ParaView options; `OPEN_COMBO=1` opens Debian's Stereo Type list). The dialog is driven by keys only: clicks inside it did not land where the capture shows them, while clicks in the main window did.
- `vtk9-after.sh`: after the vtk9 build, its stage, comparison, tree removal, the paraview build, the green image and rows.
- `pv-noareas-case.sh` (as `SESSION=`): ParaView on a bare X server (no compositor, no stereo announced), captured through X (`xshot.py`).
- `red-batch.sh`, `qb-batch.sh`, `g3-batch.sh`: the red rows (Debian's packages), the reproducer's rows, and the edition ParaView's rows.
- `compare-debs.py`: a package against the one it replaces, file by file (paths, owners, modes, bytes; Lean Code projections checked against the manifest's `sha_hr`; ELF NEEDED, SONAME and defined dynamic symbols; control fields).
- `stage.py`: a source closure (the `.dsc` and every file it names, the `.changes` and every file it names, the build record, the log) with `SHA256SUMS`.
- `run-recipe.sh`, `make-builder.sh`, `archive.json`: the builds, with the temporary folder and the link gate's scratch inside the build folder. The builder's apt reads its certificates from `/run/host-ca.crt`: pass `EXTRA_MOUNTS="-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro"` whenever `PRE` runs apt.
- `apt-upgrade-sim.sh`: every architecture-dependent package of Debian's vtk9 and paraview installed on the published tree, then the stage added and `apt-get -s full-upgrade` (Inst, Remv, Conf lines).
- `vtk-progs-batch.sh`, `prog-case.sh`, `prog_analyze.py`: each edition program that loads vtk9 (F3D published and staged, the model viewer, the Plasma theme studio, FreeCAD) started on Debian's vtk9 and on the edition's, its window's content measured and the two compared.
- `i6-batch.sh`, `i6-batch2.sh`, `i6-final.sh`, `jmol-case.sh`, `jmol-menu-case.sh`, `mpl-case.sh`, `mpl_case.py`, `jmol_analyze.py`, `mpl_analyze.py`, `i6/`: Jmol's and the plot module's rows in other languages (row 50 step 5, item 6): the pair, the told-once sentences, the loaders of all eight languages, Jmol's Display menu over its 3D area.
